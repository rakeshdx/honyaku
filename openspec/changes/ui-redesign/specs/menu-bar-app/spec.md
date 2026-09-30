## MODIFIED Requirements

### Requirement: Clicking the menu bar icon opens a popover with transcript history and status
The system SHALL display a popover with:
- A header built around the Control keycap. The keycap SHALL show the current state: idle, recording (pressed, with live input level), transcribing or processing, or error (with the full error text).
- A line naming the active speech model and whether cleanup is on.
- The most recent transcripts, newest first. Transcript text is set in a serif face, with a relative time ("2m ago").
- Settings and Quit.

Each transcript row SHALL offer Copy and Delete on hover and in a context menu. The popover SHALL NOT offer a one-click "delete all history".

#### Scenario: User clicks the menu bar icon while idle
- **WHEN** the user single-clicks the Honyaku icon in the menu bar
- **THEN** the popover shows "Hold Control to talk" beside the keycap, the active model line, the recent transcripts, and Settings and Quit

#### Scenario: Transcript history is empty
- **WHEN** the popover opens and there are no transcripts
- **THEN** it shows the keycap header and an empty state that explains how to dictate

#### Scenario: An error occurred
- **WHEN** the last dictation failed
- **THEN** the header shows the error's full text, and the next successful dictation clears it

#### Scenario: User copies or deletes one transcript
- **WHEN** the user chooses Copy or Delete on a transcript row
- **THEN** that transcript is copied to the clipboard, or removed from history, and no other transcript is affected

---

### Requirement: Settings panel is accessible from the popover
The system SHALL provide a native macOS Settings window, opened from the popover's Settings button or with ⌘, while Honyaku is frontmost, with these tabs:
- **General:** launch at login, microphone device, permission status with a way to fix each missing permission.
- **Models:** the speech and cleanup models, each with its download state, disk space used, "Use" (only for downloaded models), Download and Delete.
- **Dictation:** cleanup on/off, speaker labels on/off, and the cleanup prompt with "Reset to default", under an Advanced disclosure.
- **History:** a searchable list of transcripts with copy, and "Delete all history…" behind a confirmation.
- **Privacy:** the offline guarantees, and the Hugging Face access token under an Advanced disclosure.

#### Scenario: User opens Settings
- **WHEN** the user clicks Settings in the popover
- **THEN** the Settings window opens on the General tab, or the last tab used, and comes to the front

#### Scenario: User clicks Settings again while it's open
- **GIVEN** the Settings window is already open, possibly behind other windows
- **WHEN** the user clicks Settings in the popover again, or presses ⌘,
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
The system SHALL persist the transcript history to disk at `~/Library/Application Support/Honyaku/history.json`. The user SHALL be able to delete a single transcript from the popover or Settings, and delete all history from Settings after confirming. History SHALL never be transmitted off the device.

#### Scenario: User deletes all history
- **WHEN** the user chooses "Delete all history…" in Settings and confirms
- **THEN** all transcript records are deleted from disk and the list empties

#### Scenario: User cancels deleting all history
- **WHEN** the user chooses "Delete all history…" and then cancels
- **THEN** no transcript is deleted

#### Scenario: App restarts after transcripts were produced
- **WHEN** the app is relaunched
- **THEN** the transcript history from the previous session is restored from disk
