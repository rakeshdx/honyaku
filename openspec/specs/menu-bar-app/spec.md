# menu-bar-app Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: App runs exclusively in the menu bar with no Dock icon
The system SHALL present itself as an icon in the macOS menu bar (an `NSStatusItem`). It SHALL NOT appear in the Dock or in the app switcher (Cmd+Tab).

#### Scenario: User opens the app for the first time
- **WHEN** Honyaku launches
- **THEN** a menu bar icon appears in the system status bar and no Dock icon is visible

---

### Requirement: Menu bar icon reflects application state
The system SHALL use distinct menu bar icon symbols for idle, recording, transcribing or cleaning up, and error. The icon SHALL also tell VoiceOver the current state.

#### Scenario: App is idle
- **WHEN** the app is running and no recording is in progress
- **THEN** the menu bar icon is the waveform outline

#### Scenario: Recording is in progress
- **WHEN** the Control key is held and audio capture is active
- **THEN** the menu bar icon shows the filled recording symbol

#### Scenario: Transcription or cleanup is in progress
- **WHEN** audio has been captured and the pipeline is processing
- **THEN** the menu bar icon shows the processing symbol

#### Scenario: VoiceOver reads the icon
- **WHEN** VoiceOver focuses the Honyaku menu bar icon while a dictation is being transcribed
- **THEN** it reads "Honyaku" followed by the state, "Transcribing"

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
The system SHALL present first run as a single window titled "Set up Honyaku", with three steps, in order:
1. **Permissions:** Microphone and Accessibility, each explaining why it's needed, with a button that requests it or opens the right System Settings pane ("Open System Settings"). After the user has been sent to System Settings for Accessibility, the step SHALL also offer Relaunch, for when macOS doesn't report the grant to the running app.
2. **Models:** the models to download (see model-management).
3. **Try it:** holding Control records a real dictation, whose result appears in the window rather than being pasted or saved to history.

The window SHALL resume at the first incomplete step when reopened: Permissions while the microphone or Accessibility isn't granted (even if models were set up before), then Models while setup isn't complete, then Try it.

A dictation SHALL be treated as a Try it test only if the Try it step was showing when its recording started. When the first-run window closes, or the user chooses "Skip for now" or "Start using Honyaku", the test SHALL end: its result is cleared, and a test dictation that is still being transcribed SHALL be discarded, never pasted and never saved to history.

#### Scenario: Microphone permission is not granted
- **WHEN** first run opens without microphone access
- **THEN** the Permissions step shows Microphone with an Allow button, and Continue stays unavailable until access is granted

#### Scenario: Accessibility permission is not granted
- **WHEN** first run opens without Accessibility access
- **THEN** the Permissions step explains that the global Control key needs it, with an "Open System Settings" button that opens the Accessibility pane

#### Scenario: Accessibility is revoked after setup
- **GIVEN** setup was completed earlier, and Accessibility has since been turned off
- **WHEN** the user clicks the menu bar icon
- **THEN** first run opens on the Permissions step, not the Try it step

#### Scenario: User completes the live test
- **WHEN** on the Try it step the user holds Control and says "hello"
- **THEN** the transcript appears in the first-run window, and the button changes to "Start using Honyaku"

#### Scenario: User closes the window during a test dictation
- **GIVEN** the user started a dictation on the Try it step
- **WHEN** they close the first-run window before the transcript arrives
- **THEN** that dictation is discarded: nothing is pasted and nothing is added to history

#### Scenario: User dictates after closing first run
- **GIVEN** the user closed the first-run window on the Try it step
- **WHEN** they hold Control in another app and speak
- **THEN** the text is pasted there and saved to history as usual

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

