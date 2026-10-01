## ADDED Requirements

### Requirement: History entries record the dictation mode and target app
Each new history entry SHALL record:
- the mode it was made in (`dictate` for plain dictation)
- the bundle identifier of the app that was in front when the text was pasted or saved

History files written before these fields existed SHALL still load, with both fields empty.

#### Scenario: New dictation is saved
- **WHEN** a plain dictation is pasted into Slack
- **THEN** its history entry records mode `dictate` and app `com.tinyspeck.slackmacgap`

#### Scenario: History from an earlier version
- **GIVEN** `history.json` was written by a version without these fields
- **WHEN** Honyaku launches
- **THEN** every earlier entry loads, with no mode and no app recorded
