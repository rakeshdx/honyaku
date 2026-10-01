import XCTest
@testable import Honyaku

// MARK: - Fakes

/// A microphone that returns the samples a test gives it.
final class FakeAudioCapture: AudioCapturing {
    var onDeviceDisconnected: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    var samples: [Float] = PipelineTests.speech
    /// Thrown when the recording stops, e.g. a missing microphone permission.
    var stopError: Error?
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func prepare() {}
    func startCapture() throws { startCount += 1 }
    func stopCaptureAndFlushBoth() throws -> (url: URL, floatArray: [Float]) {
        if let stopError { throw stopError }
        // Never created: deleteTempFile only removes files under the temporary directory
        return (FileManager.default.temporaryDirectory.appendingPathComponent("honyaku-test-\(UUID().uuidString).wav"), samples)
    }
    func cancelCapture() { cancelCount += 1 }
}

final class FakeTranscription: ASRService, @unchecked Sendable {
    var text = "hello world"
    var language = "en"
    /// Thrown instead of a result, e.g. a speech-model timeout.
    var error: Error?
    private(set) var calls = 0
    /// What each call was given: proves the preparers ran first.
    private(set) var hints: [SpeechHints] = []
    private(set) var modelIDs: [String] = []

    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, samples16k: nil, modelID: modelID, hints: .none)
    }

    func transcribe(audioURL: URL, samples16k: [Float]?, modelID: String,
                    hints: SpeechHints) async throws -> TranscriptionResult {
        calls += 1
        self.hints.append(hints)
        modelIDs.append(modelID)
        if let error { throw error }
        return TranscriptionResult(rawText: text, language: language, durationSeconds: 1, timedSegments: [])
    }

    func prepareIfDownloaded(modelID: String) async throws {}
}

final class FakeDiarization: DiarizationServiceProtocol, @unchecked Sendable {
    func diarize(audioArray: [Float]) async throws -> [DiarizedSegment] { [] }
}

struct CleanupFailure: Error {}

final class FakeCleanup: CleanupServiceProtocol, @unchecked Sendable {
    /// The model's answer for a transcript; nil makes `clean` throw.
    var respond: ((String) -> String)? = { $0 }
    private(set) var inputs: [String] = []
    private(set) var requests: [CleanupRequest] = []

    func clean(_ rawText: String, request: CleanupRequest) async throws -> String {
        inputs.append(rawText)
        requests.append(request)
        guard let respond else { throw CleanupFailure() }
        return respond(rawText)
    }

    func prepare() async throws {}
}

/// Never touches a real pasteboard. A clear can be held open, like the real 5-second wait.
@MainActor
final class FakePaste: PasteServiceProtocol {
    /// Thrown instead of pasting, e.g. ⌘V couldn't be posted.
    var error: Error?
    /// When on, a clipboard clear waits for `releaseClears()`.
    var holdClears = false
    private(set) var pasted: [String] = []
    private(set) var clears = 0
    private var heldClears: [CheckedContinuation<Void, Never>] = []
    private var clearWaiters: [CheckedContinuation<Void, Never>] = []

    func paste(_ text: String) async throws {
        if let error { throw error }
        pasted.append(text)
    }

    func clearTranscriptFromPasteboard(after delay: Double) async {
        clears += 1
        clearWaiters.forEach { $0.resume() }
        clearWaiters = []
        guard holdClears else { return }
        await withCheckedContinuation { heldClears.append($0) }
    }

    /// Returns once a clear has started.
    func waitForClear() async {
        guard clears == 0 else { return }
        await withCheckedContinuation { clearWaiters.append($0) }
    }

    func releaseClears() {
        heldClears.forEach { $0.resume() }
        heldClears = []
    }
}

@MainActor
final class FakeModels: ModelAvailability {
    var missing: Set<String> = []
    private(set) var downloads: [String] = []

    func isInstalled(_ model: ModelInfo) -> Bool { !missing.contains(model.id) }
    func startDownload(_ model: ModelInfo) { downloads.append(model.id) }
    func downloadMessage(for model: ModelInfo) -> String { "Downloading \(model.id)" }
}

@MainActor
final class FakeTargets: TargetAppResolving {
    var front: TargetApp? = TargetApp(bundleID: "com.tinyspeck.slackmacgap", pid: 42)
    var honyakuIsFrontmost = false
    var secureField = false

    func frontmostApp() -> TargetApp? { front }
    func pasteTarget() -> PasteTarget {
        PasteTarget(app: front, honyakuIsFrontmost: honyakuIsFrontmost, isSecureField: secureField)
    }
}

