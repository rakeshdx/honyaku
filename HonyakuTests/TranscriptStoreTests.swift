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

@MainActor
final class TranscriptStoreFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("HonyakuStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testHistoryFromBeforeModesStillLoads() throws {
        let file = folder.appendingPathComponent("history.json")
        let old = """
        [{"id":"0E5C1D2A-7B8C-4D3E-9F10-112233445566","rawText":"um hello","cleanedText":"Hello.",\
        "timestamp":780000000,"modelTier":"parakeet-tdt-v2","durationSeconds":1.5,"hasSpeakerLabels":false}]
        """
        try Data(old.utf8).write(to: file)

        let store = TranscriptStore(fileURL: file)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.cleanedText, "Hello.")
        XCTAssertNil(store.entries.first?.mode)
        XCTAssertNil(store.entries.first?.appBundleID)
    }

    func testNewFieldsRoundTripWithRestrictivePermissions() throws {
        let file = folder.appendingPathComponent("history.json")
        let store = TranscriptStore(fileURL: file)
        store.save(TranscriptEntry(rawText: "hi", cleanedText: "Hi.", modelTier: "parakeet-tdt-v2",
                                   durationSeconds: 1, mode: "dictate", appBundleID: "com.apple.Terminal"))

        let reloaded = TranscriptStore(fileURL: file)
        XCTAssertEqual(reloaded.entries.first?.mode, "dictate")
        XCTAssertEqual(reloaded.entries.first?.appBundleID, "com.apple.Terminal")
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }
}
