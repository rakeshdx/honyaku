import XCTest
@testable import Honyaku

/// Every test uses its own temporary folder; the user's app-profiles.json is never read or written.
@MainActor
final class AppProfilesStoreTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("honyaku-app-profiles-\(UUID().uuidString)")
        suiteName = "HonyakuAppProfilesTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeEnvironment() -> FeatureEnvironment {
        FeatureEnvironment(directory: directory, defaults: UserDefaults(suiteName: suiteName)!)
    }

    private var damagedCopies: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("app-profiles.damaged-") }
    }

    private var fileURL: URL { directory.appendingPathComponent(AppProfilesStore.fileName) }

    func testNoFileMeansDefaultsAndNothingWritten() {
        let store = AppProfilesStore(directory: directory)
        XCTAssertEqual(store.profiles, AppProfiles())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "loading never writes")
    }

    func testChangesSurviveAReload() throws {
        let store = AppProfilesStore(directory: directory)
        var chat = store.profiles.rules(for: .chat)
        chat.finalFullStop = .drop
        store.profiles.setRules(chat, for: .chat)
        store.profiles.addApp(bundleID: "com.microsoft.Outlook", displayName: "Microsoft Outlook")

        let reloaded = AppProfilesStore(directory: directory)
        XCTAssertEqual(reloaded.profiles, store.profiles)
        XCTAssertEqual(reloaded.profiles.rules(for: .chat).finalFullStop, .drop)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testOnlyChangesAreStored() throws {
        let store = AppProfilesStore(directory: directory)
        store.profiles.setRules(FormattingRules(trailingSpace: true), for: .email)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        XCTAssertEqual((json?["categories"] as? [String: Any])?.keys.sorted(), ["email"])
        XCTAssertEqual(json?["version"] as? Int, 1)
    }

    func testDamagedFileIsMovedAsideWithANotice() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: fileURL)

        let store = AppProfilesStore(directory: directory)
        XCTAssertEqual(store.profiles, AppProfiles())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(damagedCopies.count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(damagedCopies[0])), damaged)
        let notice = try XCTUnwrap(store.fileNotice)
        XCTAssertTrue(notice.contains(damagedCopies[0]), notice)

        store.profiles.setRules(FormattingRules(finalFullStop: .drop), for: .chat)
        XCTAssertEqual(AppProfilesStore(directory: directory).profiles.rules(for: .chat).finalFullStop, .drop)
    }

    func testDamagedFileThatCantBeMovedIsNeverSavedOver() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: fileURL)

        let store = AppProfilesStore(directory: directory, fileManager: RefusingToMove())
        XCTAssertFalse(store.savesToDisk)
        XCTAssertTrue(store.fileNotice?.contains("won\u{2019}t be saved") == true)
        store.profiles.setRules(FormattingRules(finalFullStop: .drop), for: .chat)
        XCTAssertEqual(store.profiles.rules(for: .chat).finalFullStop, .drop, "the change still applies")
        XCTAssertEqual(try Data(contentsOf: fileURL), damaged, "never saved over")
    }

    func testNewerVersionIsLeftAloneAndNeverSavedOver() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let newer = Data(#"{"version":2,"categories":{"chat":{"finalFullStop":"drop"}},"apps":[]}"#.utf8)
        try newer.write(to: fileURL)

        let store = AppProfilesStore(directory: directory)
        XCTAssertEqual(store.profiles, AppProfiles())
        XCTAssertNotNil(store.fileNotice)
        store.profiles.setRules(FormattingRules(trailingSpace: true), for: .email)
        XCTAssertEqual(try Data(contentsOf: fileURL), newer)
        XCTAssertTrue(damagedCopies.isEmpty)
    }

    func testTheAppRunsTheRulesThenTheGuardLast() {
        let final = PipelineStages.live(makeEnvironment()).final
        XCTAssertGreaterThanOrEqual(final.count, 2)
        XCTAssertTrue(final[final.count - 2] is FormattingStage)
        XCTAssertTrue(final[final.count - 1] is PasteGuardStage)
    }

    func testTheEnvironmentSharesOneStore() {
        let environment = makeEnvironment()
        XCTAssertTrue(environment.store(AppProfilesStore.self) === environment.store(AppProfilesStore.self))
        XCTAssertEqual(environment.store(AppProfilesStore.self).fileURL, fileURL)
    }
}

/// A file manager that can't move files, to test a damaged file that can't be set aside.
private final class RefusingToMove: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
