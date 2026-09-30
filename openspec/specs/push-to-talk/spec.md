# push-to-talk Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: Global Control key activates recording
The system SHALL register a global CGEventTap that monitors keyDown and keyUp events for the Control key, capturing audio from the selected microphone for the duration the key is held, regardless of which application has focus.

#### Scenario: User holds Control to start recording
- **WHEN** the user presses and holds the Control key while Honyaku is running
- **THEN** the system begins capturing audio from the active microphone and displays a recording indicator in the menu bar icon

#### Scenario: User releases Control to stop recording
- **WHEN** the user releases the Control key after holding it
- **THEN** the system stops audio capture and immediately triggers the transcription pipeline with the captured audio

#### Scenario: Control key press is shorter than minimum duration
- **WHEN** the user taps the Control key for less than 300ms
- **THEN** the system discards the audio buffer and does not trigger transcription

---

### Requirement: Recording does not interfere with system Control key usage
The system SHALL pass through all Control key combinations (e.g., Ctrl+C, Ctrl+Z) to the active application and SHALL NOT intercept modifier+key chords as recording triggers.

#### Scenario: User presses Control+C while Honyaku is running
- **WHEN** the user presses Ctrl+C in any application
- **THEN** the system forwards the event to the active application and does not start recording

---

### Requirement: Accessibility permission is required for the hotkey
The system SHALL require and prompt for macOS Accessibility permission before activating the CGEventTap. If permission is denied, the push-to-talk feature SHALL be disabled with a visible status indicator.

#### Scenario: Accessibility permission not yet granted on first launch
- **WHEN** the app launches for the first time without Accessibility permission
- **THEN** the system displays an onboarding step directing the user to grant Accessibility access in System Settings, and does not attempt to register the event tap

#### Scenario: Accessibility permission is revoked after app is running
- **WHEN** the user revokes Accessibility permission while the app is running
- **THEN** the system detects the revocation, disables the hotkey, and shows a warning in the menu bar popover

---

### Requirement: CGEventTap does not retain non-trigger key event data
The system SHALL NOT log, buffer, store, or otherwise retain any data from key events observed by the CGEventTap other than the bare Control keydown/keyup that triggers recording. All non-triggering key events SHALL be passed through immediately without inspection of their payload beyond determining they are not a bare Control keypress.

#### Scenario: User types while Honyaku is running
- **WHEN** the user types characters in any application while the CGEventTap is active
- **THEN** each keystroke is forwarded immediately to the active application and no character data is retained by Honyaku

#### Scenario: User presses a non-Control system shortcut
- **WHEN** the user presses any key combination not involving bare Control (e.g., ⌘S, Option+F4)
- **THEN** the event is passed through without any data being recorded by the CGEventTap handler

---

### Requirement: Concurrent recording is prevented while pipeline is processing
The system SHALL NOT start a new recording while the transcription pipeline is already processing a previous recording. Attempting push-to-talk during processing SHALL surface a visible busy indicator.

#### Scenario: User presses Control while pipeline is processing
- **WHEN** the user holds the Control key while transcription or cleanup is in progress
- **THEN** the system does not start audio capture, displays a "Processing…" state in the menu bar icon, and ignores the keydown until the pipeline is idle

#### Scenario: Pipeline completes and user immediately presses Control again
- **WHEN** the pipeline finishes and the user presses Control within 100ms
- **THEN** a new recording starts normally

---

### Requirement: Visual recording indicator during capture
The system SHALL update the menu bar icon and/or show a HUD to indicate active recording state so the user knows audio is being captured.

#### Scenario: Recording is active
- **WHEN** audio capture is in progress
- **THEN** the menu bar icon animates (e.g., pulsing waveform) and an optional floating HUD shows elapsed recording time

#### Scenario: Recording ends and transcription begins
- **WHEN** the Control key is released and transcription starts
- **THEN** the menu bar icon changes to a processing state and the HUD (if shown) displays "Transcribing…"

### Requirement: A press never leaves recording active
Every Control press that starts a recording SHALL end with capture either handed to the transcription pipeline or cancelled. When a press ends without transcription, the system SHALL stop audio capture, release the microphone, discard the captured audio, and return to idle. Resetting a stale press record SHALL NOT discard a hold whose recording is still active.

#### Scenario: Quick tap is discarded and the mic is released
- **WHEN** the user presses and releases the Control key within 300 ms
- **THEN** audio capture stops, the microphone is released, the audio is discarded, no transcription runs, and the status returns to idle

#### Scenario: Push-to-talk keeps working after a quick tap
- **GIVEN** the user has just made a quick tap under 300 ms
- **WHEN** the user holds Control for at least 300 ms and releases it
- **THEN** a new recording starts and is transcribed on release

#### Scenario: Long hold survives other Control-only modifier events
- **WHEN** the user has held Control for more than 5 seconds and another Control-only modifier event arrives (for example the second Control key or Fn)
- **THEN** the recording continues, and releasing Control ends it and triggers transcription

---

### Requirement: Push-to-talk is active from launch
When setup is complete and Accessibility is granted, the system SHALL install the Control-key listener at launch, without the user opening the menu bar popover. Opening the popover SHALL still retry installing the listener, for when Accessibility was granted after launch.

#### Scenario: Launch after setup
- **GIVEN** setup is complete and Accessibility is granted
- **WHEN** Honyaku launches (at login, via Quit & Relaunch, or by replacing an older copy)
- **THEN** holding Control records and transcribes without the popover ever being opened

#### Scenario: Accessibility granted after launch
- **GIVEN** Honyaku launched without Accessibility
- **WHEN** the user grants Accessibility and then opens the popover
- **THEN** the listener is installed

---

### Requirement: The Control listener recovers when macOS disables it
If macOS disables the event tap (by timeout or user input), the system SHALL re-enable it straight away. It SHALL then reconcile any press in progress with the current Control key state. If Control is no longer held, the press SHALL end exactly as a release would: transcribed if held for 300 ms or more, otherwise cancelled. The microphone SHALL NOT stay on because a release event was missed.

#### Scenario: Tap disabled mid-hold, Control released while disabled
- **WHEN** macOS disables the tap during a hold and the user releases Control before the tap is re-enabled
- **THEN** on re-enable the recording is ended (transcribed or cancelled by duration) and the mic is released

#### Scenario: Tap disabled mid-hold, Control still held
- **WHEN** macOS disables the tap during a hold and Control is still held when it's re-enabled
- **THEN** the recording continues, and the later release ends it normally

