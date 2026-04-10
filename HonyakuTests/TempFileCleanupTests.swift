import XCTest
@testable import Honyaku

final class TempFileCleanupTests: XCTestCase {

    func testOrphanedTempFilesRemovedOnLaunch() throws {
        // Create a fake Honyaku temp file
        let fakeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("honyaku_orphan_\(UUID()).wav")
        try Data("fake audio".utf8).write(to: fakeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeURL.path))

        // Run launch-time cleanup
        TranscriptionService.cleanupOrphanedTempFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fakeURL.path),
                       "Orphaned honyaku temp file should be deleted on launch cleanup")
    }

    func testNonHonyakuTempFilesAreNotDeleted() throws {
        let otherURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("some_other_app_\(UUID()).wav")
        try Data("other data".utf8).write(to: otherURL)

        TranscriptionService.cleanupOrphanedTempFiles()

        let stillExists = FileManager.default.fileExists(atPath: otherURL.path)
        // Clean up our test file regardless
        try? FileManager.default.removeItem(at: otherURL)

        XCTAssertTrue(stillExists, "Non-Honyaku temp files must not be deleted by Honyaku cleanup")
    }
}
