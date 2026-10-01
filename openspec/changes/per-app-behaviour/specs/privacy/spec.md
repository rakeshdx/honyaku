## ADDED Requirements

### Requirement: Honyaku never pastes into a password field
Right before every paste, the system SHALL check the focused text field and the system secure-input state, and SHALL:
- **block** the paste when the focused element's subrole is `AXSecureTextField`;
- **block** the paste when secure input is on and owned by the app that would receive the text, unless that app is in the Terminals category;
- **warn and paste** when secure input is on but owned by another app, by an unknown app, or by a terminal that is in front (for example with Secure Keyboard Entry on);
- **paste** when the field's type can't be read (fail open).

A blocked transcript SHALL NOT be written to the pasteboard, pasted or saved to history. The status SHALL read "Not pasted: a password field is focused". The status SHALL NOT include the transcript, and the transcript SHALL NOT be logged.

A warning SHALL show "Pasted. Note: <App> has secure input on" without the error colour.

The check SHALL run before the "Honyaku was in front" routing, so text dictated into Honyaku's own token field is blocked rather than saved.

The system SHALL NOT set `AXManualAccessibility` or any other attribute on other apps to read their fields. The check SHALL time out quickly (about 0.25 s) rather than delay the paste when an app doesn't respond.

#### Scenario: A browser password field is focused
- **GIVEN** a password field on a web page in Safari or Chrome has focus
- **WHEN** a dictation finishes
- **THEN** nothing is pasted, the clipboard is untouched, no history entry is added, and the status reads "Not pasted: a password field is focused"

#### Scenario: The receiving app owns secure input
- **GIVEN** a native app that is not a terminal is in front and has turned on secure input for its password field
- **WHEN** a dictation finishes
- **THEN** the paste is blocked and nothing is saved

#### Scenario: Another app owns secure input
- **GIVEN** a password manager left secure input on while the user dictates into TextEdit
- **WHEN** a dictation finishes
- **THEN** the text is pasted into TextEdit and the status briefly reads "Pasted. Note: <password manager> has secure input on"

#### Scenario: Terminal with Secure Keyboard Entry
- **GIVEN** Terminal is in front with Secure Keyboard Entry turned on
- **WHEN** a dictation finishes
- **THEN** the text is pasted with the secure-input notice, because a terminal's secure input doesn't indicate a password field

#### Scenario: The field type can't be read
- **GIVEN** Slack is in front and exposes no focused field to accessibility
- **WHEN** a dictation finishes
- **THEN** the text is pasted, and Honyaku has not changed any accessibility setting of Slack

#### Scenario: Honyaku's own token field is focused
- **GIVEN** the Hugging Face token field in Settings has focus
- **WHEN** a dictation finishes
- **THEN** nothing is pasted or saved, and the status reads "Not pasted: a password field is focused"
