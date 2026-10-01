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
