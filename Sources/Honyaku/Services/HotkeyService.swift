import AppKit
import Carbon.HIToolbox

/// Registers a system-wide CGEventTap that activates push-to-talk on bare Control keydown.
/// Uses flagsChanged events because Control is a modifier key — it never fires keyDown/keyUp.
final class HotkeyService: HotkeyServiceProtocol {
    var onRecordingStarted: (() -> Void)?
    var onRecordingEnded: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownTime: Date?
    private let minimumHoldSeconds: Double = 0.3
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
        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let controlDown = flags.contains(.maskControl)
        let hasOtherModifiers = flags.contains(.maskCommand) ||
                                flags.contains(.maskAlternate) ||
                                flags.contains(.maskShift)

        if controlDown && !hasOtherModifiers {
            // Control pressed — start recording if not already started.
            // Treat a stale keyDownTime (>5s) as orphaned from a missed keyup and reset it.
            if let t = keyDownTime, Date().timeIntervalSince(t) > 5 {
                keyDownTime = nil
            }
            guard keyDownTime == nil else {
                return nil  // suppress repeat
            }
            guard !isPipelineBusy() else {
                return Unmanaged.passUnretained(event)
            }
            keyDownTime = Date()
            DispatchQueue.main.async { [weak self] in self?.onRecordingStarted?() }
            return nil  // suppress bare Control from reaching other apps

        } else if !controlDown, let downTime = keyDownTime {
            // Control released
            keyDownTime = nil
            guard Date().timeIntervalSince(downTime) >= minimumHoldSeconds else {
                return nil  // too short — discard
            }
            DispatchQueue.main.async { [weak self] in self?.onRecordingEnded?() }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

enum HotkeyError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}
