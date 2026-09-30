# speech-transcription Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
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

### Requirement: A failed microphone start leaves capture reusable
If the audio engine fails to start, the system SHALL show an error and SHALL leave no audio tap installed, so the next press can try a fresh start.

#### Scenario: Microphone fails to start
- **WHEN** the user presses Control and the audio engine fails to start
- **THEN** an error is shown, the status is not recording, and no audio tap remains installed

#### Scenario: Next press after a failed start
- **GIVEN** the previous microphone start failed
- **WHEN** the user presses and holds Control again
- **THEN** the system tries a fresh start and does not crash

---

### Requirement: A microphone disconnect stops the active recording
When an audio input device disconnects while a recording is active, the system SHALL cancel that recording (stop capture, release the microphone, discard the audio) and SHALL show the disconnect message. Disconnects of devices that carry no audio SHALL be ignored.

#### Scenario: Microphone unplugged while dictating
- **WHEN** the audio input device in use disconnects while the user is holding Control
- **THEN** the recording is cancelled, the microphone is released, the disconnect message is shown, and releasing Control does not trigger transcription

#### Scenario: Next press after a disconnect
- **GIVEN** a recording was cancelled by a microphone disconnect
- **WHEN** the user presses and holds Control again
- **THEN** a new recording starts on the current default input without crashing

#### Scenario: Audio device disconnects while a dictation is being transcribed
- **WHEN** an audio input disconnects after Control was released, while the transcript is still being produced
- **THEN** the dictation finishes normally and the status is not changed to an error, so the next press records and stops as usual

#### Scenario: Non-audio device disconnects
- **WHEN** a device without audio (for example a webcam with no microphone) disconnects while the user is dictating
- **THEN** the recording continues unaffected and no error is shown

---

### Requirement: Short utterances are transcribed
Every recording that passes the 300 ms minimum hold SHALL be sent through speech decoding, however short the captured audio is. The system SHALL NOT drop a clip because it is shorter than the speech engine's end-of-clip trim window. A clip that decodes to no speech SHALL still be discarded silently, as today.

#### Scenario: One-word dictation
- **WHEN** the user holds Control for about one second and says a single word, so the captured audio is 1 second or shorter
- **THEN** the audio is decoded and the transcribed word is pasted into the active application

#### Scenario: Short hold with no speech
- **WHEN** the user holds Control for about one second without speaking
- **THEN** no text is pasted and no error is shown

---

### Requirement: Non-speech annotations are never pasted
Before the transcript is used, the system SHALL remove Whisper's non-speech annotations: any text in square brackets (for example `[BLANK_AUDIO]`, `[MUSIC]`), and any segment made up entirely of a parenthesised annotation (for example `(silence)`). If nothing is left, the recording SHALL be treated as silence: no text is pasted, no history entry is added, and no error is shown.

#### Scenario: Text in scripts without spaces keeps its spacing
- **WHEN** a multilingual model transcribes two Japanese sentences as separate segments
- **THEN** the pasted text has no space inserted between them

#### Scenario: Silent hold
- **WHEN** the user holds Control for about 2 seconds without speaking and Whisper returns `[BLANK_AUDIO]`
- **THEN** nothing is pasted and no error is shown

#### Scenario: Annotation around real speech
- **WHEN** Whisper returns `[MUSIC] send the report`
- **THEN** only `send the report` is pasted

---

### Requirement: The first press starts the microphone as fast as later presses
The system SHALL prepare the audio engine's input ahead of the first press, and again after each recording ends, without starting audio input. The microphone SHALL only be active while Control is held, so the macOS microphone indicator stays off while idle.

#### Scenario: First press after launch
- **WHEN** the user makes their first dictation after launch
- **THEN** no more audio is lost at the start of the recording than on later presses

#### Scenario: Idle app does not use the microphone
- **WHEN** Honyaku has launched and the user is not holding Control
- **THEN** the macOS microphone indicator is not shown for Honyaku

---

### Requirement: Models are loaded at launch
Once setup is complete, the system SHALL load the selected speech model and, if cleanup is enabled, the selected cleanup model in the background at launch, so the first dictation is about as fast as later ones. Warm-up SHALL only load models already on disk, including the speech model's tokenizer. It SHALL NOT contact the network: if the local copy fails to load, warm-up gives up, and the next dictation may fetch the model. A dictation made while the models are still loading SHALL wait for that load rather than start a second one.

#### Scenario: First dictation after launch
- **GIVEN** Honyaku launched a few seconds ago with setup complete
- **WHEN** the user makes their first dictation
- **THEN** the time from release to paste is about the same as for later dictations

#### Scenario: Dictation during warm-up
- **WHEN** the user dictates while the models are still loading at launch
- **THEN** the dictation waits for the in-progress load, and each model is loaded only once

#### Scenario: Speech model not on disk at launch
- **GIVEN** the selected speech model hasn't been downloaded
- **WHEN** Honyaku launches
- **THEN** warm-up skips it and nothing is downloaded until the user's first dictation needs it

