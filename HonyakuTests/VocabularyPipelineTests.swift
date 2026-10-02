import XCTest
@testable import Honyaku

/// The vocabulary through the real pipeline with fake services: corrections, the Whisper hint and the
/// cleanup rule. Temporary folder and settings suite only.
@MainActor
final class VocabularyPipelineTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var appState: AppState!
    private var history: TranscriptStore!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var features: FeatureEnvironment!
    private var vocabulary: VocabularyStore!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: "honyaku-vocabulary-\(UUID().uuidString)")
        suiteName = "HonyakuVocabularyPipelineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        appState = AppState(defaults: defaults)
        history = TranscriptStore(inMemory: [])
        transcription = FakeTranscription()
        cleanup = FakeCleanup()
        paste = FakePaste()
        features = FeatureEnvironment(directory: directory, defaults: defaults)
        vocabulary = features.store(VocabularyStore.self)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func dictate(speechModel: String = "parakeet-tdt-v2", language: String? = nil) async {
        defaults.set(speechModel, forKey: "selectedSpeechModelID")
        if let language { defaults.set(language, forKey: TranscriptionService.dictationLanguageKey) }
        let services = PipelineServices(audioCapture: FakeAudioCapture(), transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: FakeModels(), targets: FakeTargets())
        let pipeline = TranscriptionPipeline(appState: appState, transcriptStore: history, services: services,
                                             stages: VocabularyStages.make(features), defaults: defaults)
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess()?.value
    }

    func testCorrectionsReachCleanupAndThePasteAndHistoryKeepsTheOriginal() async throws {
        try vocabulary.add(term: "Paramount+", heardAs: ["paramount plus"])
        transcription.text = "I'm testing paramount plus today."
        await dictate()

        XCTAssertEqual(cleanup.inputs, ["I'm testing Paramount+ today."])
        XCTAssertEqual(paste.pasted, ["I'm testing Paramount+ today."])
        XCTAssertEqual(history.entries.first?.rawText, "I'm testing paramount plus today.",
                       "History keeps the speech model's own words")
    }

    func testCorrectionsApplyWithCleanupOff() async throws {
        appState.cleanupEnabled = false
        try vocabulary.add(term: "Jira")
        transcription.text = "file a jira, then ping me"
        await dictate()
        XCTAssertEqual(paste.pasted, ["file a Jira, then ping me"])
        XCTAssertTrue(cleanup.inputs.isEmpty)
    }

    func testEditsApplyFromTheNextDictation() async throws {
        transcription.text = "file a jira"
        await dictate()
        try vocabulary.add(term: "Jira")
        await dictate()
        XCTAssertEqual(paste.pasted, ["file a jira", "file a Jira"])
    }

    func testCleanupPromptGetsTheRuleOnlyForTermsInTheTranscript() async throws {
        transcription.text = "file a jira about paramount plus"
        await dictate()
        XCTAssertEqual(cleanup.requests.last?.extraRules, [])

        try vocabulary.add(term: "Paramount+", heardAs: ["paramount plus"])
        try vocabulary.add(term: "Jira")
        try vocabulary.add(term: "POPS")
        await dictate()
        XCTAssertEqual(cleanup.requests.last?.extraRules, ["Write these terms exactly as listed: Paramount+, Jira."],
                       "POPS wasn't said, so it isn't listed (fix-rewrite-grounding)")

        transcription.text = "let's meet at noon"
        await dictate()
        XCTAssertEqual(cleanup.requests.last?.extraRules, [], "No listed term said: no rule")
    }

    func testWhisperWithEnglishOrAutoGetsTheGlossaryTopTermLast() async throws {
        try vocabulary.add(term: "Pluto TV")
        try vocabulary.add(term: "Jira")
        try vocabulary.add(term: "Off", heardAs: [])
        vocabulary.setEnabled(vocabulary.terms[2].id, false)

        await dictate(speechModel: "whisper-large-v3-turbo")
        XCTAssertEqual(transcription.hints.last?.glossary, ["Jira", "Pluto TV"], "Auto-detect")

        await dictate(speechModel: "whisper-large-v3-turbo", language: "en")
        XCTAssertEqual(transcription.hints.last?.glossary, ["Jira", "Pluto TV"], "English")
    }

    func testNoGlossaryForAnotherLanguageOrParakeetButCorrectionsStillApply() async throws {
        try vocabulary.add(term: "Jira")
        transcription.text = "un jira"

        await dictate(speechModel: "whisper-large-v3-turbo", language: "it")
        XCTAssertEqual(transcription.hints.last?.glossary, [])
        XCTAssertEqual(paste.pasted.last, "un Jira")

        defaults.removeObject(forKey: TranscriptionService.dictationLanguageKey)
        await dictate(speechModel: "parakeet-tdt-v2")
        XCTAssertEqual(transcription.hints.last?.glossary, [])
        XCTAssertEqual(paste.pasted.last, "un Jira")
    }

    func testSpeakerLabelsAreUntouched() async throws {
        try vocabulary.add(term: "SPEAKER", heardAs: ["speaker"])
        transcription.text = "[Speaker 1] the speaker [Speaker 2] yes"
        appState.cleanupEnabled = false
        await dictate()
        XCTAssertEqual(paste.pasted, ["[Speaker 1] the SPEAKER [Speaker 2] yes"])
    }

    func testACorrectedTermPassesTheWordForWordCheck() {
        // Cleanup sees the corrected transcript, so keeping "Paramount+" isn't a changed word
        let corrected = VocabularyMatcher(terms: [VocabularyTerm(term: "Paramount+", heardAs: ["paramount plus"])])
            .apply("um paramount plus is live")
        let request = CleanupRequest(systemPrompt: CleanupService.defaultPrompt, englishFillers: true)
        XCTAssertEqual(CleanupService.accept("Paramount+ is live.", raw: corrected, request: request), "Paramount+ is live.")
    }

    func testSendsWhisperHintOnlyForWhisperInEnglishOrAuto() {
        XCTAssertTrue(VocabularyPreparer.sendsWhisperHint(speechModelID: "whisper-large-v3-turbo", language: nil))
        XCTAssertTrue(VocabularyPreparer.sendsWhisperHint(speechModelID: "whisper-large-v3-turbo", language: "en"))
        XCTAssertFalse(VocabularyPreparer.sendsWhisperHint(speechModelID: "whisper-large-v3-turbo", language: "ja"))
        XCTAssertFalse(VocabularyPreparer.sendsWhisperHint(speechModelID: "parakeet-tdt-v2", language: nil))
        XCTAssertFalse(VocabularyPreparer.sendsWhisperHint(speechModelID: nil, language: nil))
    }
}
