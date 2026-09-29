import Foundation

/// Timing rules for the bare-Control push-to-talk gesture, kept free of CGEvent so they can be unit tested.
/// Every `.start` is eventually followed by `.end` or `.cancel`, so a recording is never left running.
struct PushToTalkGesture {
    enum Action: Equatable {
        case start        // begin recording; swallow the event
        case end          // hold long enough — transcribe; swallow the event
        case cancel       // released too soon — discard; swallow the event
        case suppress     // swallow the event, no state change
        case passThrough  // forward the event untouched
    }

    var minimumHoldSeconds: TimeInterval = 0.3
    /// A press older than this with no key-up is treated as orphaned — but only when nothing is recording.
    var staleAfterSeconds: TimeInterval = 5

    private(set) var keyDownTime: Date?

    mutating func controlChanged(controlDown: Bool, otherModifiers: Bool, now: Date, pipelineBusy: Bool) -> Action {
        if controlDown && !otherModifiers {
            if let t = keyDownTime {
                // Clearing a stale press while busy would drop the key-up of an active hold
                guard !pipelineBusy, now.timeIntervalSince(t) > staleAfterSeconds else {
                    return .suppress  // repeat
                }
                keyDownTime = nil
            }
            guard !pipelineBusy else { return .passThrough }
            keyDownTime = now
            return .start

        } else if !controlDown, let downTime = keyDownTime {
            keyDownTime = nil
            return now.timeIntervalSince(downTime) >= minimumHoldSeconds ? .end : .cancel
        }

        return .passThrough
    }
}
