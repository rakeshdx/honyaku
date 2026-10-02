import AppKit

/// Where a finished dictation's text goes.
enum DictationDestination: Equatable {
    case paste
    /// Saved to History, not pasted: Honyaku itself is in front, or the app is set to History only
    case saveOnly(notice: String?)
    /// A password field has focus: not pasted, not saved, nothing written to the pasteboard
    case blocked(notice: String)
    case firstRunTest
    /// Started in a first-run test that has since ended: never pasted, never saved
    case discard
}

/// The services a pipeline runs a dictation through. Tests pass fakes.
@MainActor
struct PipelineServices {
    var audioCapture: any AudioCapturing
    var transcription: any ASRService
    var diarization: any DiarizationServiceProtocol
    var cleanup: any CleanupServiceProtocol
    var paste: any PasteServiceProtocol
    var models: any ModelAvailability
    var targets: any TargetAppResolving

    static func live(appState: AppState) -> PipelineServices {
        PipelineServices(audioCapture: AudioCaptureService(), transcription: TranscriptionService(),
                         diarization: DiarizationService(), cleanup: CleanupService(), paste: PasteService(),
                         models: ModelDownloads(appState: appState), targets: TargetAppResolver())
    }
}

/// Orchestrates: AudioCapture → speech model → diarization → cleanup → paste, with feature stages
/// between them (see `PipelineStages`).
@MainActor
final class TranscriptionPipeline {
    private let audioCapture: any AudioCapturing
    private let transcription: any ASRService
    private let diarization: any DiarizationServiceProtocol
    private let cleanup: any CleanupServiceProtocol
    private let paste: any PasteServiceProtocol
    private let models: any ModelAvailability
    private let targets: any TargetAppResolving
    private let stages: PipelineStages
    private let transcriptStore: TranscriptStore
    private let appState: AppState
    /// Settings read on every dictation: `.standard` in the app, a private suite in tests.
    private let defaults: UserDefaults

