## MODIFIED Requirements

### Requirement: Microphone selection is respected
The system SHALL use the microphone device selected in Settings for all audio capture. If the selected device becomes unavailable, the system SHALL fall back to the system default microphone and notify the user.

#### Scenario: User selects a specific USB microphone in Settings
- **WHEN** push-to-talk is triggered
- **THEN** the system captures audio from the USB microphone, not the built-in mic

#### Scenario: Selected microphone is disconnected mid-session
- **WHEN** the selected microphone is unplugged while the app is running
- **THEN** the system switches to the system default microphone, and says so on the menu bar icon, in the recording capsule if it's showing, and in Settings > General
