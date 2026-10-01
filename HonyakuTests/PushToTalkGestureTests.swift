import XCTest
@testable import Honyaku

final class PushToTalkGestureTests: XCTestCase {
    private let t0 = Date()
    private var gesture = PushToTalkGesture()

    // MARK: - Plain dictation (unchanged)

    func testQuickTapCancels() {
        XCTAssertEqual(down(at: 0), .start(.dictate))
        XCTAssertEqual(up(at: 0.1), .cancel(.tooShort), "Release under 300 ms must cancel so the mic is released")
    }

    func testHoldEnds() {
        XCTAssertEqual(down(at: 0), .start(.dictate))
        XCTAssertEqual(up(at: 0.5), .end(.dictate))
    }

    func testPressAfterQuickTapStartsAgain() {
        _ = down(at: 0)
        _ = up(at: 0.1)
        XCTAssertEqual(down(at: 1), .start(.dictate))
        XCTAssertEqual(up(at: 2), .end(.dictate))
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
        XCTAssertEqual(up(at: 7, busy: true), .end(.dictate), "The active hold must still end with transcription")
    }

    func testStalePressClearedWhenIdle() {
        _ = down(at: 0)
        // Key-up was missed and the pipeline has gone idle since
        XCTAssertEqual(down(at: 6, busy: false), .start(.dictate))
    }

    func testCommandOrOptionHeldFirstPassesThrough() {
        XCTAssertEqual(flags(at: 0, control: true, commandOrOption: true), .passThrough)
        // Letting go of Command while Control stays down isn't a new press
        XCTAssertEqual(flags(at: 0.2, control: true), .passThrough)
        XCTAssertEqual(flags(at: 1), .passThrough)
    }

    // MARK: - Rewrite: Shift at any moment

    func testShiftThenControlRewrites() {
        XCTAssertEqual(flags(at: 0, shift: true), .passThrough, "Shift alone is the app's")
        XCTAssertEqual(flags(at: 0.1, control: true, shift: true), .start(.rewrite))
        XCTAssertEqual(flags(at: 2, shift: true), .end(.rewrite))
    }

    func testControlThenShiftRewrites() {
        XCTAssertEqual(down(at: 0), .start(.dictate))
        XCTAssertEqual(flags(at: 1, control: true, shift: true), .rewriteHint)
        XCTAssertEqual(flags(at: 2, shift: true), .end(.rewrite))
    }

    func testShiftReleasedBeforeControlStillRewrites() {
        // The scenario the spec gives: Shift down, Control down, Shift up, Control up after 1 s
        XCTAssertEqual(flags(at: 0, shift: true), .passThrough)
        XCTAssertEqual(flags(at: 0.1, control: true, shift: true), .start(.rewrite))
        XCTAssertEqual(flags(at: 0.5, control: true), .passThrough, "Shift's release reaches the app")
        XCTAssertEqual(up(at: 1.1), .end(.rewrite))
    }

    func testShiftPressedTwiceHintsOnce() {
        _ = down(at: 0)
        XCTAssertEqual(flags(at: 0.5, control: true, shift: true), .rewriteHint)
        XCTAssertEqual(flags(at: 0.6, control: true), .passThrough)
        XCTAssertEqual(flags(at: 0.7, control: true, shift: true), .passThrough)
        XCTAssertEqual(flags(at: 1, shift: true), .end(.rewrite))
    }

    func testQuickControlShiftTapCancels() {
        XCTAssertEqual(flags(at: 0, control: true, shift: true), .start(.rewrite))
        XCTAssertEqual(up(at: 0.1), .cancel(.tooShort))
    }

    func testNextHoldAfterARewriteIsPlainDictation() {
        _ = flags(at: 0, control: true, shift: true)
        _ = up(at: 1)
        XCTAssertEqual(down(at: 2), .start(.dictate))
        XCTAssertEqual(up(at: 3), .end(.dictate))
    }

    func testRewriteStartIsBlockedWhileBusy() {
        XCTAssertEqual(flags(at: 0, control: true, shift: true, busy: true), .passThrough)
    }

    // MARK: - Shortcuts cancel the hold

    func testKeyPressCancelsAndPassesTheReleaseThrough() {
        // Control held for a second, then Ctrl+C
        _ = down(at: 0)
        XCTAssertEqual(gesture.keyDown(), .cancel(.key))
        XCTAssertFalse(PushToTalkGesture.Action.cancel(.key).swallowsEvent, "The C reaches the app")
        XCTAssertEqual(gesture.keyDown(), .passThrough, "A second Ctrl+C in the same hold is the app's")
        XCTAssertEqual(up(at: 1.5), .passThrough,
                       "The app saw Control in Ctrl+C's flags, so it must see the release too")
        XCTAssertFalse(gesture.isHolding)
    }

    func testClickCancels() {
        _ = down(at: 0)
        XCTAssertEqual(gesture.mouseDown(), .cancel(.click))
        XCTAssertFalse(PushToTalkGesture.Action.cancel(.click).swallowsEvent)
        XCTAssertEqual(up(at: 1), .passThrough)
    }

