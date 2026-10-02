import XCTest
@testable import Honyaku

/// OpenSpec change `fix-rewrite-grounding`: a rewrite of "P plus" with the vocabulary Paramount+, P+ and
/// POPS invented a task about the Paramount+ backend and the POPS dashboard.
@MainActor
final class RewriteGroundingTests: XCTestCase {
    private let terms = [
        VocabularyTerm(term: "Paramount+", heardAs: ["Paramount plus", "para mount plus"]),
        VocabularyTerm(term: "P+", heardAs: ["P Plus"]),
        VocabularyTerm(term: "POPS"),
    ]
    private var matcher: VocabularyMatcher { VocabularyMatcher(terms: terms) }

    // MARK: - Only terms you said

    func testMatchedTermsAreThoseSaidInListOrder() {
        XCTAssertEqual(matcher.matchedTerms(in: "Ship P+ today, then POPS, then P+ again"), ["P+", "POPS"])
        XCTAssertEqual(matcher.matchedTerms(in: "pops and p+"), ["P+", "POPS"], "Any case, list order")
        XCTAssertEqual(matcher.matchedTerms(in: "paramount plus is live"), ["Paramount+"], "A heard-as spelling")
        XCTAssertEqual(matcher.matchedTerms(in: "Let's meet at noon"), [])
        XCTAssertEqual(matcher.matchedTerms(in: "lollipops popsicle"), [], "Whole words only")
        XCTAssertEqual(matcher.matchedTerms(in: "see pops.example.com/x"), [], "Not inside a link")
    }

    func testTheRuleListsOnlyTheTermsInTheCorrectedTranscript() {
        let snapshot = VocabularySnapshot()
        snapshot.matcher = matcher
        let stage = VocabularyCorrectionStage(snapshot: snapshot)

        var context = DictationContext()
        XCTAssertEqual(stage.apply("ship p plus today", context: &context), "ship P+ today")
        XCTAssertEqual(context.cleanupRules, ["Write these terms exactly as listed: P+."])

        var none = DictationContext()
        _ = stage.apply("let's meet at noon", context: &none)
        XCTAssertEqual(none.cleanupRules, [], "No listed term said: no rule")
    }

    func testThePreparerNoLongerSendsTheWholeList() throws {
        let environment = makeEnvironment()
        let store = environment.store(VocabularyStore.self)
        for term in terms { try store.add(term: term.term, heardAs: term.heardAs) }
        let stages = VocabularyStages.make(environment)
        var context = DictationContext()
        for preparer in stages.preparers { preparer.prepare(&context) }
        XCTAssertEqual(context.cleanupRules, [])
        XCTAssertEqual(context.vocabularyTerms, ["Paramount+", "P+", "POPS"])
        XCTAssertNotNil(context.vocabularyMatcher)
    }

    // MARK: - Minimum length

    func testMinimumLength() {
        XCTAssertTrue(RewritePrompt.isTooShort("P+"))
        XCTAssertTrue(RewritePrompt.isTooShort("fix the bug"))
        XCTAssertTrue(RewritePrompt.isTooShort("  um, P+ ?  "), "Punctuation isn't a word")
        XCTAssertTrue(RewritePrompt.isTooShort("[Speaker 1] fix the bug"), "Labels don't count")
        XCTAssertFalse(RewritePrompt.isTooShort("rename the build script"))
        XCTAssertTrue(RewritePrompt.isTooShort("確認して"), "4 characters: 2 words")
        XCTAssertFalse(RewritePrompt.isTooShort("ログイン画面を確認して"), "11 characters: 5 words")
        XCTAssertEqual(RewritePrompt.minimumWords, 4)
    }

    // MARK: - Invention check

    func testInventionCheck() {
        let input = "check the P+ login flow today"
        XCTAssertTrue(RewriteStep.addsVocabularyTerms("Check the POPS dashboard for P+.", to: input, matcher: matcher))
        XCTAssertTrue(RewriteStep.addsVocabularyTerms("Test P+ against the Paramount+ backend.", to: input,
                                                      matcher: matcher))
        XCTAssertFalse(RewriteStep.addsVocabularyTerms("Check the P+ login flow today.", to: input, matcher: matcher))
        XCTAssertFalse(RewriteStep.addsVocabularyTerms("Check the login flow.", to: input, matcher: matcher))
        XCTAssertFalse(RewriteStep.addsVocabularyTerms("Anything at all, POPS too.", to: input, matcher: nil),
                       "No vocabulary: nothing to check")
    }

