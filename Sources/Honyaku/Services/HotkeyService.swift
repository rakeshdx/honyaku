import AppKit
import Carbon.HIToolbox
import os

/// Registers a system-wide CGEventTap that activates push-to-talk on Control keydown (Control+Shift rewrites).
/// Uses flagsChanged events because Control is a modifier key — it never fires keyDown/keyUp. Key and mouse
/// presses are seen only to cancel a hold that turned into a shortcut: their type is read, nothing else.
///
/// The tap runs on a thread of its own (`HotkeyTapThread`), never the main thread: it sees every key press
/// and click on the Mac, so Honyaku being busy must never delay them, or its own ⌘V. `gesture` is only
/// touched on that thread; the actions it produces are sent to the main queue.
final class HotkeyService: HotkeyServiceProtocol {
    var onRecordingStarted: ((DictationMode) -> Void)?
    var onRecordingEnded: ((DictationMode) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var onRewriteHint: (() -> Void)?

    /// Whether the tap sees key and mouse presses, so one cancels a hold. False when macOS refused that tap
    /// and the modifiers-only tap is used instead. Read on the main thread after `start()`.
    private(set) var watchesKeyPresses = false

    /// Set on the main thread before the tap thread starts, cleared only after it has finished; the tap
    /// thread reads it to re-enable the tap.
    private var eventTap: CFMachPort?
    private var tapThread: HotkeyTapThread?
    /// Tap thread only.
    private var gesture = PushToTalkGesture()
    /// Set from the main thread whenever the status changes, read by the tap: it never reads main-actor state.
    private let pipelineBusy = OSAllocatedUnfairLock(initialState: false)
    private let ownProcessID = Int64(ProcessInfo.processInfo.processIdentifier)

    func setPipelineBusy(_ busy: Bool) {
        pipelineBusy.withLock { $0 = busy }
    }

    func start() throws {
        guard eventTap == nil else { return }  // already running
        guard AXIsProcessTrusted() else {
            throw HotkeyError.accessibilityNotGranted
        }
        // Modifier keys (Control, Shift, Option, Command) fire flagsChanged, NOT keyDown/keyUp. If macOS refuses
        // the key and mouse events, push-to-talk still works, just without cancelling on a shortcut
        var watchesKeys = true
        var tap = makeTap(mask: Self.fullMask)
        if tap == nil {
            watchesKeys = false
            tap = makeTap(mask: Self.modifiersMask)
        }
        guard let tap else { throw HotkeyError.tapCreationFailed }

        eventTap = tap
        watchesKeyPresses = watchesKeys
        tapThread = HotkeyTapThread(tap: tap)
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
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        tapThread?.stop()  // returns once the tap thread has finished, so nothing touches the tap after this
        CFMachPortInvalidate(tap)
        tapThread = nil
        eventTap = nil
        watchesKeyPresses = false
    }

    /// The flags of a modifier event passed through to the app. Control's own press is swallowed, so while a
    /// hold lasts the app must not see Control held — or, after Honyaku swallows the release too, it would
    /// think Control is stuck down (VMs, remote desktop and games track modifiers from these events).
    static func forwardedFlags(_ flags: CGEventFlags, holding: Bool) -> CGEventFlags {
        holding ? flags.subtracting(.maskControl) : flags
    }

    // MARK: - Event handler (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
            if apply(flags: event.flags) { return nil }
            if gesture.isHolding { event.flags = Self.forwardedFlags(event.flags, holding: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            // Only the type and the posting process are read: never the key code or characters. Honyaku's own
            // ⌘V (its paste) never cancels a hold. While idle this returns at once
            guard event.getIntegerValueField(.eventSourceUnixProcessID) != ownProcessID else {
                return Unmanaged.passUnretained(event)
            }
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
            pipelineBusy: pipelineBusy.withLock { $0 }
        )
        fire(action)
        // Control's own press and release are kept from other apps
        return action.swallowsEvent
    }

    /// The callbacks run on the main queue, in the order the tap produced them.
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

/// A thread that does nothing but run one event tap's run loop, so the main thread being busy (saving
/// History, a password check waiting on an app that doesn't answer) never holds up the Mac's key presses
/// and clicks, and never makes macOS disable the tap for being slow.
final class HotkeyTapThread {
    private let stopping = OSAllocatedUnfairLock(initialState: false)
    private let runLoop = OSAllocatedUnfairLock<CFRunLoop?>(uncheckedState: nil)
    private let finished = DispatchSemaphore(value: 0)

    /// Starts the thread and enables `tap` on it; returns once its run loop has the tap.
    init(tap: CFMachPort) {
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        let (stopping, runLoop, finished) = (self.stopping, self.runLoop, self.finished)
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            runLoop.withLock { $0 = loop }
            ready.signal()
            // Short turns, so a stop that lands before the loop starts running is still seen within a second
            while !stopping.withLock({ $0 }) {
                _ = CFRunLoopRunInMode(.defaultMode, 1, false)
            }
            CFRunLoopRemoveSource(loop, source, .commonModes)
            finished.signal()
        }
        thread.name = "Honyaku hotkey tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    /// Stops the run loop and waits for the thread to finish.
    func stop() {
        stopping.withLock { $0 = true }
        if let loop = runLoop.withLock({ $0 }) {
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
        finished.wait()
    }
}

enum HotkeyError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}
