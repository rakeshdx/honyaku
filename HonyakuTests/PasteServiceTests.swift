import XCTest
@testable import Honyaku

final class PasteServiceTests: XCTestCase {
    private let keystrokes = KeystrokeRecorder()
    private lazy var service = PasteService(restoreDelay: .milliseconds(50), sendPasteKeystroke: { [keystrokes] in
        // Capture what would be pasted instead of sending a real ⌘V into whichever app is frontmost
        keystrokes.record(NSPasteboard.general.string(forType: .string))
    })

    func testPriorPasteboardContentsRestoredAfterPaste() async throws {
        let prior = "prior content"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prior, forType: .string)

        try await service.paste("transcribed text")
        await service.waitForPendingRestore()

        XCTAssertEqual(keystrokes.pastedTexts, ["transcribed text"], "Exactly one paste of the transcript")
        let restored = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(restored, prior, "Prior pasteboard contents should be restored after paste")
    }

    func testNewerClipboardContentsAreNotOverwritten() async throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("prior content", forType: .string)
        // The "user" copies something while the paste is landing
        let service = PasteService(restoreDelay: .milliseconds(50), sendPasteKeystroke: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("copied meanwhile", forType: .string)
        })

        try await service.paste("transcribed text")
        await service.waitForPendingRestore()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copied meanwhile",
                       "Restoring would overwrite what the user copied during the wait")
    }

    func testPasteReturnsBeforeRestore() async throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("prior content", forType: .string)
        let slow = PasteService(restoreDelay: .seconds(5), sendPasteKeystroke: {})

        let start = ContinuousClock.now
        try await slow.paste("transcribed text")

        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1), "The next dictation must not wait for the restore")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "transcribed text")
    }

    func testQuickSuccessionRestoresOriginalClipboard() async throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("prior content", forType: .string)

        try await service.paste("first transcript")
        try await service.paste("second transcript")  // before the first restore has run
        await service.waitForPendingRestore()

        XCTAssertEqual(keystrokes.pastedTexts, ["first transcript", "second transcript"])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "prior content",
                       "The user's clipboard comes back, not the first transcript")
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
