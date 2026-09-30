## MODIFIED Requirements

### Requirement: A downloaded speech model loads without network access
When the selected speech model (Parakeet or Whisper) is already on disk, the system SHALL load it from the local folder and SHALL NOT contact any remote host, including metadata checks. Only when the model is missing, or the local copy fails to load, SHALL the system fetch it from Hugging Face. Launch warm-up SHALL never fetch; a download of a model that a migration selected is a separate, visible download started at launch (see model-management). A local load failure SHALL be logged, without any transcript data.

#### Scenario: First dictation after launch with the model on disk
- **GIVEN** the selected speech model is already downloaded
- **WHEN** the user makes their first dictation after launch
- **THEN** the model loads from the local folder and no request is sent to huggingface.co

#### Scenario: Dictation works offline
- **GIVEN** the selected speech model is already downloaded and the Mac has no network connection
- **WHEN** the user dictates
- **THEN** the transcript is produced and pasted as usual

#### Scenario: Model not on disk
- **GIVEN** the selected speech model has not been downloaded
- **WHEN** the model is needed for transcription
- **THEN** the system fetches it from Hugging Face in the background, showing progress, and transcribes once it is installed

#### Scenario: Local copy fails to load
- **GIVEN** the selected speech model's files are present but won't load
- **WHEN** a dictation needs it
- **THEN** the system logs the error type and downloads the model again
