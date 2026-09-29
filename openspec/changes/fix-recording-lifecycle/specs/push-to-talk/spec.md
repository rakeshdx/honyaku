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