    func testOptionDuringTheHoldCancels() {
        _ = down(at: 0)
        XCTAssertEqual(flags(at: 1, control: true, commandOrOption: true), .cancel(.chord))
        XCTAssertFalse(PushToTalkGesture.Action.cancel(.chord).swallowsEvent, "The Option event reaches the app")
        XCTAssertEqual(flags(at: 1.2, control: true), .passThrough, "Option let go, Control still held")
        XCTAssertEqual(up(at: 2), .passThrough)
    }

    func testControlShiftShortcutRunsNoRewrite() {
        // Ctrl+Shift+Tab
        XCTAssertEqual(flags(at: 0, control: true, shift: true), .start(.rewrite))
        XCTAssertEqual(gesture.keyDown(), .cancel(.key))
        XCTAssertEqual(flags(at: 0.5, control: true), .passThrough)
        XCTAssertEqual(up(at: 0.6), .passThrough)
    }

    func testCancelAppliesHoweverLongTheHold() {
        _ = down(at: 0)
        XCTAssertEqual(down(at: 10, busy: true), .suppress)
        XCTAssertEqual(gesture.keyDown(), .cancel(.key))
    }

    func testDictationWorksAfterACancelledHold() {
        _ = down(at: 0)
        _ = gesture.keyDown()
        _ = up(at: 1)
        XCTAssertEqual(down(at: 2), .start(.dictate))
        XCTAssertEqual(up(at: 4), .end(.dictate))
    }

    func testMissedReleaseAfterACancelDoesNotBlockTheNextPress() {
        _ = down(at: 0)
        _ = gesture.keyDown()
        // The release never arrived (the tap was off); the state replay says Control is up, then a new press
        XCTAssertEqual(up(at: 3), .passThrough)
        XCTAssertEqual(down(at: 4), .start(.dictate))
    }

    // MARK: - No stuck Control

    func testHoldingCoversTheWholeHoldAndNothingElse() {
        XCTAssertFalse(gesture.isHolding)
        _ = down(at: 0)
        XCTAssertTrue(gesture.isHolding)
        XCTAssertEqual(flags(at: 0.5, control: true, shift: true), .rewriteHint)
        XCTAssertTrue(gesture.isHolding, "Shift's events during the hold must have Control cleared")
        XCTAssertEqual(flags(at: 0.8, control: true), .passThrough)
        XCTAssertTrue(gesture.isHolding, "So must Shift's release")
        XCTAssertEqual(up(at: 1.5), .end(.rewrite))
        XCTAssertFalse(gesture.isHolding)
    }

    func testACancelledHoldIsNoLongerHeld() {
        _ = down(at: 0)
        _ = gesture.keyDown()
        XCTAssertFalse(gesture.isHolding, "After Ctrl+C the app has seen Control, so its flags are left alone")
    }

    func testForwardedFlagsClearControlOnlyDuringAHold() {
        let ctrlShift: CGEventFlags = [.maskControl, .maskShift]
        XCTAssertEqual(HotkeyService.forwardedFlags(ctrlShift, holding: true), .maskShift)
        XCTAssertEqual(HotkeyService.forwardedFlags(ctrlShift, holding: false), ctrlShift)
    }

    func testIdleKeysAndClicksAreIgnored() {
        XCTAssertEqual(gesture.keyDown(), .passThrough)
        XCTAssertEqual(gesture.mouseDown(), .passThrough)
        XCTAssertEqual(down(at: 0), .start(.dictate), "Nothing was left behind by idle events")
    }

    func testSwallowedEvents() {
        XCTAssertTrue(PushToTalkGesture.Action.start(.dictate).swallowsEvent)
        XCTAssertTrue(PushToTalkGesture.Action.end(.rewrite).swallowsEvent)
        XCTAssertTrue(PushToTalkGesture.Action.cancel(.tooShort).swallowsEvent)
        XCTAssertTrue(PushToTalkGesture.Action.suppress.swallowsEvent)
        XCTAssertFalse(PushToTalkGesture.Action.rewriteHint.swallowsEvent, "Shift reaches the app")
        XCTAssertFalse(PushToTalkGesture.Action.passThrough.swallowsEvent)
    }

    // MARK: - Tap disabled by macOS

    func testReplayAfterTheTapWasOffEndsTheHold() {
        _ = flags(at: 0, control: true, shift: true)
        // The release happened while the tap was off; the replay of the live state shows nothing held
        XCTAssertEqual(flags(at: 2), .end(.rewrite))
    }

    func testReplayWhileStillHeldKeepsTheHold() {
        _ = down(at: 0)
        XCTAssertEqual(down(at: 2, busy: true), .suppress)
        XCTAssertEqual(up(at: 3, busy: true), .end(.dictate))
    }

    // MARK: - Helpers

    private func flags(at seconds: TimeInterval, control: Bool = false, shift: Bool = false,
                       commandOrOption: Bool = false, busy: Bool = false) -> PushToTalkGesture.Action {
        gesture.flagsChanged(control: control, shift: shift, commandOrOption: commandOrOption,
                             now: t0 + seconds, pipelineBusy: busy)
    }

    private func down(at seconds: TimeInterval, busy: Bool = false) -> PushToTalkGesture.Action {
        flags(at: seconds, control: true, busy: busy)
    }

    private func up(at seconds: TimeInterval, busy: Bool = false) -> PushToTalkGesture.Action {
        flags(at: seconds, busy: busy)
    }
}
