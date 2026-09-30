## MODIFIED Requirements

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
- **WHEN** the selected speech model is not in local model storage
- **THEN** the system fetches it on first use (see privacy), or the user can download it in Settings, before transcribing

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

## ADDED Requirements

### Requirement: Silent recordings are discarded before transcription
Before transcribing, the system SHALL measure the recording's loudness. If no 100 ms window rises above −45 dBFS RMS, the recording SHALL be treated as silence and discarded silently, without calling the speech model. That stops models inventing text such as "Thank you." for silence.

#### Scenario: Silent hold with Whisper
- **WHEN** the user holds Control without speaking, with Whisper large-v3-turbo selected
- **THEN** nothing is pasted, and the speech model is not run

#### Scenario: Quiet speech
- **WHEN** the user speaks quietly but audibly
- **THEN** the recording is transcribed as usual