@MainActor
final class RecordingPreparer: DictationContextPreparer {
    private(set) var calls = 0
    private(set) var seen: DictationContext?
    func prepare(_ context: inout DictationContext) {
        calls += 1
        seen = context
        context.speechHints.glossary.append("Paramount+")
        context.cleanupRules.append("Write Paramount+ exactly.")
    }
}

@MainActor
struct SuffixStage: TextStage {
    let suffix: String
    func apply(_ text: String, context: inout DictationContext) -> String { text + suffix }
}

/// Adds a notice, the way Rewrite will when a rewrite can't run.
@MainActor
struct NoticeStage: TextStage {
    let notice: String
    func apply(_ text: String, context: inout DictationContext) -> String {
        context.notices.append(notice)
        return text
    }
}

/// Replaces the text, e.g. with whitespace only.
@MainActor
struct ReplaceStage: TextStage {
    let text: String
    func apply(_ text: String, context: inout DictationContext) -> String { self.text }
}

// MARK: - Tests

@MainActor
final class PipelineTests: XCTestCase {
    /// Loud enough to pass the silence gate: a steady -6 dBFS for one second at 16 kHz.
    nonisolated static let speech = [Float](repeating: 0.5, count: 16_000)

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var appState: AppState!
    private var store: TranscriptStore!
    private var audio: FakeAudioCapture!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var models: FakeModels!
    private var targets: FakeTargets!

    override func setUp() {
        super.setUp()
        suiteName = "HonyakuPipelineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        appState = AppState(defaults: defaults)
        store = TranscriptStore(inMemory: [])
        audio = FakeAudioCapture()
        transcription = FakeTranscription()
        cleanup = FakeCleanup()
        paste = FakePaste()
        models = FakeModels()
        targets = FakeTargets()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makePipeline(stages: PipelineStages? = nil) -> TranscriptionPipeline {
        let services = PipelineServices(audioCapture: audio, transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: models, targets: targets)
        return TranscriptionPipeline(appState: appState, transcriptStore: store, services: services,
                                     stages: stages, defaults: defaults)
    }

    /// One push-to-talk: start, stop, and wait for the run to finish.
    private func dictate(_ pipeline: TranscriptionPipeline, beforeStop: () -> Void = {}) async {
        pipeline.startRecording()
        XCTAssertEqual(appState.status, .recording)
        beforeStop()
        await pipeline.stopRecordingAndProcess()?.value
    }

    func testPlainDictationPastesAndSaves() async {
        cleanup.respond = { _ in "Hello world." }
        await dictate(makePipeline())

        XCTAssertEqual(paste.pasted, ["Hello world."])
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.rawText, "hello world")
        XCTAssertEqual(store.entries.first?.cleanedText, "Hello world.")
        XCTAssertEqual(appState.status, .idle)
    }

    func testDictationLanguageAndSpeechModelReachThePreparersAndModel() async {
        defaults.set("it", forKey: TranscriptionService.dictationLanguageKey)
        let preparer = RecordingPreparer()
        await dictate(makePipeline(stages: PipelineStages(preparers: [preparer])))

        XCTAssertEqual(preparer.seen?.speechModelID, appState.selectedSpeechModelID)
        XCTAssertEqual(preparer.seen?.speechHints.language, "it")
        XCTAssertEqual(transcription.hints.first?.language, "it")
        XCTAssertEqual(transcription.modelIDs, [appState.selectedSpeechModelID])
    }

    func testAutoDetectPassesNoLanguage() async {
        defaults.set("", forKey: TranscriptionService.dictationLanguageKey)
        await dictate(makePipeline())
        XCTAssertNil(transcription.hints.first?.language)
    }

    func testHistoryRecordsModeAndTargetApp() async {
        await dictate(makePipeline())
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertEqual(store.entries.first?.appBundleID, "com.tinyspeck.slackmacgap")
    }

    func testTargetAppIsTakenAtStartAndAtPaste() async {
        let probe = ContextProbe()
        let pipeline = makePipeline(stages: PipelineStages(final: [probe]))
        pipeline.startRecording()
        // The user switches to Terminal while speaking
        targets.front = TargetApp(bundleID: "com.apple.Terminal", pid: 7)
        await pipeline.stopRecordingAndProcess()?.value

        XCTAssertEqual(probe.seen?.appAtStart?.category, .chat)
        XCTAssertEqual(probe.seen?.appAtPaste?.category, .terminal)
        XCTAssertEqual(store.entries.first?.appBundleID, "com.apple.Terminal")
    }