### Requirement: Clicking the menu bar icon opens Settings
Clicking the Honyaku menu bar icon SHALL open the Settings window directly. There is no popover and no transcript list in the menu bar; history lives in Settings > History.
- **While first run is incomplete** (a permission is missing, or models haven't been set up), clicking the icon SHALL open the first-run window instead.
- **Right-clicking** the icon SHALL show a menu with "Settings…" and "Quit Honyaku". A Control-click SHALL NOT open the menu, because holding Control is how the user dictates.
- **The icon itself** SHALL keep reflecting state: idle, recording, transcribing or processing, and error.
- **Current status** SHALL be shown at the top of the General tab: the Control keycap with "Hold Control to talk", the active speech model, whether cleanup is on, the full text of any error, and any background model download with its progress.
- **Clicking the icon SHALL NOT clear an error.** The error stays until the next dictation starts, or until the problem it reports is fixed (for example, the Control listener installs after Accessibility is granted).

#### Scenario: User clicks the menu bar icon after setup
- **WHEN** the user clicks the Honyaku icon in the menu bar
- **THEN** the Settings window opens (or comes to the front) on the last tab used, and no popover appears

#### Scenario: User right-clicks the icon
- **WHEN** the user right-clicks the Honyaku icon
- **THEN** a menu with "Settings…" and "Quit Honyaku" appears, and "Quit Honyaku" quits the app

#### Scenario: User Control-clicks the icon
- **WHEN** the user holds Control and clicks the Honyaku icon
- **THEN** the click is treated as a left click (Settings, or first run, opens), and no menu appears

#### Scenario: First run isn't finished
- **GIVEN** Accessibility isn't granted yet, or models haven't been set up
- **WHEN** the user clicks the icon
- **THEN** the first-run window opens at its first incomplete step

#### Scenario: An error occurred
- **WHEN** the last dictation failed and the user clicks the icon
- **THEN** the General tab shows the error's full text, and the error is still there after the click; the next dictation clears it

#### Scenario: A model is downloading in the background
- **WHEN** a migrated model is downloading and the user opens Settings
- **THEN** the General tab and the model's row in the Models tab show the download's progress

---

### Requirement: Settings is a single window
The system SHALL provide a single Settings window, opened by clicking the menu bar icon (or "Settings…" in its right-click menu), with these tabs:
- **General:** current status (see the menu bar icon requirement), launch at login, microphone device, permission status with "Open System Settings" for each missing permission.
- **Models:** the speech and cleanup models, each with its download state, disk space used, "Use" (only for downloaded models), "In use" for the active one, Download and Delete.
- **Dictation:** cleanup on/off, speaker labels on/off, the dictation language, and the cleanup prompt with "Reset to default", under an Advanced disclosure.
- **History:** a searchable list of transcripts. Each row SHALL have visible Copy and Delete buttons, reachable from the keyboard and named for VoiceOver, as well as Copy and Delete in its context menu. "Delete all history…" sits behind a confirmation.
- **Privacy:** the offline guarantees, and the Hugging Face access token under an Advanced disclosure. A token that fails to save SHALL show an error rather than "Saved".

There SHALL never be more than one Settings window, and never more than one first-run window.

#### Scenario: User opens Settings
- **WHEN** the user clicks the menu bar icon, or chooses "Settings…" from its right-click menu
- **THEN** the Settings window opens on the General tab, or the last tab used, and comes to the front

#### Scenario: User clicks Settings again while it's open
- **GIVEN** the Settings window is already open, possibly behind other windows
- **WHEN** the user clicks the menu bar icon again, or chooses "Settings…" from its menu
- **THEN** that same window comes to the front, and no second Settings window opens

#### Scenario: Settings is minimised
- **GIVEN** the user minimised the Settings window (or the first-run window) to the Dock
- **WHEN** the user clicks the menu bar icon
- **THEN** that same window is restored from the Dock and comes to the front, with its content as the user left it

#### Scenario: User closes Settings
- **WHEN** the user closes the Settings window and later clicks Settings again
- **THEN** a single Settings window opens

#### Scenario: User searches history
- **WHEN** the user types "invoice" into the History search field
- **THEN** only transcripts containing "invoice" (ignoring case and accents) are listed

#### Scenario: User copies a transcript with the keyboard
- **WHEN** the user tabs to a history row's Copy button and presses Space
- **THEN** that transcript is on the clipboard

---

