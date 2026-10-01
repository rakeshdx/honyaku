## ADDED Requirements

### Requirement: History entries record the dictation mode and target app
Each new history entry SHALL record:
- the mode it was made in (`dictate` for plain dictation)
- the bundle identifier of the app the text went to: the app in front at paste time, or none when Honyaku itself was in front

History files written before these fields existed SHALL still load, with both fields empty.

#### Scenario: New dictation is saved
- **WHEN** a plain dictation is pasted into Slack
- **THEN** its history entry records mode `dictate` and app `com.tinyspeck.slackmacgap`

#### Scenario: Honyaku was in front
- **WHEN** a dictation finishes while a Honyaku window is in front, so it is saved to History without pasting
- **THEN** its history entry records mode `dictate` and no app

#### Scenario: History from an earlier version
- **GIVEN** `history.json` was written by a version without these fields
- **WHEN** Honyaku launches
- **THEN** every earlier entry loads, with no mode and no app recorded
