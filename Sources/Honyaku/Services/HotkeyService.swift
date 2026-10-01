import AppKit
import Carbon.HIToolbox

/// Registers a system-wide CGEventTap that activates push-to-talk on Control keydown (Control+Shift rewrites).
/// Uses flagsChanged events because Control is a modifier key — it never fires keyDown/keyUp. Key and mouse
/// presses are seen only to cancel a hold that turned into a shortcut: their type is read, nothing else.
final class HotkeyService: HotkeyServiceProtocol {
    var onRecordingStarted: ((DictationMode) -> Void)?
    var onRecordingEnded: ((DictationMode) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var onRewriteHint: (() -> Void)?

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
        // Modifier keys (Control, Shift, Option, Command) fire flagsChanged, NOT keyDown/keyUp. If macOS refuses
        // the key and mouse events, push-to-talk still works, just without cancelling on a shortcut
        guard let tap = makeTap(mask: Self.fullMask) ?? makeTap(mask: Self.modifiersMask) else {
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    static let modifiersMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
    static let fullMask: CGEventMask = modifiersMask
        | (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)

    private func makeTap(mask: CGEventMask) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
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
        let action: PushToTalkGesture.Action
        switch type {
        case .flagsChanged:
            return apply(flags: event.flags) ? nil : Unmanaged.passUnretained(event)
        case .keyDown:
            // Only the type is read: never the key code or characters. While idle this returns at once
            action = gesture.keyDown()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            action = gesture.mouseDown()
        default:
            return Unmanaged.passUnretained(event)
        }
        // A key or click never changes a recording's start or end, only cancels it; the event always reaches the app
        if action != .passThrough { fire(action) }
        return Unmanaged.passUnretained(event)
    }

    /// Runs the gesture for a modifier state and fires the matching callback. Returns true to swallow the event.
    private func apply(flags: CGEventFlags) -> Bool {
        let action = gesture.flagsChanged(
            control: flags.contains(.maskControl),
            shift: flags.contains(.maskShift),
            commandOrOption: flags.contains(.maskCommand) || flags.contains(.maskAlternate),
            now: Date(),
            pipelineBusy: isPipelineBusy()
        )
        fire(action)
        // Control's own press and release are kept from other apps
        return action.swallowsEvent
    }

    private func fire(_ action: PushToTalkGesture.Action) {
        switch action {
        case .start(let mode):
            DispatchQueue.main.async { [weak self] in self?.onRecordingStarted?(mode) }
        case .end(let mode):
            DispatchQueue.main.async { [weak self] in self?.onRecordingEnded?(mode) }
        case .cancel:
            // Too short, or a shortcut: still stop capture so the mic is released
            DispatchQueue.main.async { [weak self] in self?.onRecordingCancelled?() }
        case .rewriteHint:
            DispatchQueue.main.async { [weak self] in self?.onRewriteHint?() }
        case .suppress, .passThrough:
            break
        }
    }
}

enum HotkeyError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}
