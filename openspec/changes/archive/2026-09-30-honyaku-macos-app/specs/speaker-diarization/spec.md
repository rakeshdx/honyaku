## ADDED Requirements

### Requirement: Speaker diarization is an opt-in feature
The system SHALL treat speaker diarization as an optional capability. It SHALL be disabled by default and toggleable in Settings. When disabled, the transcription pipeline operates without diarization and produces no speaker labels.

#### Scenario: Diarization is disabled
- **WHEN** push-to-talk completes and diarization is toggled off
- **THEN** the system transcribes and cleans up without any speaker identification step

#### Scenario: User enables diarization for the first time
- **WHEN** the user enables diarization in Settings
- **THEN** the system checks whether required SpeakerKit CoreML model files are cached; if not, it prompts to download them (~10 MB)

---

### Requirement: Recorded audio is segmented by speaker using WhisperKit SpeakerKit
The system SHALL use WhisperKit's SpeakerKit (argmaxinc/WhisperKit, MIT license) to identify speaker boundaries and associate each text segment with a speaker label (e.g., "Speaker 1", "Speaker 2"). All diarization processing SHALL run locally on the Apple Neural Engine via CoreML. No audio or speaker data SHALL be transmitted to any remote service.

#### Scenario: Two distinct speakers are present in the recording
- **WHEN** push-to-talk captures audio containing two speakers
- **THEN** the cleaned transcript is prefixed with speaker labels per segment (e.g., "[Speaker 1] Hello, how are you? [Speaker 2] I'm doing well.")

#### Scenario: Only one speaker is detected
- **WHEN** SpeakerKit identifies a single speaker throughout the recording
- **THEN** no speaker labels are prepended and the transcript is output as normal

#### Scenario: 30-second two-speaker recording is processed
- **WHEN** a 30-second audio buffer with two speakers is passed to SpeakerKit
- **THEN** the system returns labeled speaker segments within 3 seconds on M1 hardware (SpeakerKit runs at ~122× real-time on M1)

---

### Requirement: SpeakerKit CoreML models are downloaded and cached locally
The system SHALL download SpeakerKit's CoreML diarization models (~10 MB) from Hugging Face on first use and cache them at `~/Library/Application Support/Honyaku/Models/diarization/`. No download occurs unless the feature is enabled by the user.

#### Scenario: Diarization models are not yet downloaded when feature is enabled
- **WHEN** the user enables diarization and the CoreML model files are absent
- **THEN** the system prompts the user to download the models (~10 MB) before activating the feature

#### Scenario: Diarization models are already cached
- **WHEN** the user enables diarization and model files are present in local storage
- **THEN** diarization activates immediately without any network request

---

### Requirement: Speaker labels are consistent within a session
The system SHALL maintain consistent speaker label assignments within a single recording session (app launch to quit). Speaker 1 in one recording SHALL refer to the same voice as Speaker 1 in subsequent recordings within the same session, provided the voice embedding is sufficiently similar.

#### Scenario: Same person speaks in two consecutive recordings
- **WHEN** the same speaker is detected in two back-to-back push-to-talk recordings
- **THEN** the speaker is assigned the same label in both transcripts

---

### Requirement: Diarization runs after transcription and before cleanup in the pipeline
The system SHALL execute the transcription pipeline stages in this fixed order: (1) WhisperKit ASR → (2) SpeakerKit diarization (if enabled) → (3) LLM cleanup. When diarization is enabled, the cleanup LLM SHALL receive speaker-labeled text (e.g., `[Speaker 1] ... [Speaker 2] ...`) as its input. The cleanup prompt SHALL instruct the LLM to preserve `[Speaker N]` label tokens in its output unchanged.

#### Scenario: Diarization and cleanup are both enabled
- **WHEN** push-to-talk completes with two speakers detected
- **THEN** WhisperKit produces raw text → SpeakerKit adds labels → the cleanup LLM receives `[Speaker 1] ... [Speaker 2] ...` and returns cleaned text with labels intact

#### Scenario: Diarization is enabled but cleanup is disabled
- **WHEN** push-to-talk completes with diarization on and cleanup toggled off
- **THEN** WhisperKit produces raw text → SpeakerKit adds labels → labeled raw text is pasted directly without LLM processing

---

### Requirement: Speaker embeddings are held in memory only and never persisted to disk
The system SHALL store speaker embeddings exclusively in process memory for the duration of the app session. Embeddings SHALL NOT be written to any file, database, or persistent store. All embeddings SHALL be discarded when the app is quit or the session ends.

#### Scenario: App is quit normally
- **WHEN** the user quits Honyaku
- **THEN** all in-memory speaker embeddings are discarded and no embedding data remains on disk

#### Scenario: App is force-quit or crashes
- **WHEN** the app terminates unexpectedly
- **THEN** no speaker embedding data has been written to disk at any point, so no residual data persists

---

### Requirement: SpeakerKit diarization model tier is defined
The system SHALL use the following diarization model for v1:

| Model | Source | Size | License |
|---|---|---|---|
| SpeakerKit CoreML (argmaxinc/WhisperKit) | `argmaxinc/whisperkit-coreml` HF repo | ~10 MB | MIT |

There is one diarization model tier in v1. Multiple tiers are not supported in this release.

#### Scenario: User enables diarization
- **WHEN** the user enables diarization in Settings
- **THEN** the system downloads the single SpeakerKit CoreML model (~10 MB) if not already cached

---

### Requirement: No audio or speaker data is transmitted off-device
The system SHALL never transmit audio recordings, speaker embeddings, or diarization results to any remote service.

#### Scenario: Diarization is active and device has network access
- **WHEN** push-to-talk diarization runs with an active internet connection
- **THEN** the system makes no outbound network calls during the SpeakerKit inference
