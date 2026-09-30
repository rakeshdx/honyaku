## MODIFIED Requirements

### Requirement: Visual recording indicator during capture
While a dictation is in progress, the system SHALL show a floating capsule at the bottom centre of the screen that contains the Control keycap, and:
- **while recording:** a live input-level meter and the elapsed time
- **while transcribing or cleaning up:** "Transcribing…"

The capsule SHALL fade out once the text is pasted, or when the dictation is discarded or fails. A failure SHALL also show briefly as a short error. The capsule SHALL NOT take keyboard focus, activate Honyaku or intercept clicks. With Reduce Motion on, it SHALL appear and disappear without animation and show the level as a static bar. The menu bar icon SHALL continue to reflect state.

#### Scenario: Recording is active
- **WHEN** the user is holding Control and speaking
- **THEN** the capsule shows the level meter moving with their voice and the elapsed time counting up, and the frontmost app keeps keyboard focus

#### Scenario: Recording ends and transcription begins
- **WHEN** the Control key is released and transcription starts
- **THEN** the capsule shows "Transcribing…", and fades once the text is pasted

#### Scenario: Quick tap
- **WHEN** the user taps Control for under 300 ms
- **THEN** the capsule does not appear, or disappears at once, with no error

#### Scenario: Reduce Motion is on
- **WHEN** Reduce Motion is enabled in macOS
- **THEN** the capsule appears and disappears without animation
