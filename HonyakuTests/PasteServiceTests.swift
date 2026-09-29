import XCTest
@testable import Honyaku

final class PasteServiceTests: XCTestCase {
    private let keystrokes = KeystrokeRecorder()
    private lazy var service = PasteService(sendPasteKeystroke: { [keystrokes] in
        // Capture what would be pasted instead of sending a real ⌘V into whichever app is frontmost
        keystrokes.record(NSPasteboard.general.string(forType: .string))
    })

    func testPriorPasteboardContentsRestoredAfterPaste() async throws {
        let prior = "prior content"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prior, forType: .string)

        try await service.paste("transcribed text")

        XCTAssertEqual(keystrokes.pastedTexts, ["transcribed text"], "Exactly one paste of the transcript")
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

/// Thread-safe record of what the injected keystroke sender saw on the pasteboard.
private final class KeystrokeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String?] = []

    func record(_ text: String?) {
        lock.lock(); defer { lock.unlock() }
        texts.append(text)
    }

    var pastedTexts: [String?] {
        lock.lock(); defer { lock.unlock() }
        return texts
    }
}
