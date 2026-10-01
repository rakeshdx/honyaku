import XCTest
@testable import Honyaku

// MARK: - Fakes

/// A microphone that returns the samples a test gives it.
final class FakeAudioCapture: AudioCapturing {
    var onDeviceDisconnected: (() -> Void)?
    var onLevel: ((Double) -> Void)?
    var samples: [Float] = PipelineTests.speech
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func prepare() {}
    func startCapture() throws { startCount += 1 }
    func stopCaptureAndFlushBoth() throws -> (url: URL, floatArray: [Float]) {
        // Never created: deleteTempFile only removes files under the temporary directory
        (FileManager.default.temporaryDirectory.appendingPathComponent("honyaku-test-\(UUID().uuidString).wav"), samples)
    }
    func cancelCapture() { cancelCount += 1 }
}

final class FakeTranscription: ASRService, @unchecked Sendable {
    var text = "hello world"
    var language = "en"
    private(set) var calls = 0
    private(set) var hints: [SpeechHints] = []
    /// Runs when transcription is called, to check what earlier stages did.
    var onTranscribe: (() -> Void)?

    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, samples16k: nil, modelID: modelID, hints: .none)
    }

    func transcribe(audioURL: URL, samples16k: [Float]?, modelID: String,
                    hints: SpeechHints) async throws -> TranscriptionResult {
        calls += 1
        self.hints.append(hints)
        onTranscribe?()
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

final class FakePaste: PasteServiceProtocol, @unchecked Sendable {
    private(set) var pasted: [String] = []
    private(set) var clears = 0

    func paste(_ text: String) async throws { pasted.append(text) }
    func clearTranscriptFromPasteboard(after delay: Double) async { clears += 1 }
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

    func frontmostApp() -> TargetApp? { front }
    func pasteTarget() -> PasteTarget { PasteTarget(app: front, honyakuIsFrontmost: honyakuIsFrontmost) }
}

@MainActor
final class RecordingPreparer: DictationContextPreparer {
    var log: [String] = []
    func prepare(_ context: inout DictationContext) {
        log.append("prepare")
        context.speechHints.glossary.append("Paramount+")
        context.cleanupRules.append("Write Paramount+ exactly.")
    }
}

@MainActor
struct SuffixStage: TextStage {
    let suffix: String
    func apply(_ text: String, context: DictationContext) -> String { text + suffix }
}

// MARK: - Tests

@MainActor
final class PipelineTests: XCTestCase {
    /// Loud enough to pass the silence gate: a steady -6 dBFS for one second at 16 kHz.
    static let speech = [Float](repeating: 0.5, count: 16_000)

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

    private func makePipeline(stages: PipelineStages = .none) -> TranscriptionPipeline {
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
    }

    func testHonyakuInFrontSavesWithoutPasting() async {
        targets.honyakuIsFrontmost = true
        await dictate(makePipeline())

        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage))
    }

    func testFirstRunTestShowsTheResultInTheWindow() async {
        appState.beginFirstRunTest()
        targets.honyakuIsFrontmost = true
        await dictate(makePipeline())

        XCTAssertEqual(appState.firstRunTestTranscript, "hello world")
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
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
        transcription.onTranscribe = { [unowned preparer] in preparer.log.append("transcribe") }
        cleanup.respond = { $0 + " [cleaned]" }
        let stages = PipelineStages(preparers: [preparer],
                                    afterTranscription: [SuffixStage(suffix: " [after]")],
                                    final: [SuffixStage(suffix: " [final]")])
        await dictate(makePipeline(stages: stages))

        XCTAssertEqual(preparer.log, ["prepare", "transcribe"])
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
    func apply(_ text: String, context: DictationContext) -> String {
        seen = context
        return text
    }
}
