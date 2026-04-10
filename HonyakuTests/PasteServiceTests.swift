import XCTest
@testable import Honyaku

final class PasteServiceTests: XCTestCase {
    private let service = PasteService()

    func testPriorPasteboardContentsRestoredAfterPaste() async throws {
        let prior = "prior content"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prior, forType: .string)

        try await service.paste("transcribed text")

        let restored = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(restored, prior, "Prior pasteboard contents should be restored after paste")
    }

    func testPasteboardClearedOnAbort() async {
        NSPasteboard.general.setString("transcript text", forType: .string)
        await service.clearTranscriptFromPasteboard(after: 0)
        let content = NSPasteboard.general.string(forType: .string)
        XCTAssertNil(content, "Pasteboard should be empty after clearTranscriptFromPasteboard")
    }
}
