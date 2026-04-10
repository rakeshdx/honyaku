import XCTest
@testable import Honyaku

@MainActor
final class TranscriptStoreTests: XCTestCase {

    func testHistoryFileSavedWithRestrictivePermissions() async throws {
        let store = TranscriptStore()
        let entry = TranscriptEntry(
            rawText: "um hello world",
            cleanedText: "hello world",
            modelTier: "whisper-small-en",
            durationSeconds: 2.5
        )
        store.save(entry)

        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honyaku/history.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            XCTFail("history.json not found after save")
            return
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        XCTAssertEqual(perms, 0o600, "history.json must have permissions 600 (owner rw only)")
    }

    func testHistoryFileExcludedFromBackup() throws {
        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honyaku")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let rv = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(rv.isExcludedFromBackup, true, "Honyaku directory must be excluded from backup")
    }

    func testClearAllRemovesEntries() {
        let store = TranscriptStore()
        store.save(TranscriptEntry(rawText: "test", cleanedText: "test", modelTier: "m", durationSeconds: 1))
        store.clearAll()
        XCTAssertTrue(store.entries.isEmpty)
    }
}
