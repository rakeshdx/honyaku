## MODIFIED Requirements

### Requirement: Visual recording indicator during capture
While a dictation is in progress, the system SHALL show a floating capsule at the bottom centre of the screen that contains the Control keycap, and:
- **while recording:** a live input-level meter and the elapsed time
- **while transcribing or cleaning up:** "Transcribing…"

The capsule SHALL fade out once the text is pasted, or when the dictation is discarded or fails. A failure SHALL also show briefly as a short error. The capsule SHALL NOT take keyboard focus, activate Honyaku or intercept clicks. With Reduce Motion on, it SHALL appear and disappear without animation and show the level as a static bar. The menu bar icon SHALL continue to reflect state.
- A recording that starts while the capsule is fading out SHALL cancel the fade, and the capsule SHALL stay shown for that recording.
- The capsule SHALL stay centred on its screen when its content changes width (for example from the level meter to "Transcribing…" or an error).
- The capsule SHOULD be excluded from screenshots and screen sharing, like other system overlays.
- The keycap's glyph SHALL keep at least 3:1 contrast against the key face in every state, in light and dark mode.

#### Scenario: Recording is active
- **WHEN** the user is holding Control and speaking
- **THEN** the capsule shows the level meter moving with their voice and the elapsed time counting up, and the frontmost app keeps keyboard focus

#### Scenario: Recording ends and transcription begins
- **WHEN** the Control key is released and transcription starts
- **THEN** the capsule shows "Transcribing…", still centred, and fades once the text is pasted

#### Scenario: Quick tap
- **WHEN** the user taps Control for under 300 ms
- **THEN** the capsule does not appear, or disappears at once, with no error

#### Scenario: New recording during the fade-out
- **GIVEN** a dictation was just pasted and the capsule is fading out
- **WHEN** the user holds Control again
- **THEN** the capsule returns to full opacity and stays shown for the new recording

#### Scenario: Reduce Motion is on
- **WHEN** Reduce Motion is enabled in macOS
- **THEN** the capsule appears and disappears without animation

---

### Requirement: Accessibility permission is required for the hotkey
The system SHALL require and prompt for macOS Accessibility permission before activating the CGEventTap. If permission is denied, the push-to-talk feature SHALL be disabled with a visible status indicator.

#### Scenario: Accessibility permission not yet granted on first launch
- **WHEN** the app launches for the first time without Accessibility permission
- **THEN** the system displays an onboarding step directing the user to grant Accessibility access in System Settings, and does not attempt to register the event tap

#### Scenario: Accessibility permission is revoked after app is running
- **WHEN** the user revokes Accessibility permission while the app is running
- **THEN** the system detects the revocation, disables the hotkey, and shows the error on the menu bar icon and in Settings > General

---

### Requirement: Push-to-talk is active from launch
When setup is complete and Accessibility is granted, the system SHALL install the Control-key listener at launch, without the user clicking the menu bar icon. Clicking the icon SHALL still retry installing the listener, for when Accessibility was granted after launch.

#### Scenario: Launch after setup
- **GIVEN** setup is complete and Accessibility is granted
- **WHEN** Honyaku launches (at login, via Quit & Relaunch, or by replacing an older copy)
- **THEN** holding Control records and transcribes without the menu bar icon ever being clicked

#### Scenario: Accessibility granted after launch
- **GIVEN** Honyaku launched without Accessibility
- **WHEN** the user grants Accessibility and then clicks the menu bar icon
- **THEN** the listener is installed, and the "Accessibility not granted" error clears
