## ADDED Requirements

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
