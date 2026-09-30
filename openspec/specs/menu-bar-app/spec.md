# menu-bar-app Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: App runs exclusively in the menu bar with no Dock icon
The system SHALL present itself as a macOS menu bar extra using `MenuBarExtra`. It SHALL NOT appear in the Dock or in the app switcher (Cmd+Tab).

#### Scenario: User opens the app for the first time
- **WHEN** Honyaku launches
- **THEN** a menu bar icon appears in the system status bar and no Dock icon is visible

---

### Requirement: Menu bar icon reflects application state
The system SHALL use distinct menu bar icon states to communicate: idle, recording, processing (transcribing/cleaning), and error.

#### Scenario: App is idle
- **WHEN** the app is running and no recording is in progress
- **THEN** the menu bar icon is static (waveform outline)

#### Scenario: Recording is in progress
- **WHEN** the Control key is held and audio capture is active
- **THEN** the menu bar icon animates with a pulsing or active recording indicator

#### Scenario: Transcription or cleanup is in progress
- **WHEN** audio has been captured and the pipeline is processing
- **THEN** the menu bar icon shows a spinner or processing animation

---

### Requirement: Clicking the menu bar icon opens a popover with transcript history and status
The system SHALL display a popover containing the last N transcripts, current status, and quick-access actions (copy last result, clear history, open Settings).

#### Scenario: User clicks the menu bar icon while idle
- **WHEN** the user single-clicks the Honyaku icon in the menu bar
- **THEN** a popover opens showing the transcript history list and a "Settings" button

#### Scenario: Transcript history is empty
- **WHEN** the popover opens and no transcripts have been produced in this session
- **THEN** the popover shows an empty-state message with a hint to use Control+hold to start

---

### Requirement: Settings panel is accessible from the popover
The system SHALL provide a Settings view accessible from the menu bar popover with the following configurable options:
- Active speech model (with download state)
- Active cleanup model (with download state)
- Cleanup enabled/disabled toggle
- Customizable cleanup prompt
- Microphone device selection
- Speaker diarization enabled/disabled toggle
- Launch at login toggle
- Transcript history: view, copy, and clear

#### Scenario: User opens Settings
- **WHEN** the user clicks "Settings" in the popover
- **THEN** a Settings panel opens within the popover (or a dedicated window) with all configurable options

---

### Requirement: App launches at login by default
The system SHALL register itself as a login item using `SMAppService` so it starts automatically with macOS. This SHALL be enabled by default and toggleable in Settings.

#### Scenario: First launch after installation
- **WHEN** the app runs for the first time
- **THEN** launch-at-login is automatically enabled via `SMAppService`

#### Scenario: User disables launch at login
- **WHEN** the user toggles "Launch at Login" off in Settings
- **THEN** the system unregisters the login item and the app no longer launches automatically

---

### Requirement: Permission onboarding is presented inline at first launch
The system SHALL present a guided onboarding flow for required permissions (Microphone, Accessibility) within the app UI before the hotkey is activated, explaining why each permission is needed.

#### Scenario: Microphone permission is not granted
- **WHEN** the app starts without microphone access
- **THEN** the onboarding UI shows a "Grant Microphone Access" step with a button that opens System Settings to the correct pane

#### Scenario: Accessibility permission is not granted
- **WHEN** the app starts without Accessibility access
- **THEN** the onboarding UI shows a "Grant Accessibility Access" step explaining the global hotkey requirement

---

### Requirement: Transcript history is stored locally and clearable
The system SHALL persist the transcript history to disk at `~/Library/Application Support/Honyaku/history.json`. The user SHALL be able to clear all history from Settings. History SHALL never be transmitted off the device.

#### Scenario: User clears transcript history
- **WHEN** the user clicks "Clear History" in Settings and confirms the action
- **THEN** all transcript records are deleted from disk and the history list empties

#### Scenario: App restarts after transcripts were produced
- **WHEN** the app is relaunched
- **THEN** the transcript history from the previous session is restored from disk

---

### Requirement: Transcript history file has restrictive permissions and is excluded from backup
The system SHALL create `history.json` with Unix file permissions 600 (owner read/write only). The file SHALL be marked with `URLResourceValues.isExcludedFromBackup = true` so it is not included in Time Machine, iCloud Drive, or any other macOS backup mechanism.

#### Scenario: history.json is created for the first time
- **WHEN** the first transcript is written to disk
- **THEN** `history.json` is created with permissions 600 and flagged as excluded from backup

#### Scenario: User checks iCloud Drive for Honyaku files
- **WHEN** a user inspects their iCloud Drive storage
- **THEN** no Honyaku transcript history or model files appear in iCloud Drive

### Requirement: Only one instance of the app runs at a time
The system SHALL ensure that at most one Honyaku process (bundle identifier `com.honyaku.app`) runs per user session. When a new instance launches while older instances are running, the new instance SHALL request graceful termination of every older instance ("newest wins"). The new instance SHALL NOT install its push-to-talk event tap until no older instance remains.

#### Scenario: Build and run while an older instance is running
- **WHEN** an instance of Honyaku is running and the developer builds and runs a new instance from Xcode
- **THEN** the older instance terminates, the new instance keeps running, and exactly one Honyaku process remains

#### Scenario: Older instance performs its normal quit cleanup
- **WHEN** a new instance terminates an older instance
- **THEN** the older instance terminates through the normal application termination path, so its quit cleanup (pasteboard clearing, temp-file removal) runs

#### Scenario: Older instance does not exit in time
- **WHEN** an older instance has not exited within 3 seconds of the graceful termination request
- **THEN** the new instance force-terminates the older instance

#### Scenario: Only one hotkey listener is active
- **WHEN** a new instance has replaced an older instance
- **THEN** a single press-and-hold of the Control key starts exactly one recording and produces at most one paste

#### Scenario: No other instance is running
- **WHEN** Honyaku launches and no other instance is running
- **THEN** startup proceeds normally without delay

---

### Requirement: Quit & Relaunch starts exactly one fresh instance
When the user chooses "Quit & Relaunch" from the permission onboarding, the system SHALL terminate the current process and then launch a new instance of the same app bundle only after the current process has exited. The new instance SHALL read permission state fresh at launch.

#### Scenario: User relaunches after granting Accessibility
- **WHEN** the user grants Accessibility in System Settings and clicks "Quit & Relaunch"
- **THEN** the current process exits, a new process for the same app bundle starts, and exactly one Honyaku process is running afterwards

#### Scenario: Relaunched instance reflects the current grant
- **WHEN** the relaunched instance starts and Accessibility is granted for its code signature
- **THEN** the onboarding shows Accessibility as granted and the push-to-talk event tap is installed

