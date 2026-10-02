import XCTest
@testable import Honyaku

/// The three features together: the real Vocabulary, Rewrite and Per-app stages in the app's order, with fake
/// services, a fake password probe and a temporary folder for every feature store.
@MainActor
final class MergedFeaturesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var environment: FeatureEnvironment!
    private var appState: AppState!
    private var history: TranscriptStore!
    private var probe: FakePasteGuardProbe!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var targets: FakeTargets!

    private let terminal = TargetApp(bundleID: "com.apple.Terminal", pid: 7, name: "Terminal")

    override func setUp() {
        super.setUp()
        suiteName = "HonyakuMergedFeaturesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        environment = FeatureEnvironment(
            directory: FileManager.default.temporaryDirectory.appending(path: "honyaku-merged-\(UUID().uuidString)"),
            defaults: defaults)
        appState = AppState(defaults: defaults)
        history = TranscriptStore(inMemory: [])
        probe = FakePasteGuardProbe()
        transcription = FakeTranscription()
        transcription.text = "add a retry to the paramount plus uploader"
        cleanup = FakeCleanup()
        paste = FakePaste()
        targets = FakeTargets()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: environment.directory)
        super.tearDown()
    }

    /// The live order (`PipelineStages.live`), but with the fake probe instead of the system's.
    private func makePipeline() -> TranscriptionPipeline {
        let stages = PipelineStages.combined([
            VocabularyStages.make(environment),
            RewriteStages.make(environment),
            PerAppStages.make(store: environment.store(AppProfilesStore.self), probe: probe),
        ])
        let services = PipelineServices(audioCapture: FakeAudioCapture(), transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: FakeModels(), targets: targets)
        return TranscriptionPipeline(appState: appState, transcriptStore: history, services: services,
                                     stages: stages, defaults: defaults)
    }

    private func rewrite() async {
        let pipeline = makePipeline()
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess(mode: .rewrite)?.value
    }

    func testSettingsTabsAreInTheAgreedOrder() {
        XCTAssertEqual(SettingsWindowController.Tab.allCases.map(\.rawValue),
                       ["general", "models", "dictation", "vocabulary", "rewrite", "apps", "history", "privacy"])
    }

    func testRewriteIntoATerminalIsOneLineThroughThePerAppRules() async {
        targets.front = terminal
        cleanup.respond = { _ in "Add a retry to “upload()” in the uploader\nand run the tests.\n" }
        await rewrite()

        // Joined by Rewrite, then the Terminals rules: straight quotes, no final full stop, no trailing newline
        XCTAssertEqual(paste.pasted, ["Add a retry to \"upload()\" in the uploader and run the tests"])
        XCTAssertEqual(history.entries.first?.rewriteTemplateID, "agentPrompt")
        XCTAssertEqual(history.entries.first?.appBundleID, terminal.bundleID)
    }

    func testRewriteIntoATerminalWithKeepLineBreaksIsStillOneLine() async {
        let store = environment.store(AppProfilesStore.self)
        var rules = store.profiles.rules(for: .terminal)
        rules.lineBreaks = .keep
        store.profiles.setRules(rules, for: .terminal)
        targets.front = terminal
        cleanup.respond = { _ in "First line\nSecond line" }
        await rewrite()

        XCTAssertEqual(paste.pasted, ["First line Second line"], "Rewrite's own join still protects terminals")
    }

    func testPasswordGuardStillBlocksARewrite() async {
        targets.front = terminal
        probe.reading.focusedSubrole = "AXSecureTextField"
        cleanup.respond = { _ in "Rewritten text" }
        await rewrite()

        XCTAssertEqual(paste.pasted, [])
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    func testVocabularyCorrectsAndReachesTheRewritePrompt() async throws {
        _ = try environment.store(VocabularyStore.self).add(term: "Paramount+", heardAs: ["paramount plus"])
        targets.front = terminal
        cleanup.respond = { $0 }
        await rewrite()

        XCTAssertEqual(cleanup.inputs.first, "add a retry to the Paramount+ uploader", "corrected before the model")
        let rules = cleanup.requests.first?.extraRules ?? []
        XCTAssertTrue(rules.contains { $0.contains("Paramount+") }, "the keep-these-terms rule is in the rewrite prompt")
    }
}
