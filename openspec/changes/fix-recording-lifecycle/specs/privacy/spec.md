## ADDED Requirements

### Requirement: A downloaded speech model loads without network access
When the selected speech model is already on disk, the system SHALL load it from the local folder and SHALL NOT contact any remote host, including metadata checks. Only when the model is missing SHALL the system fetch it from Hugging Face.

#### Scenario: First dictation after launch with the model on disk
- **GIVEN** the selected Whisper model is already downloaded
- **WHEN** the user makes their first dictation after launch
- **THEN** the model loads from the local folder and no request is sent to huggingface.co

#### Scenario: Dictation works offline
- **GIVEN** the selected Whisper model is already downloaded and the Mac has no network connection
- **WHEN** the user dictates
- **THEN** the transcript is produced and pasted as usual

#### Scenario: Model not on disk
- **GIVEN** the selected Whisper model has not been downloaded
- **WHEN** the model is needed for transcription
- **THEN** the system fetches it from Hugging Face and then transcribes
