import XCTest
@testable import Honyaku

final class PushToTalkGestureTests: XCTestCase {
    private let t0 = Date()
    private var gesture = PushToTalkGesture()

    func testQuickTapCancels() {
        XCTAssertEqual(down(at: 0), .start)
        XCTAssertEqual(up(at: 0.1), .cancel, "Release under 300 ms must cancel so the mic is released")
    }

    func testHoldEnds() {
        XCTAssertEqual(down(at: 0), .start)
        XCTAssertEqual(up(at: 0.5), .end)
    }

    func testPressAfterQuickTapStartsAgain() {
        _ = down(at: 0)
        _ = up(at: 0.1)
        XCTAssertEqual(down(at: 1), .start)
        XCTAssertEqual(up(at: 2), .end)
    }

    func testRepeatDownIsSuppressed() {
        _ = down(at: 0)
        XCTAssertEqual(down(at: 0.2, busy: true), .suppress)
    }

    func testBusyPipelinePassesThrough() {
        XCTAssertEqual(down(at: 0, busy: true), .passThrough)
        XCTAssertEqual(up(at: 1, busy: true), .passThrough, "No press was started, so release is not ours")
    }

    func testLongHoldSurvivesExtraControlEvent() {
        _ = down(at: 0)
        // e.g. the second Control key or Fn, 6 s into an active recording
        XCTAssertEqual(down(at: 6, busy: true), .suppress)
        XCTAssertEqual(up(at: 7, busy: true), .end, "The active hold must still end with transcription")
    }

    func testStalePressClearedWhenIdle() {
        _ = down(at: 0)
        // Key-up was missed and the pipeline has gone idle since
        XCTAssertEqual(down(at: 6, busy: false), .start)
    }

    func testControlChordPassesThrough() {
        XCTAssertEqual(gesture.controlChanged(controlDown: true, otherModifiers: true, now: t0, pipelineBusy: false),
                       .passThrough)
    }

    // MARK: - Helpers

    private func down(at seconds: TimeInterval, busy: Bool = false) -> PushToTalkGesture.Action {
        gesture.controlChanged(controlDown: true, otherModifiers: false, now: t0 + seconds, pipelineBusy: busy)
    }

    private func up(at seconds: TimeInterval, busy: Bool = false) -> PushToTalkGesture.Action {
        gesture.controlChanged(controlDown: false, otherModifiers: false, now: t0 + seconds, pipelineBusy: busy)
    }
}
