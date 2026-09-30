import AppKit

/// Where a finished dictation's text goes.
enum DictationDestination: Equatable {
    case paste
    /// Honyaku itself is in front: ⌘V would paste into its own window
    case saveOnly
    case firstRunTest
    /// Started in a first-run test that has since ended: never pasted, never saved
    case discard
}

/// Orchestrates: AudioCapture → WhisperKit → SpeakerKit → CleanupLLM → PasteService
@MainActor
final class TranscriptionPipeline {
    private let audioCapture = AudioCaptureService()
    private let transcription = TranscriptionService()
    private let diarization = DiarizationService()
    private let cleanup = CleanupService()
    private let paste = PasteService()
    private let transcriptStore: TranscriptStore
    private let appState: AppState
    private let downloads: ModelDownloads

    init(appState: AppState, transcriptStore: TranscriptStore) {
        self.appState = appState
        self.transcriptStore = transcriptStore
        downloads = ModelDownloads(appState: appState)
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
        for (key, id) in migrated where AppState.migratedSelectionKeys.contains(key) {
            if let model = ModelRegistry.model(id: id) { downloads.start(model) }
        }
        Task {
            try? await transcription.prepareIfDownloaded(modelID: modelID)
            if cleanupEnabled { try? await cleanup.prepare() }
        }
    }

    // MARK: - Routing

    static let savedWhileInFrontMessage = "Saved to History — Honyaku was in front"

    /// `recordedInTest` is the first-run test running when the recording started; `currentTest` is the
    /// one running now. A test result only reaches the window if that same test is still on screen.
    nonisolated static func destination(recordedInTest: Int?, currentTest: Int?,
                                        honyakuIsFrontmost: Bool) -> DictationDestination {
        if let recordedInTest {
            return recordedInTest == currentTest ? .firstRunTest : .discard
        }
        return honyakuIsFrontmost ? .saveOnly : .paste
    }

    // MARK: - Recording lifecycle

    /// The first-run test that was running when the current recording started, if any.
    private var recordingTestSession: Int?

    func startRecording() {
        guard !appState.status.isBusy else { return }
        // Clear any prior error so Control key works again after a failed pipeline run
        appState.clearError()
        do {
            try audioCapture.startCapture()
            recordingTestSession = appState.firstRunTestSession
            appState.inputLevel = 0
            appState.recordingStartedAt = Date()
            appState.status = .recording
        } catch {
            appState.setError("Couldn't start the microphone: \(error.localizedDescription) Check it's connected, or choose another in Settings > General.")
        }
    }

    func stopRecordingAndProcess() {
        guard appState.status == .recording else { return }
        appState.status = .transcribing
        appState.inputLevel = 0
        let testSession = recordingTestSession

        Task {
            do {
                let (audioURL, floatArray) = try audioCapture.stopCaptureAndFlushBoth()
                try await run(audioURL: audioURL, floatArray: floatArray, testSession: testSession)
            } catch AudioCaptureError.noMicrophonePermission {
                appState.setError("Honyaku needs microphone access. Turn it on in System Settings → Privacy & Security → Microphone.")
            } catch {
                appState.setError("The dictation didn't finish: \(error.localizedDescription) Try again.")
                await paste.clearTranscriptFromPasteboard(after: pasteboardClearDelay)
            }
            if case .error = appState.status {} else {
                appState.status = .idle
            }
        }
    }

    func cancelRecording() {
        // Only an active recording is cancelled — never overwrite an error or an in-flight pipeline run
        guard appState.status == .recording else { return }
        audioCapture.cancelCapture()
        appState.inputLevel = 0
        appState.status = .idle
    }

    // MARK: - Private pipeline

    private let pasteboardClearDelay: Double = 5.0

    private func run(audioURL: URL, floatArray: [Float], testSession: Int?) async throws {
        // Silence never reaches the speech model — Whisper invents "Thank you." for it
        if !floatArray.isEmpty, AudioCaptureService.isSilent(samples16k: floatArray) {
            TranscriptionService.deleteTempFile(audioURL)
            appState.status = .idle
            return
        }

        // Step 1: ASR (the service deletes audioURL on return; Parakeet reads the float samples directly)
        // Read the saved choice each time, as cleanup does, so switching models in Settings applies at once
        let modelID = UserDefaults.standard.string(forKey: "selectedSpeechModelID") ?? appState.selectedSpeechModelID
        // A missing model downloads in the background; this dictation returns rather than waiting minutes
        if let speechModel = ModelRegistry.model(id: modelID), !ModelInstaller.isInstalled(speechModel) {
            TranscriptionService.deleteTempFile(audioURL)
            downloads.start(speechModel)
            appState.setError(downloads.message(for: speechModel))
            return
        }
        let result = try await transcription.transcribe(audioURL: audioURL, samples16k: floatArray, modelID: modelID)
        // um/uh are fillers in English only — "um" is a word in German and Portuguese
        let englishFillers = result.language.lowercased().hasPrefix("en")

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

        // Step 3: Cleanup (optional)
        let cleanupPrompt = UserDefaults.standard.string(forKey: "cleanupPrompt") ?? CleanupService.defaultPrompt
        var finalText = labeledText
        let cleanupModel = ModelRegistry.model(
            id: UserDefaults.standard.string(forKey: "selectedCleanupModelID") ?? appState.selectedCleanupModelID)
        if appState.cleanupEnabled, let cleanupModel, !ModelInstaller.isInstalled(cleanupModel) {
            // Paste the speaker's words now; cleanup resumes once its model is downloaded
            downloads.start(cleanupModel)
        } else if appState.cleanupEnabled {
            do {
                let cleaned = try await cleanup.clean(labeledText, prompt: cleanupPrompt, englishFillers: englishFillers)
                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? labeledText : trimmed
            } catch {
                // Timeout, model not loaded, or any other error — fall back to labeled text
                finalText = labeledText
            }
        }

        // In English, um/umm/uh/hmm are never content, whatever the model (or no model) left in
        if englishFillers { finalText = CleanupService.removeUnambiguousFillers(finalText) }
        guard !finalText.isEmpty else {
            appState.status = .idle
            return
        }

        // Decided now, not when the recording started: the user may have closed first run or brought
        // Honyaku forward while this was transcribing
        let destination = Self.destination(recordedInTest: testSession, currentTest: appState.firstRunTestSession,
                                           honyakuIsFrontmost: NSApplication.shared.isActive)
        switch destination {
        case .discard:
            appState.status = .idle
            return
        case .firstRunTest:
            // First run's "Try it" step shows the result in the window: no paste, no history
            appState.firstRunTestTranscript = finalText
            return
        case .saveOnly:
            break
        case .paste:
            // Step 4: Paste
            do {
                try await paste.paste(finalText)
            } catch {
                await paste.clearTranscriptFromPasteboard(after: pasteboardClearDelay)
                throw error
            }
        }

        // Step 5: Persist to history (no content in log messages)
        let entry = TranscriptEntry(
            rawText: result.rawText,
            cleanedText: finalText,
            modelTier: modelID,
            durationSeconds: result.durationSeconds,
            hasSpeakerLabels: !segments.isEmpty
        )
        transcriptStore.save(entry)
        if destination == .saveOnly { appState.setError(Self.savedWhileInFrontMessage) }
    }
}
