import Foundation

/// Timing rules for the Control push-to-talk gesture, kept free of CGEvent so they can be unit tested.
/// Every `.start` is eventually followed by `.end` or `.cancel`, so a recording is never left running.
///
/// A hold during which Shift was down at any moment is a rewrite; the mode is decided at release, so the
/// order of Control and Shift doesn't matter. A key press, a click, or Command or Option during the hold
/// means the user is using a Control shortcut: the hold is cancelled, and the cancelling event and the
/// Control release that follows reach the app, so it sees Control go up as well as down.
struct PushToTalkGesture {
    enum CancelReason: Equatable {
        case tooShort  // released under the minimum hold
        case chord     // Command or Option joined the hold
        case key       // a non-modifier key went down
        case click     // a mouse button went down
    }

    enum Action: Equatable {
        case start(DictationMode)  // begin recording; swallow the event
        case end(DictationMode)    // held long enough: transcribe in this mode; swallow the event
        case cancel(CancelReason)  // discard the recording; see `swallowsEvent`
        case rewriteHint           // Shift seen for the first time in a hold that started as dictation
        case suppress              // swallow the event, no state change
        case passThrough           // forward the event untouched

        /// Whether the event that produced this action is kept from the app in front. Only Control's own
        /// press and release are swallowed; the key, click or modifier that cancels a hold reaches the app,
        /// and so does the release of a cancelled hold.
        var swallowsEvent: Bool {
            switch self {
            case .start, .end, .suppress, .cancel(.tooShort): return true
            case .cancel, .rewriteHint, .passThrough: return false
            }
        }
    }

    var minimumHoldSeconds: TimeInterval = 0.3
    /// A press older than this with no key-up is treated as orphaned — but only when nothing is recording.
    var staleAfterSeconds: TimeInterval = 5

    private(set) var keyDownTime: Date?
    /// Shift was down at some point during the current hold.
    private(set) var sawShift = false
    /// The current Control hold was cancelled by a shortcut; its release reaches the app.
    private(set) var cancelledHold = false

    /// A hold is in progress: Control's press was swallowed, so the app must not see Control held in the
    /// modifier events passed through until it ends (`HotkeyService` clears it from their flags).
    var isHolding: Bool { keyDownTime != nil }
    private var controlWasDown = false
    private var shiftWasDown = false

    /// A modifier changed. Only Control, Shift, and whether Command or Option is down, are looked at.
    mutating func flagsChanged(control: Bool, shift: Bool, commandOrOption: Bool, now: Date,
                               pipelineBusy: Bool) -> Action {
        let newPress = control && !controlWasDown
        let shiftChanged = shift != shiftWasDown
        defer {
            controlWasDown = control
            shiftWasDown = shift
        }

        if cancelledHold {
            if !control {
                // The release of a hold a shortcut cancelled. The app saw Control in the cancelling event's
                // flags, so it must see the release too, or it would think Control is still held
                cancelledHold = false
                return .passThrough
            }
            // Still the shortcut's hold, unless a release was missed and this is a new press
            guard newPress else { return .passThrough }
            cancelledHold = false
        }

        var clearedStalePress = false
        if let downTime = keyDownTime {
            if !control {
                keyDownTime = nil
                let mode: DictationMode = sawShift ? .rewrite : .dictate
                sawShift = false
                return now.timeIntervalSince(downTime) >= minimumHoldSeconds ? .end(mode) : .cancel(.tooShort)
            }
            if commandOrOption {
                // Control+Command or Control+Option: a shortcut, not a dictation
                cancelHold()
                return .cancel(.chord)
            }
            if shiftChanged {
                // Shift's own events reach the app. Pressed at any moment, it makes the hold a rewrite
                guard shift, !sawShift else { return .passThrough }
                sawShift = true
                return .rewriteHint
            }
            // Control again (the other Control key, or Fn). Clearing a stale press while busy would drop the
            // key-up of an active hold
            guard !pipelineBusy, now.timeIntervalSince(downTime) > staleAfterSeconds else {
                return .suppress  // repeat
            }
            keyDownTime = nil
            sawShift = false
            clearedStalePress = true
        }

        // Only Control's own press starts a recording: not Shift, Command or Option let go while it's held
        guard control, !commandOrOption, !pipelineBusy, newPress || clearedStalePress else { return .passThrough }
        keyDownTime = now
        sawShift = shift
        return .start(shift ? .rewrite : .dictate)
    }

    /// A non-modifier key went down. Only the fact is used, never which key.
    mutating func keyDown() -> Action {
        guard keyDownTime != nil else { return .passThrough }
        cancelHold()
        return .cancel(.key)
    }

    /// A mouse button went down. Only the fact is used, never where.
    mutating func mouseDown() -> Action {
        guard keyDownTime != nil else { return .passThrough }
        cancelHold()
        return .cancel(.click)
    }

    private mutating func cancelHold() {
        keyDownTime = nil
        sawShift = false
        cancelledHold = true
    }
}
