import XCTest
@testable import Honyaku

final class TimeAgoTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-09-30T15:00:00Z")!

    private func ago(_ seconds: TimeInterval) -> String {
        TimeAgo.string(from: now.addingTimeInterval(-seconds), now: now, calendar: calendar)
    }

    func testRecentIsJustNow() {
        XCTAssertEqual(ago(10), "just now")
    }

    func testMinutesAndHours() {
        XCTAssertEqual(ago(120), "2m ago")
        XCTAssertEqual(ago(59 * 60), "59m ago")
        XCTAssertEqual(ago(3 * 3600), "3h ago")
    }

    func testFutureDatesClampToJustNow() {
        XCTAssertEqual(ago(-30), "just now")
    }

    func testYesterdayAndOlder() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let yesterday = now.addingTimeInterval(-24 * 3600)
        XCTAssertEqual(TimeAgo.string(from: yesterday, now: now, calendar: cal), "yesterday")
        let older = now.addingTimeInterval(-5 * 24 * 3600)
        XCTAssertNotEqual(TimeAgo.string(from: older, now: now, calendar: cal), "yesterday")
        XCTAssertFalse(TimeAgo.string(from: older, now: now, calendar: cal).hasSuffix("ago"))
    }
}

@MainActor
final class TranscriptStoreRedesignTests: XCTestCase {
    private func entry(_ text: String) -> TranscriptEntry {
        TranscriptEntry(rawText: text, cleanedText: text, modelTier: "test", durationSeconds: 1)
    }

    func testDeleteRemovesOnlyThatEntry() {
        let a = entry("first"), b = entry("second")
        let store = TranscriptStore(inMemory: [a, b])
        store.delete(a.id)
        XCTAssertEqual(store.entries.map(\.id), [b.id])
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let entries = [entry("Send the Invoice today"), entry("Book the café"), entry("Call Mum")]
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "invoice").map(\.cleanedText), ["Send the Invoice today"])
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "cafe").map(\.cleanedText), ["Book the café"])
    }

    func testBlankSearchReturnsEverything() {
        let entries = [entry("one"), entry("two")]
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "  ").count, 2)
    }

    func testInMemoryStoreNeverTouchesHistoryFile() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honyaku/history.json")
        let before = try? Data(contentsOf: file)
        let store = TranscriptStore(inMemory: [])
        store.save(entry("never persisted"))
        store.clearAll()
        XCTAssertEqual(try? Data(contentsOf: file), before)
    }
}

final class InputLevelTests: XCTestCase {
    func testSilenceIsZeroAndFullScaleIsOne() {
        let silence = [Float](repeating: 0, count: 480)
        let loud = [Float](repeating: 1, count: 480)
        silence.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 0) }
        loud.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 1, accuracy: 0.001) }
    }

    func testQuietSpeechIsInTheMiddle() {
        // RMS 0.03 ≈ −30 dBFS → 0.4 on the −50…0 scale
        let quiet = [Float](repeating: 0.03, count: 480)
        quiet.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 0.4, accuracy: 0.02) }
    }
}

final class KeycapStateTests: XCTestCase {
    func testStatusMapsToKeyState() {
        XCTAssertEqual(KeycapView.KeyState(.idle), .idle)
        XCTAssertEqual(KeycapView.KeyState(.recording), .recording)
        XCTAssertEqual(KeycapView.KeyState(.transcribing), .busy)
        XCTAssertEqual(KeycapView.KeyState(.processing), .busy)
        XCTAssertEqual(KeycapView.KeyState(.error("x")), .error)
    }
}