    func testSilenceNeverReachesTheSpeechModel() async {
        audio.samples = [Float](repeating: 0, count: 16_000)
        await dictate(makePipeline())

        XCTAssertEqual(transcription.calls, 0)
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .idle)
    }

    func testEmptyTranscriptIsDiscarded() async {
        transcription.text = "   "
        await dictate(makePipeline())

        XCTAssertTrue(cleanup.inputs.isEmpty)
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .idle)
    }

    func testFailedCleanupFallsBackToTheTranscriptWithoutFillers() async {
        transcription.text = "um hello world"
        cleanup.respond = nil
        await dictate(makePipeline())

        XCTAssertEqual(cleanup.inputs, ["um hello world"])
        XCTAssertEqual(paste.pasted, ["hello world"])
        XCTAssertEqual(appState.status, .idle)
    }

    func testNonEnglishKeepsFillerLikeWords() async {
        transcription.text = "um ein Beispiel"
        transcription.language = "de"
        cleanup.respond = nil
        await dictate(makePipeline())

        XCTAssertEqual(cleanup.requests.first?.englishFillers, false)
        XCTAssertEqual(paste.pasted, ["um ein Beispiel"])
    }

    func testCleanupOffSkipsTheModel() async {
        appState.cleanupEnabled = false
        transcription.text = "uh hello world"
        await dictate(makePipeline())

        XCTAssertTrue(cleanup.inputs.isEmpty)
        XCTAssertEqual(paste.pasted, ["hello world"])
    }

    func testCleanupUsesTheSavedPrompt() async {
        appState.cleanupPrompt = "Custom prompt"
        await dictate(makePipeline())
        XCTAssertEqual(cleanup.requests.first?.systemPrompt, "Custom prompt")
        XCTAssertEqual(cleanup.requests.first?.faithfulness, .strict)
        XCTAssertNil(cleanup.requests.first?.maxTokens)
    }

    func testMissingCleanupModelDownloadsAndPastesTheWords() async {
        models.missing = [appState.selectedCleanupModelID]
        await dictate(makePipeline())

        XCTAssertEqual(models.downloads, [appState.selectedCleanupModelID])
        XCTAssertTrue(cleanup.inputs.isEmpty)
        XCTAssertEqual(paste.pasted, ["hello world"])
    }

    func testMissingSpeechModelDownloadsAndReports() async {
        models.missing = [appState.selectedSpeechModelID]
        await dictate(makePipeline())

        XCTAssertEqual(models.downloads, [appState.selectedSpeechModelID])
        XCTAssertEqual(transcription.calls, 0)
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(appState.lastError, "Downloading \(appState.selectedSpeechModelID)")
        XCTAssertEqual(appState.status, .error("Downloading \(appState.selectedSpeechModelID)"))
    }

    func testHonyakuInFrontSavesWithoutPasting() async {
        targets.honyakuIsFrontmost = true
        await dictate(makePipeline())

        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.entries.first?.appBundleID, "Honyaku isn't where the text went")
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage))
    }

    func testPasswordFieldIsNeitherPastedNorSaved() async {
        targets.secureField = true
        await dictate(makePipeline())

        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(paste.clears, 0, "Nothing was written to the pasteboard")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    func testPasswordFieldInHonyakuItselfIsBlockedNotSaved() async {
        targets.secureField = true
        targets.honyakuIsFrontmost = true
        await dictate(makePipeline())

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    func testAStageCanSendTextToHistoryOnly() async {
        let stages = PipelineStages(final: [HistoryOnlyStage(notice: "Saved to History — paste is off for Slack")])
        await dictate(makePipeline(stages: stages))

        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.appBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(appState.status, .error("Saved to History — paste is off for Slack"))
    }

    func testNoticesShowOnceAfterThePaste() async {
        let stages = PipelineStages(afterTranscription: [NoticeStage(notice: "Couldn't rewrite: pasted your words as dictated")])
        await dictate(makePipeline(stages: stages))

        XCTAssertEqual(paste.pasted, ["hello world"])
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(appState.status, .error("Couldn't rewrite: pasted your words as dictated"))
    }

    func testNoticesFollowTheRoutingNotice() async {
        targets.honyakuIsFrontmost = true
        let stages = PipelineStages(final: [NoticeStage(notice: "Second.")])
        await dictate(makePipeline(stages: stages))
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage + " Second."))
    }

    func testNoNoticesForAFirstRunTest() async {
        appState.beginFirstRunTest()
        let stages = PipelineStages(final: [NoticeStage(notice: "Ignored.")])
        await dictate(makePipeline(stages: stages))
        XCTAssertEqual(appState.firstRunTestTranscript, "hello world")
        XCTAssertEqual(appState.status, .idle)
    }

    func testWhitespaceOnlyTextIsNotPasted() async {
        await dictate(makePipeline(stages: PipelineStages(final: [ReplaceStage(text: "  \n")])))

        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .idle)
    }

    // MARK: Failures

    func testSpeechModelFailureReportsAndClearsThePasteboard() async {
        transcription.error = TranscriptionError.timedOut
        await dictate(makePipeline())

        guard case .error(let message) = appState.status else { return XCTFail("Expected an error, got \(appState.status)") }
        XCTAssertTrue(message.hasPrefix("The dictation didn't finish:"), message)
        XCTAssertEqual(paste.clears, 1)
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testFailedPasteReportsAtOnceAndClearsOnce() async {
        paste.error = PasteError.simulationFailed
        await dictate(makePipeline())

        guard case .error(let message) = appState.status else { return XCTFail("Expected an error, got \(appState.status)") }
        XCTAssertTrue(message.hasPrefix("The dictation didn't finish:"), message)
        XCTAssertEqual(paste.clears, 1, "Cleared once, not once inside the run and again outside it")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testMissingMicrophonePermissionAsksForIt() async {
        audio.stopError = AudioCaptureError.noMicrophonePermission
        await dictate(makePipeline())

        XCTAssertEqual(appState.status, .error("Honyaku needs microphone access. Turn it on in System Settings → Privacy & Security → Microphone."))
        XCTAssertEqual(paste.clears, 0, "Nothing reached the pasteboard")
        XCTAssertEqual(transcription.calls, 0)
    }

    func testAFailedDictationNeverInterruptsTheNextRecording() async {
        transcription.error = TranscriptionError.timedOut
        paste.holdClears = true
        let pipeline = makePipeline()
        pipeline.startRecording()
        let failed = pipeline.stopRecordingAndProcess()

        // The failed run is now waiting to clear the pasteboard; the user presses Control again
        await paste.waitForClear()
        guard case .error = appState.status else { return XCTFail("Expected the error first, got \(appState.status)") }
        pipeline.startRecording()
        XCTAssertEqual(appState.status, .recording)

        paste.releaseClears()
        await failed?.value
        XCTAssertEqual(appState.status, .recording, "The failed run must not end the new recording")
        XCTAssertEqual(audio.startCount, 2)

        // And the new recording still transcribes when Control is released
        transcription.error = nil
        await pipeline.stopRecordingAndProcess()?.value
        XCTAssertEqual(paste.pasted, ["hello world"])
        XCTAssertEqual(appState.status, .idle)
    }

    func testFirstRunTestShowsTheResultInTheWindow() async {
        appState.beginFirstRunTest()
        targets.honyakuIsFrontmost = true
        await dictate(makePipeline())

        XCTAssertEqual(appState.firstRunTestTranscript, "hello world")
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .idle)
    }

    func testTestDictationEndedMidRecordingIsDiscarded() async {
        appState.beginFirstRunTest()
        await dictate(makePipeline()) { appState.endFirstRunTest() }

        XCTAssertNil(appState.firstRunTestTranscript)
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .idle)
    }

    func testStagesRunInOrder() async {
        let preparer = RecordingPreparer()
        cleanup.respond = { $0 + " [cleaned]" }
        let stages = PipelineStages(preparers: [preparer],
                                    afterTranscription: [SuffixStage(suffix: " [after]")],
                                    final: [SuffixStage(suffix: " [final]")])
        await dictate(makePipeline(stages: stages))

        // The speech model received the preparer's hints, so the preparer ran first
        XCTAssertEqual(preparer.calls, 1)
        XCTAssertEqual(transcription.hints.first?.glossary, ["Paramount+"])
        XCTAssertEqual(cleanup.inputs, ["hello world [after]"])
        XCTAssertEqual(cleanup.requests.first?.extraRules, ["Write Paramount+ exactly."])
        XCTAssertEqual(paste.pasted, ["hello world [after] [cleaned] [final]"])
        // History keeps what the speech model heard and what was pasted
        XCTAssertEqual(store.entries.first?.rawText, "hello world")
        XCTAssertEqual(store.entries.first?.cleanedText, "hello world [after] [cleaned] [final]")
    }

    func testCancelledRecordingDoesNothing() async {
        let pipeline = makePipeline()
        pipeline.startRecording()
        pipeline.cancelRecording()

        XCTAssertEqual(audio.cancelCount, 1)
        XCTAssertNil(pipeline.stopRecordingAndProcess())
        XCTAssertEqual(transcription.calls, 0)
        XCTAssertEqual(appState.status, .idle)
    }

    func testSettingsAreSavedToTheInjectedDefaults() {
        appState.cleanupEnabled = false
        appState.cleanupPrompt = "Custom prompt"
        XCTAssertEqual(defaults.object(forKey: "cleanupEnabled") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "cleanupPrompt"), "Custom prompt")
        XCTAssertFalse(AppState(defaults: defaults).cleanupEnabled)
    }
}

/// Records the context the final stages saw.
@MainActor
final class ContextProbe: TextStage {
    private(set) var seen: DictationContext?
    func apply(_ text: String, context: inout DictationContext) -> String {
        seen = context
        return text
    }
}
