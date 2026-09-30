## MODIFIED Requirements

### Requirement: Cleaned text is pasted into the active application
The system SHALL write the cleaned (or raw, if cleanup is disabled) transcript to the system pasteboard and simulate a ⌘V keystroke to paste it into the frontmost application. The user's prior pasteboard contents SHALL be restored after the paste.

If Honyaku itself is the frontmost app when the text is ready (for example, the user brought Settings forward while the dictation was being transcribed), the system SHALL NOT send ⌘V. It SHALL save the transcript to history and show "Saved to History — Honyaku was in front", and SHALL leave the clipboard untouched.

#### Scenario: Successful paste after cleanup
- **WHEN** cleanup completes and the user has a text field focused
- **THEN** the cleaned text appears at the cursor position in the active application and the user's prior clipboard content is restored

#### Scenario: No active text field to paste into
- **WHEN** cleanup completes but no editable field is focused
- **THEN** the text is written to the pasteboard and a notification indicates the text is ready to paste manually

#### Scenario: Honyaku is in front when the text is ready
- **GIVEN** the user started a dictation in another app, then clicked the menu bar icon so Settings came to the front
- **WHEN** the transcript is ready
- **THEN** no ⌘V is sent, the transcript is added to history, the status reads "Saved to History — Honyaku was in front", and the clipboard is unchanged

#### Scenario: Paste simulation fails or pipeline is aborted
- **WHEN** the paste simulation fails or the transcription pipeline is cancelled before completion
- **THEN** any transcript text written to the pasteboard is cleared within 5 seconds and the prior clipboard contents are restored, and the error is shown on the menu bar icon and in Settings > General
