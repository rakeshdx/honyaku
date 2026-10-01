## ADDED Requirements

### Requirement: The dictation pipeline is unit-testable with fake services
The dictation pipeline SHALL receive its services through protocols:
- audio capture
- speech transcription
- diarization
- cleanup
- paste
- model availability
- target-app resolution

Production SHALL pass the real services by default. Unit tests SHALL drive a whole dictation, from recording start to paste or save, with fake services. Pipeline unit tests SHALL NOT use, read or change:
- the user's saved settings (`UserDefaults.standard`)
- the user's history, models or Application Support folder
- the system pasteboard
- the microphone
- the network

#### Scenario: Plain dictation pastes and saves
- **GIVEN** fake services where transcription returns "hello world" and cleanup returns "Hello world."
- **WHEN** a unit test starts and stops a recording
- **THEN** the fake paste service receives "Hello world." and one history entry is saved with that text

#### Scenario: Silence never reaches the speech model
- **GIVEN** the fake microphone returns silent samples
- **WHEN** the recording stops
- **THEN** transcription is not called, nothing is pasted or saved, and the status returns to idle

#### Scenario: An empty transcript is discarded
- **GIVEN** transcription returns only whitespace
- **WHEN** the recording stops
- **THEN** cleanup is not called, nothing is pasted or saved, and the status returns to idle

#### Scenario: A failed cleanup falls back to the transcript
- **GIVEN** cleanup is on and the fake cleanup service throws
- **WHEN** the recording stops
- **THEN** the transcript, minus English fillers, is pasted

#### Scenario: Honyaku in front saves without pasting
- **GIVEN** the fake target resolver reports Honyaku as the frontmost app
- **WHEN** a dictation finishes
- **THEN** nothing is pasted, the entry is saved to history, and the status shows "Saved to History — Honyaku was in front"

#### Scenario: Pipeline stages run in order
- **GIVEN** a context preparer, an after-transcription stage and a final stage are registered
- **WHEN** a dictation runs
- **THEN** the preparer runs before transcription, the after-transcription stage's output is what cleanup receives, and the final stage's output is what is pasted

### Requirement: Tests never touch the user's real data
No test — unit, integration or UI — SHALL write, change or delete:
- the user's history (`~/Library/Application Support/Honyaku/history.json`)
- the user's saved settings (`UserDefaults.standard` for Honyaku)
- the system clipboard
- anything in the user's models folder

Tests SHALL use temporary folders, private `UserDefaults` suites, uniquely named pasteboards, in-memory stores and fakes. Integration tests MAY read installed models.

When the app hosts the unit tests, or is launched by the UI tests, it SHALL keep its history in memory and its settings in a separate suite. It SHALL NOT clean up the temporary audio folder, which the user's running copy may be using.

#### Scenario: Running the unit tests leaves history alone
- **GIVEN** the user has dictation history
- **WHEN** the unit tests run
- **THEN** `history.json` has the same size and modification date afterwards

#### Scenario: Paste tests don't change the clipboard
- **GIVEN** the user has copied some text
- **WHEN** the paste service tests run
- **THEN** the user's clipboard still holds that text

#### Scenario: The language benchmark leaves the setting alone
- **WHEN** the speech benchmark transcribes with Italian chosen
- **THEN** the language is passed to the speech model for that call, and the user's dictation-language setting is never written