    func testNoticesDontClaimAPaste() {
        XCTAssertFalse(RewriteCopy.tooShortNotice.contains("pasted"))
        XCTAssertFalse(RewriteCopy.inventedNotice.contains("pasted"))
    }

    private func makeEnvironment() -> FeatureEnvironment {
        let suite = "HonyakuRewriteGroundingTests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)")
        addTeardownBlock {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return FeatureEnvironment(directory: directory, defaults: UserDefaults(suiteName: suite)!)
    }
}

/// The reported case end to end, with the real vocabulary and rewrite stages and a model that invents.
@MainActor
final class RewriteGroundingPipelineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var appState: AppState!
    private var store: TranscriptStore!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var targets: FakeTargets!
    private var environment: FeatureEnvironment!
    /// Never the real accessibility API: the guard sees only what a test sets.
    private var probe: FakePasteGuardProbe!

    private let invented = "Add P+ to the list of supported platforms. Make sure you verify the P+ integration works "
        + "with the Paramount+ backend. Check that the POPS dashboard shows real-time data for P+ streams."

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HonyakuRewriteGroundingPipelineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        appState = AppState(defaults: defaults)
        store = TranscriptStore(inMemory: [])
        transcription = FakeTranscription()
        cleanup = FakeCleanup()
        paste = FakePaste()
        targets = FakeTargets()
        targets.front = TargetApp(bundleID: "com.cmuxterm.app", pid: 9)
        probe = FakePasteGuardProbe()
        environment = FeatureEnvironment(
            directory: FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)"),
            defaults: defaults)
        let vocabulary = environment.store(VocabularyStore.self)
        try vocabulary.add(term: "Paramount+", heardAs: ["Paramount plus", "para mount plus"])
        try vocabulary.add(term: "P+", heardAs: ["P Plus"])
        try vocabulary.add(term: "POPS")
        // A model that invents for a rewrite, and keeps the words for word-for-word cleanup
        let fake: FakeCleanup = cleanup
        cleanup.respond = { [unowned fake, invented] text in
            fake.requests.last?.faithfulness == CleanupRequest.Faithfulness.none ? invented : text
        }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: environment.directory)
        super.tearDown()
    }

    private func rewrite() async {
        let services = PipelineServices(audioCapture: FakeAudioCapture(), transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: FakeModels(), targets: targets)
        let pipeline = TranscriptionPipeline(
            appState: appState, transcriptStore: store, services: services,
            stages: .combined([VocabularyStages.make(environment), RewriteStages.make(environment),
                               PerAppStages.make(store: environment.store(AppProfilesStore.self), probe: probe)]),
            defaults: defaults)
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess(mode: .rewrite)?.value
    }

    func testTwoWordsArePastedAsDictatedNotRewritten() async {
        transcription.text = "P plus"
        await rewrite()

        XCTAssertFalse(cleanup.requests.contains { $0.faithfulness == .none }, "No rewrite call")
        XCTAssertEqual(paste.pasted, ["P+"])
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertNil(store.entries.first?.rewriteTemplateID)
        XCTAssertEqual(appState.status, .error(RewriteCopy.tooShortNotice))
        XCTAssertEqual(cleanup.requests.first?.extraRules, ["Write these terms exactly as listed: P+."],
                       "Cleanup still runs, told only about the term said")
    }

    func testARewriteThatAddsUnsaidTermsFallsBack() async {
        transcription.text = "check the p plus login flow today"
        await rewrite()

        let rewriteRequest = cleanup.requests.first { $0.faithfulness == .none }
        XCTAssertEqual(rewriteRequest?.extraRules, ["Write these terms exactly as listed: P+."],
                       "The rewrite prompt names only P+, never Paramount+ or POPS")
        XCTAssertEqual(paste.pasted, ["check the P+ login flow today"], "One line, no final full stop: a terminal")
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertEqual(appState.status, .error(RewriteCopy.inventedNotice))
    }

    func testARewriteUsingOnlySaidTermsIsPasted() async {
        transcription.text = "check the p plus login flow today"
        cleanup.respond = { _ in "Check the P+ login flow today." }
        await rewrite()

        XCTAssertEqual(paste.pasted, ["Check the P+ login flow today"])
        XCTAssertEqual(store.entries.first?.mode, "rewrite")
        XCTAssertEqual(appState.status, .idle)
    }

    func testABlockedRewriteShowsOnlyTheBlock() async {
        transcription.text = "P plus"
        targets.secureField = true
        await rewrite()
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }
}
