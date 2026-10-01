import AppKit
import Carbon.HIToolbox

/// Registers a system-wide CGEventTap that activates push-to-talk on bare Control keydown.
/// Uses flagsChanged events because Control is a modifier key — it never fires keyDown/keyUp.
final class HotkeyService: HotkeyServiceProtocol {
    var onRecordingStarted: ((DictationMode) -> Void)?
    var onRecordingEnded: ((DictationMode) -> Void)?
    var onRecordingCancelled: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gesture = PushToTalkGesture()
    private var isPipelineBusy: (() -> Bool) = { false }

    func setPipelineBusyCheck(_ check: @escaping () -> Bool) {
        isPipelineBusy = check
    }

    func start() throws {
        guard eventTap == nil else { return }  // already running
        guard AXIsProcessTrusted() else {
            throw HotkeyError.accessibilityNotGranted
        }
        // Modifier keys (Control, Shift, Option, Command) fire flagsChanged, NOT keyDown/keyUp
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handler

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS switched the tap off; a release that happened meanwhile was never delivered, so
            // re-enable and replay the live Control state — otherwise the mic stays on
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            _ = apply(flags: CGEventSource.flagsState(.combinedSessionState))
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }
        return apply(flags: event.flags) ? nil : Unmanaged.passUnretained(event)
    }

    /// Runs the gesture for a modifier state and fires the matching callback. Returns true to swallow the event.
    private func apply(flags: CGEventFlags) -> Bool {
        let action = gesture.controlChanged(
            controlDown: flags.contains(.maskControl),
            otherModifiers: flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskShift),
            now: Date(),
            pipelineBusy: isPipelineBusy()
        )

        switch action {
        case .start:
            DispatchQueue.main.async { [weak self] in self?.onRecordingStarted?(.dictate) }
            return true  // suppress bare Control from reaching other apps
        case .end:
            DispatchQueue.main.async { [weak self] in self?.onRecordingEnded?(.dictate) }
            return true
        case .cancel:
            // Too short to transcribe — still stop capture so the mic is released
            DispatchQueue.main.async { [weak self] in self?.onRecordingCancelled?() }
            return true
        case .suppress:
            return true
        case .passThrough:
            return false
        }
    }
}

enum HotkeyError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}
