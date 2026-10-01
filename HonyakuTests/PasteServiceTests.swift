import XCTest
@testable import Honyaku

/// Uses a private pasteboard: the user's clipboard is never read or changed.
final class PasteServiceTests: XCTestCase {
    private let keystrokes = KeystrokeRecorder()
    private let shared = TestPasteboard()
    private var pasteboard: NSPasteboard { shared.pasteboard }
    private lazy var service = PasteService(pasteboard: pasteboard, restoreDelay: .milliseconds(50),
                                            sendPasteKeystroke: { [keystrokes, shared] in
        // Capture what would be pasted instead of sending a real ⌘V into whichever app is frontmost
        keystrokes.record(shared.pasteboard.string(forType: .string))
    })

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testPriorPasteboardContentsRestoredAfterPaste() async throws {
        let prior = "prior content"
        pasteboard.clearContents()
        pasteboard.setString(prior, forType: .string)

        try await service.paste("transcribed text")
        await service.waitForPendingRestore()

        XCTAssertEqual(keystrokes.pastedTexts, ["transcribed text"], "Exactly one paste of the transcript")
        let restored = pasteboard.string(forType: .string)
        XCTAssertEqual(restored, prior, "Prior pasteboard contents should be restored after paste")
    }

    func testNewerClipboardContentsAreNotOverwritten() async throws {
        pasteboard.clearContents()
        pasteboard.setString("prior content", forType: .string)
        // The "user" copies something while the paste is landing
        let service = PasteService(pasteboard: pasteboard, restoreDelay: .milliseconds(50), sendPasteKeystroke: { [shared] in
            shared.pasteboard.clearContents()
            shared.pasteboard.setString("copied meanwhile", forType: .string)
        })

        try await service.paste("transcribed text")
        await service.waitForPendingRestore()

        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile",
                       "Restoring would overwrite what the user copied during the wait")
    }

    func testPasteReturnsBeforeRestore() async throws {
        pasteboard.clearContents()
        pasteboard.setString("prior content", forType: .string)
        let slow = PasteService(pasteboard: pasteboard, restoreDelay: .seconds(5), sendPasteKeystroke: {})

        let start = ContinuousClock.now
        try await slow.paste("transcribed text")

        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1), "The next dictation must not wait for the restore")
        XCTAssertEqual(pasteboard.string(forType: .string), "transcribed text")
    }

    func testQuickSuccessionRestoresOriginalClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("prior content", forType: .string)

        try await service.paste("first transcript")
        try await service.paste("second transcript")  // before the first restore has run
        await service.waitForPendingRestore()

        XCTAssertEqual(keystrokes.pastedTexts, ["first transcript", "second transcript"])
        XCTAssertEqual(pasteboard.string(forType: .string), "prior content",
                       "The user's clipboard comes back, not the first transcript")
    }

    func testPasteboardClearedOnAbort() async {
        pasteboard.setString("transcript text", forType: .string)
        await service.clearTranscriptFromPasteboard(after: 0)
        let content = pasteboard.string(forType: .string)
        XCTAssertNil(content, "Pasteboard should be empty after clearTranscriptFromPasteboard")
    }
}

/// A private, uniquely named pasteboard. NSPasteboard isn't Sendable; the keystroke closures only read and
/// write it, as the service itself does.
private final class TestPasteboard: @unchecked Sendable {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.honyaku.tests.\(UUID().uuidString)"))
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
