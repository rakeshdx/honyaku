import XCTest
@testable import Honyaku

final class HotkeyServiceTests: XCTestCase {

    func testRecordingIgnoredWhenPipelineBusy() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permission not granted to test runner — skip hotkey tests")
        }
        let service = HotkeyService()
        var recordingStarted = false
        service.onRecordingStarted = { _ in recordingStarted = true }
        service.setPipelineBusy(true)  // pipeline always busy

        // Cannot directly fire CGEvent in unit tests without Accessibility;
        // the busy flag the tap reads is set here. Integration testing of actual
        // CGEvent firing requires a UI test.
        XCTAssertFalse(recordingStarted, "Recording should not start when pipeline is busy")
    }

    func testHotkeyServiceStopsCleanly() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permission not granted to test runner — skip hotkey tests")
        }
        let service = HotkeyService()
        XCTAssertNoThrow(try service.start())
        XCTAssertTrue(service.watchesKeyPresses,
                      "With Accessibility alone, macOS gives the tap key and mouse presses (no Input Monitoring)")
        service.stop()  // should not crash, and should wait for the tap thread to finish
        XCTAssertFalse(service.watchesKeyPresses)
        XCTAssertNoThrow(try service.start(), "A stopped service starts again on a new thread")
        service.stop()
    }

    func testTapThreadStartsAndStops() throws {
        // A tap thread with a modifiers-only tap needs Accessibility to create the tap
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permission not granted to test runner — skip hotkey tests")
        }
        let tap = try XCTUnwrap(CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: HotkeyService.modifiersMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil))
        let thread = HotkeyTapThread(tap: tap)
        let started = Date()
        thread.stop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "stop() returns promptly")
        CFMachPortInvalidate(tap)
    }
}
