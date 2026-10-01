import XCTest
@testable import Honyaku

/// Every test uses its own temporary folder; the user's app-profiles.json is never read or written.
@MainActor
final class AppProfilesStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("honyaku-app-profiles-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
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

    func testDamagedFileUsesDefaultsAndIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: fileURL)

        let store = AppProfilesStore(directory: directory)
        XCTAssertEqual(store.profiles, AppProfiles())
        XCTAssertEqual(try Data(contentsOf: fileURL), damaged, "not overwritten until the user changes a rule")

        store.profiles.setRules(FormattingRules(finalFullStop: .drop), for: .chat)
        XCTAssertEqual(AppProfilesStore(directory: directory).profiles.rules(for: .chat).finalFullStop, .drop)
    }

    func testNewerVersionIsTreatedAsUnreadable() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let newer = Data(#"{"version":2,"categories":{"chat":{"finalFullStop":"drop"}},"apps":[]}"#.utf8)
        try newer.write(to: fileURL)
        XCTAssertEqual(AppProfilesStore(directory: directory).profiles, AppProfiles())
        XCTAssertEqual(try Data(contentsOf: fileURL), newer)
    }

    func testTheAppRunsTheGuardThenTheRulesLast() {
        let environment = FeatureEnvironment(directory: directory, defaults: UserDefaults(suiteName: "unused-\(UUID())")!)
        let final = PipelineStages.live(environment).final
        XCTAssertGreaterThanOrEqual(final.count, 2)
        XCTAssertTrue(final[final.count - 2] is PasteGuardStage)
        XCTAssertTrue(final[final.count - 1] is FormattingStage)
    }

    func testTheEnvironmentSharesOneStore() {
        let environment = FeatureEnvironment(directory: directory, defaults: UserDefaults(suiteName: "unused-\(UUID())")!)
        XCTAssertTrue(environment.store(AppProfilesStore.self) === environment.store(AppProfilesStore.self))
        XCTAssertEqual(environment.store(AppProfilesStore.self).fileURL, fileURL)
    }
}
