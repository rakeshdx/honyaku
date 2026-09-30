# speech-transcription Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: Audio is transcribed locally using a Whisper model
The system SHALL transcribe captured audio on the local device using the selected speech engine: NVIDIA Parakeet (via FluidAudio) or Whisper (via WhisperKit). No audio data SHALL be transmitted to any remote service. Both engines SHALL produce the same result shape: text, language, duration and timed segments. That lets speaker labels, annotation removal and cleanup work unchanged.

#### Scenario: Transcription completes successfully
- **WHEN** the user releases the Control key and audio has been captured
- **THEN** the system passes the audio to the selected engine and produces a raw transcript, in a time proportional to audio length and model size

#### Scenario: Transcription fails due to inaudible audio
- **WHEN** the engine returns an empty or silence-only transcript
- **THEN** the system discards the result silently and resets to the idle state

#### Scenario: Speaker labels with Parakeet
- **WHEN** speaker labels are on and Parakeet transcribes a two-speaker recording
- **THEN** the transcript is split into speaker-labelled blocks, as with Whisper

---

### Requirement: Multiple Whisper model tiers are supported
The system SHALL offer the following speech models:

| Tier | Model | Size | Notes |
|---|---|---|---|
| Recommended | Parakeet TDT 0.6B v2 (FluidAudio) | ~0.6 GB | English, with punctuation; default |
| Multilingual | Whisper large-v3-turbo (`openai_whisper-large-v3-v20240930_626MB`) | ~627 MB | 99 languages |

#### Scenario: User has the recommended model selected
- **WHEN** push-to-talk recording completes
- **THEN** the system transcribes with Parakeet TDT 0.6B v2

#### Scenario: User has the multilingual model selected
- **WHEN** the user dictates in French
- **THEN** Whisper large-v3-turbo transcribes it in French

#### Scenario: Model files are not yet downloaded
- **WHEN** the selected speech model is not in local model storage and the user dictates
- **THEN** the system starts downloading it in the background and the dictation returns straight away with a message naming the model and its progress; dictations work once it's installed (the user can also download it in Settings)

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
- **THEN** the system switches to the system default microphone, and says so on the menu bar icon, in the recording capsule if it's showing, and in Settings > General

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
Before the transcript is used, the system SHALL remove Whisper's non-speech annotations: any text in square brackets (for example `[BLANK_AUDIO]`, `[MUSIC]`), and any segment made up entirely of a parenthesised annotation (for example `(silence)`) or an asterisk-wrapped sound description (for example `*thud*`). If nothing is left, the recording SHALL be treated as silence: no text is pasted, no history entry is added, and no error is shown.

#### Scenario: Text in scripts without spaces keeps its spacing
- **WHEN** a multilingual model transcribes two Japanese sentences as separate segments
- **THEN** the pasted text has no space inserted between them

#### Scenario: Silent hold
- **WHEN** the user holds Control for about 2 seconds without speaking and Whisper returns `[BLANK_AUDIO]`
- **THEN** nothing is pasted and no error is shown

#### Scenario: Annotation around real speech
- **WHEN** Whisper returns `[MUSIC] send the report`
- **THEN** only `send the report` is pasted

#### Scenario: Sound description in asterisks
- **WHEN** Whisper returns `*thud*` for a dictation
- **THEN** nothing is pasted and no error is shown

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
Once setup is complete, the system SHALL load the selected speech model (Parakeet or Whisper) and, if cleanup is enabled, the selected cleanup model in the background at launch, so the first dictation is about as fast as later ones. Warm-up SHALL only load models already fully on disk, including any tokenizer or vocabulary files the engine needs. It SHALL NOT contact the network: if the local copy fails to load, warm-up gives up, and the next dictation may fetch the model. A dictation made while a model is still loading SHALL wait for that load rather than start a second one.

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

---

### Requirement: Silent recordings are discarded before transcription
Before transcribing, the system SHALL measure the recording's loudness. If no 100 ms window rises above −45 dBFS RMS, the recording SHALL be treated as silence and discarded silently, without calling the speech model. That stops models inventing text such as "Thank you." for silence.

#### Scenario: Silent hold with Whisper
- **WHEN** the user holds Control without speaking, with Whisper large-v3-turbo selected
- **THEN** nothing is pasted, and the speech model is not run

#### Scenario: Quiet speech
- **WHEN** the user speaks quietly but audibly
- **THEN** the recording is transcribed as usual

---

### Requirement: Dictation language can be set for the multilingual model
Settings SHALL offer a dictation language for the multilingual speech model: "Auto-detect" (the default), or any language the model supports, listed by name. With a language chosen, the system SHALL tell the model that language, and SHALL NOT detect or translate, so short phrases aren't mistaken for another language. With Auto-detect, the model detects the language for each dictation and transcribes it in that language. The setting SHALL NOT affect English-only models, and Settings SHALL say so while an English-only model is selected. It SHALL apply to the next dictation, without relaunching.

#### Scenario: Italian chosen
- **GIVEN** the multilingual model is selected and the dictation language is Italian
- **WHEN** the user says "Dov'è la stazione?"
- **THEN** "Dov'è la stazione?" is pasted in Italian, not an English translation

#### Scenario: Auto-detect
- **GIVEN** the dictation language is Auto-detect
- **WHEN** the user dictates a Japanese sentence
- **THEN** it is transcribed in Japanese

#### Scenario: English-only model selected
- **GIVEN** Parakeet is selected
- **WHEN** the user opens the dictation language setting
- **THEN** Settings explains that the setting applies to the multilingual model only, and Parakeet keeps transcribing English

