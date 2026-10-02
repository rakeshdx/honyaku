import XCTest
@testable import Honyaku

/// Every test uses its own temporary folder and settings suite: never the user's vocabulary.json.
@MainActor
final class VocabularyStoreTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: "honyaku-vocabulary-\(UUID().uuidString)")
        suiteName = "HonyakuVocabularyTests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeStore() -> VocabularyStore {
        let environment = FeatureEnvironment(directory: directory, defaults: UserDefaults(suiteName: suiteName)!)
        return environment.store(VocabularyStore.self)
    }

    private var fileURL: URL { directory.appending(path: VocabularyStore.fileName) }

    // MARK: - File

    func testRoundTripKeepsOrderAndState() throws {
        let store = makeStore()
        try store.add(term: "Paramount+", heardAs: ["paramount plus"])
        try store.add(term: "Jira")
        store.setEnabled(store.terms[1].id, false)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.terms, store.terms)
        XCTAssertEqual(reloaded.terms.map(\.term), ["Paramount+", "Jira"])
        XCTAssertFalse(reloaded.terms[1].enabled)
    }

    func testFileIsOwnerOnlyAndExcludedFromBackup() throws {
        let store = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "No file until the first term")
        try store.add(term: "Jira")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testCorruptFileIsSetAsideAndAnEmptyListStarts() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let store = makeStore()
        XCTAssertTrue(store.terms.isEmpty)
        let notice = try XCTUnwrap(store.corruptFileNotice)
        XCTAssertTrue(notice.contains("vocabulary.corrupt-"))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("vocabulary.corrupt-") && $0.hasSuffix(".json") })
        XCTAssertFalse(names.contains(VocabularyStore.fileName))

        // The list works again straight away
        try store.add(term: "Jira")
        XCTAssertEqual(makeStore().terms.map(\.term), ["Jira"])
    }

    // MARK: - Validation

    func testValidation() throws {
        let store = makeStore()
        XCTAssertThrowsError(try store.add(term: "   ")) { XCTAssertEqual($0 as? VocabularyError, .emptyTerm) }
        XCTAssertThrowsError(try store.add(term: String(repeating: "a", count: 101))) {
            XCTAssertEqual($0 as? VocabularyError, .tooLong)
        }
        try store.add(term: "Jira", heardAs: ["jeera"])
        XCTAssertThrowsError(try store.add(term: "jira")) {
            XCTAssertEqual($0 as? VocabularyError, .duplicateTerm)
            XCTAssertEqual(($0 as? VocabularyError)?.errorDescription, "Already in your list")
        }
        XCTAssertThrowsError(try store.add(term: "Gira", heardAs: ["Jeera"])) {
            XCTAssertEqual($0 as? VocabularyError, .heardAsInUse(spelling: "Jeera", term: "Jira"))
        }
        // A term can't be another term's heard-as spelling either
        XCTAssertThrowsError(try store.add(term: "Jeera")) {
            XCTAssertEqual($0 as? VocabularyError, .heardAsInUse(spelling: "Jeera", term: "Jira"))
        }
        XCTAssertEqual(store.terms.count, 1, "Refused edits change nothing")
    }

    func testEditingTrimsAndDropsSpellingsThatMatchTheTermItself() throws {
        let store = makeStore()
        try store.add(term: "  Pluto   TV ", heardAs: [" pluto tv", "plutotv", "", "PLUTOTV"])
        XCTAssertEqual(store.terms[0].term, "Pluto TV")
        XCTAssertEqual(store.terms[0].heardAs, ["plutotv"])

        try store.update(store.terms[0].id, term: "Pluto TV", heardAs: ["pluto t v"])
        XCTAssertEqual(store.terms[0].heardAs, ["pluto t v"])
    }

    func testMoveAndDelete() throws {
        let store = makeStore()
        for term in ["A", "B", "C"] { try store.add(term: term) }
        store.move(store.terms[2].id, by: -1)
        XCTAssertEqual(store.terms.map(\.term), ["A", "C", "B"])
        store.move(store.terms[0].id, by: -1)
        XCTAssertEqual(store.terms.map(\.term), ["A", "C", "B"], "The top term can't move further up")
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.terms.map(\.term), ["B", "A", "C"])
        store.delete(store.terms[1].id)
        XCTAssertEqual(makeStore().terms.map(\.term), ["B", "C"])
    }

    // MARK: - What the pipeline uses

    func testPromptRuleListsTheTopFortyEnabledTerms() throws {
        let store = makeStore()
        XCTAssertNil(store.promptRule)
        try store.add(term: "Paramount+")
        try store.add(term: "Jira")
        XCTAssertEqual(store.promptRule, "Write these terms exactly as listed: Paramount+, Jira.")

        for index in 0..<120 { try store.add(term: "Term\(index)") }
        let rule = try XCTUnwrap(store.promptRule)
        XCTAssertEqual(rule.components(separatedBy: ", ").count, 40)
        XCTAssertTrue(rule.hasSuffix("Term37."))

        for term in store.terms { store.setEnabled(term.id, false) }
        XCTAssertNil(store.promptRule, "No rule when every term is off")
    }

    func testMatcherFollowsEdits() throws {
        let store = makeStore()
        XCTAssertEqual(store.matcher.apply("file a jira"), "file a jira")
        try store.add(term: "Jira")
        XCTAssertEqual(store.matcher.apply("file a jira"), "file a Jira")
        store.setEnabled(store.terms[0].id, false)
        XCTAssertEqual(store.matcher.apply("file a jira"), "file a jira")
    }

    // MARK: - History

    func testAddFromHistoryAddsANewTermOrMergesIntoAnExistingOne() throws {
        let store = makeStore()
        try store.addFromHistory(heardAs: "plutotv", writeAs: "Pluto TV")
        XCTAssertEqual(store.terms.map(\.term), ["Pluto TV"])
        XCTAssertEqual(store.terms[0].heardAs, ["plutotv"])

        try store.addFromHistory(heardAs: "pluto t v", writeAs: "pluto tv")
        XCTAssertEqual(store.terms.count, 1, "Merged into the existing term, ignoring case")
        XCTAssertEqual(store.terms[0].heardAs, ["plutotv", "pluto t v"])

        try store.addFromHistory(heardAs: "", writeAs: "Jira")
        XCTAssertEqual(store.terms.map(\.term), ["Pluto TV", "Jira"], "Only the case was wrong: no heard-as")
    }

    // MARK: - Import and export

    func testImportMergesWithoutDeleting() throws {
        let store = makeStore()
        try store.add(term: "Jira", heardAs: ["jeera"])
        try store.add(term: "Slack")
        store.setEnabled(store.terms[0].id, false)

        let incoming = """
        { "version": 1, "terms": [
            { "term": "jira", "heardAs": ["gira"], "enabled": true },
            { "term": "Pluto TV" }
        ] }
        """
        let summary = try store.importData(Data(incoming.utf8))
        XCTAssertEqual(summary.message, "Added 1 term, updated 1")
        XCTAssertEqual(store.terms.map(\.term), ["Jira", "Slack", "Pluto TV"])
        XCTAssertEqual(store.terms[0].heardAs, ["jeera", "gira"])
        XCTAssertFalse(store.terms[0].enabled, "An existing term keeps its on/off state")
    }

    func testImportSkipsSpellingsOtherTermsUse() throws {
        let store = makeStore()
        try store.add(term: "Jira", heardAs: ["jeera"])
        let incoming = #"{ "version": 1, "terms": [ { "term": "Gira", "heardAs": ["jeera"] }, { "term": "Jeera" } ] }"#
        let summary = try store.importData(Data(incoming.utf8))
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.skipped.count, 2)
        XCTAssertEqual(summary.message, "Added 1 term, updated 0, skipped 2 (already used by \u{201C}Jira\u{201D} and others)")
        XCTAssertEqual(store.terms.map(\.term), ["Jira", "Gira"])
        XCTAssertEqual(store.terms[1].heardAs, [])
    }

    func testAnInvalidFileChangesNothing() throws {
        let store = makeStore()
        try store.add(term: "Jira")
        XCTAssertThrowsError(try store.importData(Data(#"{ "words": [] }"#.utf8)))
        XCTAssertThrowsError(try store.importData(Data(#"{ "version": 99, "terms": [] }"#.utf8)))
        XCTAssertEqual(store.terms.map(\.term), ["Jira"])
    }

    func testExportRoundTripsThroughImport() throws {
        let store = makeStore()
        try store.add(term: "Paramount+", heardAs: ["paramount plus"])
        let data = try store.exportData()

        try? FileManager.default.removeItem(at: directory)
        let other = FeatureEnvironment(directory: directory.appending(path: "other"),
                                       defaults: UserDefaults(suiteName: suiteName)!).store(VocabularyStore.self)
        _ = try other.importData(data)
        XCTAssertEqual(other.terms.map(\.term), ["Paramount+"])
        XCTAssertEqual(other.terms[0].heardAs, ["paramount plus"])
    }
}
