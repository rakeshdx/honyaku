## ADDED Requirements

### Requirement: Audio is transcribed locally using a Whisper model
The system SHALL transcribe captured audio using a WhisperKit-based pipeline running entirely on the local device. No audio data SHALL be transmitted to any remote service.

#### Scenario: Transcription completes successfully
- **WHEN** the user releases the Control key and audio has been captured
- **THEN** the system passes the buffered audio to WhisperKit and produces a raw transcript string within a time proportional to audio length and selected model size

#### Scenario: Transcription fails due to inaudible audio
- **WHEN** WhisperKit returns an empty or silence-only transcript
- **THEN** the system discards the result silently and resets to the idle state

---

### Requirement: Multiple Whisper model tiers are supported
The system SHALL support at minimum the following model tiers selectable by the user:

| Tier | Model | Size | Notes |
|---|---|---|---|
| Fast | Whisper tiny.en | ~75 MB | English only |
| Balanced | Whisper small.en | ~466 MB | English only, default |
| Multilingual | Whisper small (multilingual) | ~466 MB | 99 languages |
| High Quality | Parakeet v3 | ~1.4 GB | 25 languages via FluidAudio |

#### Scenario: User has selected Balanced tier
- **WHEN** push-to-talk recording completes
- **THEN** the system uses the `whisper-small.en` CoreML model for transcription

#### Scenario: Model files are not yet downloaded
- **WHEN** the selected speech model is not present in local model storage
- **THEN** the system displays a prompt to download the model and does not attempt transcription

---

### Requirement: Temporary audio file is deleted immediately after use
The system SHALL write captured audio to a temporary WAV file in `NSTemporaryDirectory()` solely for the purpose of passing it to WhisperKit. The temporary file SHALL be deleted immediately upon WhisperKit completing ingestion, whether transcription succeeds or fails. On app launch, the system SHALL delete any Honyaku temporary audio files left in `NSTemporaryDirectory()`, treating them as crash artifacts.

#### Scenario: Transcription completes successfully
- **WHEN** WhisperKit returns a transcript from the temporary WAV file
- **THEN** the temporary WAV file is deleted before the cleanup step begins

#### Scenario: WhisperKit throws an error during transcription
- **WHEN** WhisperKit fails to process the temporary WAV file
- **THEN** the temporary WAV file is deleted before the error state is surfaced to the user

#### Scenario: App launches after a crash that left temp files
- **WHEN** the app starts and finds temporary audio files from a previous session in `NSTemporaryDirectory()`
- **THEN** all such files are deleted during app initialization before any pipeline activity begins

---

### Requirement: Microphone access is held only during active recording
The system SHALL install the `AVAudioInputNode` tap only when a recording is triggered and SHALL tear it down as soon as audio capture ends. The microphone access session SHALL NOT be held open between recordings.

#### Scenario: User releases Control key ending a recording
- **WHEN** the Control key is released and audio capture stops
- **THEN** the `AVAudioInputNode` tap is removed and the microphone session is ended

#### Scenario: App is idle between recordings
- **WHEN** no push-to-talk recording is in progress
- **THEN** no active microphone tap exists and no audio is being captured

---

### Requirement: Raw transcript is available before cleanup
The system SHALL make the raw (pre-cleanup) transcript available as an intermediate result so it can be displayed or stored even if the cleanup LLM step fails.

#### Scenario: LLM cleanup step times out
- **WHEN** the cleanup LLM does not return a result within 15 seconds
- **THEN** the system falls back to pasting the raw WhisperKit transcript and logs the timeout

---

### Requirement: Microphone selection is respected
The system SHALL use the microphone device selected in Settings for all audio capture. If the selected device becomes unavailable, the system SHALL fall back to the system default microphone and notify the user.

#### Scenario: User selects a specific USB microphone in Settings
- **WHEN** push-to-talk is triggered
- **THEN** the system captures audio from the USB microphone, not the built-in mic

#### Scenario: Selected microphone is disconnected mid-session
- **WHEN** the selected microphone is unplugged while the app is running
- **THEN** the system switches to the system default microphone and shows a notification in the menu bar popover
