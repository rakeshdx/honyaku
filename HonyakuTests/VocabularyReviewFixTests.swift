import WhisperKit
import XCTest
@testable import Honyaku

/// The custom-vocabulary review fixes: one list per dictation, terms for every engine, protected terms in
/// cleanup, import limits, file failures and the Whisper blank filter. Temporary folders and suites only.
@MainActor
final class VocabularyReviewFixTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var features: FeatureEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: "honyaku-vocabulary-\(UUID().uuidString)")
        suiteName = "HonyakuVocabularyReviewFixTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        features = FeatureEnvironment(directory: directory, defaults: defaults)
    }

    override func tearDown() async throws {
        // A test may have made the folder read-only
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private var store: VocabularyStore { features.store(VocabularyStore.self) }
    private var fileURL: URL { directory.appending(path: VocabularyStore.fileName) }

    // MARK: - One list per dictation, terms for every engine

    func testTheContextGetsEveryEnabledTermForAnyEngine() throws {
        try store.add(term: "Pluto TV")
        try store.add(term: "Jira")
        try store.add(term: "Off")
        store.setEnabled(store.terms[2].id, false)
        let preparer = VocabularyPreparer(store: store, snapshot: VocabularySnapshot())

        for (model, language) in [("parakeet-tdt-v2", nil), ("whisper-large-v3-turbo", "it"), ("whisper-large-v3-turbo", nil)] {
            var context = DictationContext()
            context.speechModelID = model
            context.speechHints.language = language
            preparer.prepare(&context)
            XCTAssertEqual(context.vocabularyTerms, ["Pluto TV", "Jira"], "\(model) \(language ?? "auto")")
        }
    }

    func testAnEditDuringADictationAppliesToTheNextOne() throws {
        try store.add(term: "Jira")
        let snapshot = VocabularySnapshot()
        let preparer = VocabularyPreparer(store: store, snapshot: snapshot)
        let stage = VocabularyCorrectionStage(snapshot: snapshot)

        var context = DictationContext()
        preparer.prepare(&context)
        // Edited in Settings while this dictation is transcribing
        try store.add(term: "Pluto TV")
        XCTAssertEqual(stage.apply("jira and pluto tv", context: &context), "Jira and pluto tv")

        var next = DictationContext()
        preparer.prepare(&next)
        XCTAssertEqual(stage.apply("jira and pluto tv", context: &next), "Jira and Pluto TV")
    }

    func testAnEmptyListCorrectsNothing() throws {
        let snapshot = VocabularySnapshot()
        var context = DictationContext()
        VocabularyPreparer(store: store, snapshot: snapshot).prepare(&context)
        XCTAssertEqual(context.vocabularyTerms, [])
        XCTAssertEqual(VocabularyCorrectionStage(snapshot: snapshot).apply("jira", context: &context), "jira")
    }

    // MARK: - Protected terms in cleanup

    func testStrictCleanupThatLosesPartOfATermIsRejected() {
        let request = CleanupRequest(systemPrompt: CleanupService.defaultPrompt, englishFillers: true,
                                     protectedTerms: ["Paramount+", "Jira"])
        XCTAssertEqual(CleanupService.accept("Paramount is live.", raw: "Paramount+ is live", request: request),
                       "Paramount+ is live")
        XCTAssertEqual(CleanupService.accept("Paramount+ is on jira.", raw: "Paramount+ is on Jira", request: request),
                       "Paramount+ is on Jira", "Letter case counts too")
        XCTAssertEqual(CleanupService.accept("Paramount+ is live.", raw: "um Paramount+ is live", request: request),
                       "Paramount+ is live.")
    }

    func testProtectedTermsDontApplyToRewrites() {
        let request = CleanupRequest(systemPrompt: "Rewrite", faithfulness: .none, protectedTerms: ["Paramount+"])
        XCTAssertEqual(CleanupService.accept("Paramount launched.", raw: "Paramount+ launched", request: request),
                       "Paramount launched.")
    }

    func testKeepsTermsCountsOccurrences() {
        XCTAssertTrue(CleanupService.keepsTerms(["Jira"], raw: "no terms here", cleaned: "No terms here."))
        XCTAssertFalse(CleanupService.keepsTerms(["Jira"], raw: "Jira and Jira", cleaned: "Jira and."))
        XCTAssertTrue(CleanupService.keepsTerms([""], raw: "x", cleaned: "x"))
    }

    // MARK: - Import limits

    func testAFileWithTooManyTermsIsRefused() throws {
        try store.add(term: "Jira")
        let file = VocabularyFile(terms: (0...VocabularyStore.importTermLimit).map { VocabularyTerm(term: "T\($0)") })
        XCTAssertThrowsError(try store.importData(JSONEncoder().encode(file))) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooLarge)
        }
        XCTAssertEqual(store.terms.map(\.term), ["Jira"])
    }

    func testAFileOverOneMegabyteIsRefused() throws {
        var data = Data(#"{ "version": 1, "terms": [ { "term": ""#.utf8)
        data.append(Data(repeating: UInt8(ascii: "a"), count: VocabularyStore.importByteLimit))
        data.append(Data(#"" } ] }"#.utf8))
        XCTAssertThrowsError(try store.importData(data)) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooLarge)
        }
        XCTAssertEqual(VocabularyImportError.tooLarge.errorDescription,
                       "A word list can have at most 2,000 terms and be at most 1 MB. Your list is unchanged.")
    }

    func testTheLargestAllowedImportMergesCorrectly() throws {
        for index in 0..<500 { try store.add(term: "Existing\(index)", heardAs: ["existing number \(index)"]) }
        let incoming = (0..<VocabularyStore.importTermLimit).map { index in
            // The first 500 match existing terms and gain a spelling; one clashes with an existing spelling
            index < 500
                ? VocabularyTerm(term: "existing\(index)", heardAs: ["alias \(index)"])
                : VocabularyTerm(term: "New\(index)", heardAs: index == 600 ? ["existing number 3"] : [])
        }
        let summary = try store.importData(JSONEncoder().encode(VocabularyFile(terms: incoming)))
        XCTAssertEqual(summary.added, 1_500)
        XCTAssertEqual(summary.updated, 500)
        XCTAssertEqual(summary.skipped.map(\.spelling), ["existing number 3"])
        XCTAssertEqual(summary.skipped.map(\.term), ["Existing3"])
        XCTAssertEqual(store.terms.count, 2_000)
        XCTAssertEqual(store.terms[0].heardAs, ["existing number 0", "alias 0"])
        XCTAssertEqual(store.terms[0].term, "Existing0", "An existing term keeps its spelling")
    }

    func testAnImportedHeardAsSpellingAlreadyUsedInTheSameFileIsSkipped() throws {
        let incoming = [VocabularyTerm(term: "Pluto TV", heardAs: ["plutotv"]),
                        VocabularyTerm(term: "Pluto", heardAs: ["plutotv"])]
        let summary = try store.importData(JSONEncoder().encode(VocabularyFile(terms: incoming)))
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.skipped.map(\.term), ["Pluto TV"])
        XCTAssertEqual(store.terms.map(\.heardAs), [["plutotv"], []])
    }

    // MARK: - File failures

    func testADamagedFileThatCantBeSetAsideIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        // A read-only folder: the damaged file can't be renamed, and nothing can be written
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        let damaged = store
        XCTAssertEqual(damaged.corruptFileNotice,
                       "Couldn\u{2019}t set aside the damaged vocabulary file. Changes won\u{2019}t be saved until it\u{2019}s fixed or removed.")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        try damaged.add(term: "Jira")
        XCTAssertEqual(damaged.terms.map(\.term), ["Jira"], "Edits still apply")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "not json", "Never overwritten")
        XCTAssertNil(damaged.saveFailureNotice)
    }

    func testASaveFailureIsShownAndClearedByTheNextSave() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vocabulary = store
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        try vocabulary.add(term: "Jira")
        let notice = try XCTUnwrap(vocabulary.saveFailureNotice)
        XCTAssertTrue(notice.hasPrefix("Couldn\u{2019}t save your word list:"), notice)
        XCTAssertTrue(notice.hasSuffix("Your changes apply until you quit Honyaku."), notice)
        XCTAssertFalse(notice.contains("Jira"), "No terms in the message")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try vocabulary.add(term: "Pluto TV")
        XCTAssertNil(vocabulary.saveFailureNotice)
    }

    // MARK: - Whisper blank filter

    private let tokens = SpecialTokens(
        endToken: 50257, englishToken: 50259, noSpeechToken: 50362, noTimestampsToken: 50363,
        specialTokenBegin: 50257, startOfPreviousToken: 50361, startOfTranscriptToken: 50258,
        timeTokenBegin: 50364, transcribeToken: 50359, translateToken: 50358, whitespaceToken: 220)

    func testTheBlankFilterActsOnlyBeforeTheFirstSampledToken() {
        let prompt = [tokens.startOfPreviousToken, 1000, 1001]
        let prefill = prompt + [tokens.startOfTranscriptToken, tokens.englishToken, tokens.transcribeToken, tokens.timeTokenBegin]
        func suppressed(_ sequence: [Int]) -> Bool {
            WhisperPromptBlankFilter.isBeforeFirstSample(sequence, specialTokens: tokens)
        }

        XCTAssertTrue(suppressed(prefill), "Prefill steps and the first sampled position")
        XCTAssertTrue(suppressed(prompt + [tokens.startOfTranscriptToken, tokens.noTimestampsToken]),
                      "English-only model without timestamps")
        XCTAssertFalse(suppressed(prefill + [tokens.timeTokenBegin + 10]), "A timestamp was sampled: it may end")
        XCTAssertFalse(suppressed(prefill + [1002]), "A word was sampled")
        XCTAssertFalse(suppressed([tokens.startOfTranscriptToken, tokens.englishToken, tokens.transcribeToken,
                                   tokens.timeTokenBegin]), "No prompt: WhisperKit's own filter handles it")
    }
}
