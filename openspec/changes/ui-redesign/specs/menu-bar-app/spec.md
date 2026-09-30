## MODIFIED Requirements

### Requirement: Clicking the menu bar icon opens a popover with transcript history and status
Clicking the Honyaku menu bar icon SHALL open the Settings window directly. There is no popover and no transcript list in the menu bar; history lives in Settings > History.
- **While first run is incomplete** (permissions or model setup), clicking the icon SHALL open the first-run window instead.
- **Right-clicking** (or Control-clicking) the icon SHALL show a menu with "Settings…" and "Quit Honyaku".
- **The icon itself** SHALL keep reflecting state: idle, recording, transcribing or processing, and error.
- **Current status** SHALL be shown at the top of the General tab: the Control keycap with "Hold Control to talk", the active speech model, whether cleanup is on, the full text of any error, and any background model download with its progress.

#### Scenario: User clicks the menu bar icon after setup
- **WHEN** the user clicks the Honyaku icon in the menu bar
- **THEN** the Settings window opens (or comes to the front) on the last tab used, and no popover appears

#### Scenario: User right-clicks the icon
- **WHEN** the user right-clicks the Honyaku icon
- **THEN** a menu with "Settings…" and "Quit Honyaku" appears, and "Quit Honyaku" quits the app

#### Scenario: First run isn't finished
- **GIVEN** Accessibility isn't granted yet, or models haven't been set up
- **WHEN** the user clicks the icon
- **THEN** the first-run window opens at its first incomplete step

#### Scenario: An error occurred
- **WHEN** the last dictation failed and the user clicks the icon
- **THEN** the General tab shows the error's full text, and the next successful dictation clears it

#### Scenario: A model is downloading in the background
- **WHEN** a migrated model is downloading and the user opens Settings
- **THEN** the General tab and the model's row in the Models tab show the download's progress

---

### Requirement: Settings panel is accessible from the popover
The system SHALL provide a single Settings window, opened by clicking the menu bar icon (or "Settings…" in its right-click menu), with these tabs:
- **General:** current status (see the menu bar icon requirement), launch at login, microphone device, permission status with a way to fix each missing permission.
- **Models:** the speech and cleanup models, each with its download state, disk space used, "Use" (only for downloaded models), Download and Delete.
- **Dictation:** cleanup on/off, speaker labels on/off, and the cleanup prompt with "Reset to default", under an Advanced disclosure.
- **History:** a searchable list of transcripts with copy, and "Delete all history…" behind a confirmation.
- **Privacy:** the offline guarantees, and the Hugging Face access token under an Advanced disclosure.

#### Scenario: User opens Settings
- **WHEN** the user clicks the menu bar icon, or chooses "Settings…" from its right-click menu
- **THEN** the Settings window opens on the General tab, or the last tab used, and comes to the front

#### Scenario: User clicks Settings again while it's open
- **GIVEN** the Settings window is already open, possibly behind other windows
- **WHEN** the user clicks the menu bar icon again, or chooses "Settings…" from its menu
- **THEN** that same window comes to the front, and no second Settings window opens

#### Scenario: User closes Settings
- **WHEN** the user closes the Settings window and later clicks Settings again
- **THEN** a single Settings window opens

#### Scenario: User searches history
- **WHEN** the user types "invoice" into the History search field
- **THEN** only transcripts containing "invoice" (ignoring case and accents) are listed

---

### Requirement: Permission onboarding is presented inline at first launch
The system SHALL present first run as a single window with three steps, in order:
1. **Permissions:** Microphone and Accessibility, each explaining why it's needed, with a button that requests it or opens the right System Settings pane. It shows "Restart required" with Quit & Relaunch only when Accessibility can't take effect without one.
2. **Models:** the models to download (see model-management).
3. **Try it:** holding Control records a real dictation, whose result appears in the window rather than being pasted.

The window SHALL resume at the first incomplete step when reopened.

#### Scenario: Microphone permission is not granted
- **WHEN** first run opens without microphone access
- **THEN** the Permissions step shows Microphone with a Grant button, and Continue stays unavailable until access is granted

#### Scenario: Accessibility permission is not granted
- **WHEN** first run opens without Accessibility access
- **THEN** the Permissions step explains that the global Control key needs it, with a button that opens the Accessibility pane

#### Scenario: User completes the live test
- **WHEN** on the Try it step the user holds Control and says "hello"
- **THEN** the transcript appears in the first-run window, and the button changes to "Start using Honyaku"

---

### Requirement: Transcript history is stored locally and clearable
The system SHALL persist the transcript history to disk at `~/Library/Application Support/Honyaku/history.json`. The user SHALL be able to delete a single transcript, or all history after confirming, in Settings > History. History SHALL never be transmitted off the device.

#### Scenario: User deletes all history
- **WHEN** the user chooses "Delete all history…" in Settings and confirms
- **THEN** all transcript records are deleted from disk and the list empties

#### Scenario: User cancels deleting all history
- **WHEN** the user chooses "Delete all history…" and then cancels
- **THEN** no transcript is deleted

#### Scenario: App restarts after transcripts were produced
- **WHEN** the app is relaunched
- **THEN** the transcript history from the previous session is restored from disk