    /// The app passes `PipelineStages.live(features)`; tests pass the stages they exercise (none by default).
    init(appState: AppState, transcriptStore: TranscriptStore, services: PipelineServices? = nil,
         stages: PipelineStages? = nil, defaults: UserDefaults = .standard,
         pasteboardClearDelay: Double = 5.0) {
        let services = services ?? .live(appState: appState)
        audioCapture = services.audioCapture
        transcription = services.transcription
        diarization = services.diarization
        cleanup = services.cleanup
        paste = services.paste
        models = services.models
        targets = services.targets
        self.stages = stages ?? .none
        self.appState = appState
        self.transcriptStore = transcriptStore
        self.defaults = defaults
        self.pasteboardClearDelay = pasteboardClearDelay
        audioCapture.prepare()
        audioCapture.onLevel = { [weak appState] level in
            MainActor.assumeIsolated { appState?.inputLevel = level }
        }
        audioCapture.onDeviceDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                switch self.appState.status {
                case .recording:
                    // Stop the live engine first; otherwise key-up bails on the error state and the tap leaks
                    self.cancelRecording()
                case .transcribing, .processing:
                    // The in-flight run owns the status; an error here would unblock a new recording
                    // whose state that run then overwrites, leaving the mic on
                    return
                default:
                    break
                }
                self.appState.setError("Microphone disconnected. Honyaku switched to the system default microphone.")
            }
        }
    }

    /// Loads the models in the background so the first dictation after launch isn't slower than the rest.
    /// Failures are ignored here; a real dictation reports them.
    func warmUp() {
        let modelID = appState.selectedSpeechModelID
        let cleanupEnabled = appState.cleanupEnabled
        // A migration picked models that may not be on disk yet: fetch them now, visibly, rather than
        // on the first dictation. Warm-up itself still never downloads.
        let migrated: [String: String] = ["selectedSpeechModelID": modelID,
                                          "selectedCleanupModelID": appState.selectedCleanupModelID]
        for (key, id) in migrated where appState.migratedSelectionKeys.contains(key) {
            if let model = ModelRegistry.model(id: id) { models.startDownload(model) }
        }
        let transcription = transcription
        let cleanup = cleanup
        // An older install may lack the cleanup model's chat template; fetch just that file, then load
        // the model so the next dictation doesn't wait for it
        if let cleanupModel = ModelRegistry.model(id: appState.selectedCleanupModelID) {
            models.repairChatTemplateIfNeeded(cleanupModel) { [appState] in
                guard appState.cleanupEnabled else { return }
                Task { try? await cleanup.prepare() }
            }
        }
        Task {
            try? await transcription.prepareIfDownloaded(modelID: modelID)
            if cleanupEnabled { try? await cleanup.prepare() }
        }
    }

    // MARK: - Routing

    nonisolated static let savedWhileInFrontMessage = "Saved to History — Honyaku was in front"
    nonisolated static let passwordFieldMessage = "Not pasted: a password field is focused"

    /// `context.firstRunTestSession` is the first-run test running when the recording started; `currentTest`
    /// is the one running now. A test result only reaches the window if that same test is still on screen.
    /// The password guard comes before "Honyaku in front", so Honyaku's own token field is blocked, not saved.
    nonisolated static func destination(for context: DictationContext, currentTest: Int?) -> DictationDestination {
        if let recordedInTest = context.firstRunTestSession {
            return recordedInTest == currentTest ? .firstRunTest : .discard
        }
        if context.isSecureField { return .blocked(notice: passwordFieldMessage) }
        if context.honyakuIsFrontmost { return .saveOnly(notice: savedWhileInFrontMessage) }
        if !context.pasteAllowed { return .saveOnly(notice: context.pasteOffNotice) }
        return .paste
    }

    // MARK: - Recording lifecycle

    /// The current recording's context, captured when it started.
    private var recordingContext: DictationContext?

    func startRecording(mode: DictationMode = .dictate) {
        guard !appState.status.isBusy else { return }
        // Clear any prior error so Control key works again after a failed pipeline run
        appState.clearError()
        do {
            try audioCapture.startCapture()
            recordingContext = DictationContext(mode: mode, appAtStart: targets.frontmostApp(),
                                                firstRunTestSession: appState.firstRunTestSession)
            appState.inputLevel = 0
            appState.recordingStartedAt = Date()
            appState.status = .recording
        } catch {
            appState.setError("Couldn't start the microphone: \(error.localizedDescription) Check it's connected, or choose another in Settings > General.")
        }
    }

    /// `mode` is the mode the gesture ended in; it wins over the one the recording started in.
    /// Returns the run, so tests can wait for it.
    @discardableResult
    func stopRecordingAndProcess(mode: DictationMode? = nil) -> Task<Void, Never>? {
        guard appState.status == .recording else { return nil }
        appState.status = .transcribing
        appState.inputLevel = 0
        var context = recordingContext ?? DictationContext()
        recordingContext = nil
        if let mode { context.mode = mode }

        return Task {
            var clearPasteboard = false
            do {
                let (audioURL, floatArray) = try audioCapture.stopCaptureAndFlushBoth()
                try await run(audioURL: audioURL, floatArray: floatArray, context: context)
            } catch AudioCaptureError.noMicrophonePermission {
                appState.setError("Honyaku needs microphone access. Turn it on in System Settings → Privacy & Security → Microphone.")
            } catch {
                appState.setError("The dictation didn't finish: \(error.localizedDescription) Try again.")
                clearPasteboard = true
            }
            // Settle the status before waiting: once it's an error (not busy), a new recording can start, and
            // nothing this run does afterwards may touch the status
            if case .error = appState.status {} else {
                appState.status = .idle
            }
            if clearPasteboard {
                await paste.clearTranscriptFromPasteboard(after: pasteboardClearDelay)
            }
        }
    }

    func cancelRecording() {
        // Only an active recording is cancelled — never overwrite an error or an in-flight pipeline run
        guard appState.status == .recording else { return }
        audioCapture.cancelCapture()
        recordingContext = nil
        appState.inputLevel = 0
        appState.status = .idle
    }

    // MARK: - Private pipeline

    /// How long a failed dictation's transcript may stay on the pasteboard before it's cleared.
    private let pasteboardClearDelay: Double

    private func run(audioURL: URL, floatArray: [Float], context startContext: DictationContext) async throws {
        var context = startContext
        // Silence never reaches the speech model — Whisper invents "Thank you." for it
        if !floatArray.isEmpty, AudioCaptureService.isSilent(samples16k: floatArray) {
            TranscriptionService.deleteTempFile(audioURL)
            appState.status = .idle
            return
        }

        // Step 1: ASR (the service deletes audioURL on return; Parakeet reads the float samples directly)
        // Read the saved choice each time, as cleanup does, so switching models in Settings applies at once
        let modelID = defaults.string(forKey: "selectedSpeechModelID") ?? appState.selectedSpeechModelID
        // A missing model downloads in the background; this dictation returns rather than waiting minutes
        if let speechModel = ModelRegistry.model(id: modelID), !models.isInstalled(speechModel) {
            TranscriptionService.deleteTempFile(audioURL)
            models.startDownload(speechModel)
            appState.setError(models.downloadMessage(for: speechModel))
            return
        }
        context.speechModelID = modelID
        context.speechHints.language = TranscriptionService.dictationLanguage(in: defaults)
        for preparer in stages.preparers { preparer.prepare(&context) }
        let result = try await transcription.transcribe(audioURL: audioURL, samples16k: floatArray, modelID: modelID,
                                                        hints: context.speechHints)
        context.language = result.language
        // um/uh are fillers in English only — "um" is a word in German and Portuguese
        context.englishFillers = result.language.lowercased().hasPrefix("en")

        // Empty / silence → discard
        guard !result.rawText.trimmingCharacters(in: .whitespaces).isEmpty else {
            appState.status = .idle
            return
        }

        appState.status = .processing

        // Step 2: Diarization (optional, after ASR, before cleanup)
        // Uses the pre-captured float array — no dependency on audioURL which is already deleted.
        var labeledText = result.rawText
        var segments: [DiarizedSegment] = []
        if appState.diarizationEnabled {
            segments = (try? await diarization.diarize(audioArray: floatArray)) ?? []
            let uniqueSpeakers = Set(segments.map(\.speakerID))
            if uniqueSpeakers.count > 1 {
                labeledText = DiarizationService.mergeWithTranscript(
                    rawText: result.rawText,
                    timedSegments: result.timedSegments,
                    diarizedSegments: segments
                )
            }
        }
        // After the speaker merge, which rebuilds the text from the speech model's segments
        labeledText = PipelineStages.apply(stages.afterTranscription, to: labeledText, context: &context)

        // Step 3: Cleanup (optional)
        var finalText = await llmStage(labeledText, context: &context)

        // In English, um/umm/uh/hmm are never content, whatever the model (or no model) left in
        if context.englishFillers { finalText = CleanupService.removeUnambiguousFillers(finalText) }

        // Decided now, not when the recording started: the user may have closed first run or brought
        // Honyaku forward while this was transcribing
        let target = targets.pasteTarget()
        context.appAtPaste = target.app
        context.honyakuIsFrontmost = target.honyakuIsFrontmost
        context.isSecureField = target.isSecureField
        finalText = PipelineStages.apply(stages.final, to: finalText, context: &context)
        // A stage may have left only whitespace (e.g. a lone "." dropped): nothing worth pasting
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.status = .idle
            return
        }

        let destination = Self.destination(for: context, currentTest: appState.firstRunTestSession)
        let routingNotice: String?
        switch destination {
        case .discard:
            appState.status = .idle
            return
        case .firstRunTest:
            // First run's "Try it" step shows the result in the window: no paste, no history, no notices
            appState.firstRunTestTranscript = finalText
            return
        case .blocked(let notice):
            // Nothing is pasted, saved or written to the pasteboard
            showNotices([notice] + context.notices)
            return
        case .saveOnly(let notice):
            routingNotice = notice
        case .paste:
            // Step 4: Paste. A failure throws at once; the caller reports it and clears the pasteboard
            try await paste.paste(finalText)
            routingNotice = nil
        }

        // Step 5: Persist to history (no content in log messages)
        let entry = TranscriptEntry(
            rawText: result.rawText,
            cleanedText: finalText,
            modelTier: modelID,
            durationSeconds: result.durationSeconds,
            hasSpeakerLabels: !segments.isEmpty,
            mode: context.mode.id,
            // Honyaku isn't where the text went when its own window was in front
            appBundleID: context.honyakuIsFrontmost ? nil : context.appAtPaste?.bundleID,
            pasted: destination == .paste
        )
        transcriptStore.save(entry)
        showNotices([routingNotice].compactMap { $0 } + context.notices)
    }

    /// Shows the run's messages once, at its end, the way errors are shown (orange, on the icon, the
    /// capsule and the General tab). The status stays busy until here, so no recording can start early.
    private func showNotices(_ notices: [String]) {
        guard !notices.isEmpty else { return }
        appState.setError(notices.joined(separator: " "))
    }

    /// The model step: word-for-word cleanup when it's on and its model is installed; otherwise the text
    /// as it is. Any failure falls back to the text it was given.
    private func llmStage(_ text: String, context: inout DictationContext) async -> String {
        guard appState.cleanupEnabled else { return text }
        let cleanupModel = ModelRegistry.model(
            id: defaults.string(forKey: "selectedCleanupModelID") ?? appState.selectedCleanupModelID)
        if let cleanupModel, !models.isInstalled(cleanupModel) {
            // Paste the speaker's words now; cleanup resumes once its model is downloaded
            models.startDownload(cleanupModel)
            context.notices.append(models.cleanupSkippedNotice(for: cleanupModel))
            return text
        }
        let request = CleanupRequest(
            systemPrompt: defaults.string(forKey: "cleanupPrompt") ?? CleanupService.defaultPrompt,
            extraRules: context.cleanupRules,
            englishFillers: context.englishFillers,
            protectedTerms: context.vocabularyTerms)
        do {
            let cleaned = try await cleanup.clean(text, request: request)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? text : trimmed
        } catch {
            // Timeout, model not loaded, or any other error — fall back to the text as it is
            return text
        }
    }
}
