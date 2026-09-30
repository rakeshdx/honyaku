# testing Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: Core services are covered by unit tests using mocked dependencies
The system's service layer SHALL be designed behind Swift protocols so that unit tests can substitute mock implementations for WhisperKit, LLM.swift, SpeakerKit, AVAudioEngine, and URLSession. Unit tests SHALL run without any downloaded models, without microphone access, and without network access. Unit tests SHALL complete in under 30 seconds on M1 hardware.

#### Scenario: Unit tests run with no models downloaded
- **WHEN** `xcodebuild test -scheme HonyakuTests` is run on a machine with no cached models
- **THEN** all unit tests pass without attempting any model load or network request

#### Scenario: ModelDownloader handles a simulated checksum mismatch
- **WHEN** a unit test injects a mock URLSession that returns a file whose SHA-256 does not match the registry entry
- **THEN** `ModelDownloader` deletes the file and returns a `.checksumMismatch` error

#### Scenario: PasteService restores prior pasteboard contents on failure
- **WHEN** a unit test triggers a paste failure via a mock CGEvent
- **THEN** `PasteService` restores the original pasteboard contents and clears the transcript text within 5 seconds

#### Scenario: Pipeline ordering is enforced
- **WHEN** a unit test injects mock ASR output and mock diarization segments and runs the pipeline with diarization enabled
- **THEN** the text passed to `CleanupService` contains `[Speaker N]` label tokens in the correct positions

#### Scenario: HotkeyService ignores Control keydown while pipeline is busy
- **WHEN** a unit test sets `AppState.status` to `.processing` and fires a mock Control keydown event
- **THEN** `HotkeyService` does not call `AudioCaptureService.startCapture()`

---

### Requirement: Integration tests verify real model inference with audio fixtures
A separate `HonyakuIntegrationTests` target SHALL contain tests that run the real WhisperKit, LLM.swift, and SpeakerKit pipelines against a set of pre-recorded audio fixture files. Integration tests SHALL be gated behind a `INTEGRATION_TESTS=1` environment variable so they do not run in standard CI by default. Required audio fixtures:

| Fixture | Duration | Purpose |
|---|---|---|
| `silence.wav` | 3s | Verify empty-result discard path |
| `filler_heavy.wav` | 20s | Verify cleanup removes "um", "uh", "like", "you know" |
| `clean_monologue.wav` | 20s | Verify cleanup LLM does not corrupt already-clean text |
| `two_speakers.wav` | 30s | Verify diarization labels ≥2 distinct speakers |
| `single_speaker.wav` | 30s | Verify diarization produces no labels for one speaker |

#### Scenario: WhisperKit transcribes filler-heavy fixture
- **WHEN** `filler_heavy.wav` is passed to `TranscriptionService` with the Balanced model
- **THEN** the raw transcript is non-empty and contains at least one filler word

#### Scenario: Cleanup LLM removes fillers from filler-heavy fixture
- **WHEN** `filler_heavy.wav` is transcribed and the result passed to `CleanupService`
- **THEN** the cleaned transcript contains no instances of "um", "uh", "like you know", or "you know"

#### Scenario: SpeakerKit labels two speakers in two-speaker fixture
- **WHEN** `two_speakers.wav` is passed to `DiarizationService`
- **THEN** the output contains segments attributed to at least 2 distinct speaker IDs

#### Scenario: Silence fixture produces no transcript and no paste
- **WHEN** `silence.wav` is passed through the full pipeline
- **THEN** no text is written to the pasteboard and the app returns to idle state

---

### Requirement: Temporary audio files are verified to be cleaned up
A test SHALL verify that no temporary audio files from Honyaku remain in `NSTemporaryDirectory()` after the pipeline completes, and that any pre-existing Honyaku temp files are removed on app launch.

#### Scenario: Temp file is deleted after successful transcription
- **WHEN** an integration test runs the full transcription pipeline with a valid audio fixture
- **THEN** after `TranscriptionService` returns, no WAV file with a Honyaku prefix exists in `NSTemporaryDirectory()`

#### Scenario: Crash-leftover temp files are cleaned on relaunch
- **WHEN** a unit test pre-creates a fake Honyaku temp WAV file in `NSTemporaryDirectory()` and then calls the app's launch-time cleanup routine
- **THEN** the fake file is deleted

---

### Requirement: File permissions and backup exclusion are verified by tests
A test SHALL assert that `history.json` is created with Unix permissions 600 and that `URLResourceValues.isExcludedFromBackup` is `true` for the Application Support directory.

#### Scenario: history.json is written for the first time
- **WHEN** a unit test calls `TranscriptStore.save()` with a mock transcript on a clean directory
- **THEN** the created file has permissions `0o600` and `isExcludedFromBackup == true`

---

### Requirement: Network isolation is verified with a proxy-based test
Before each release, a manual network audit SHALL be performed by running the app under mitmproxy or Proxyman while executing at least 10 push-to-talk recordings after setup. The audit SHALL confirm zero outbound network requests are made during normal operation. Results SHALL be documented in the release checklist.

#### Scenario: Manual network audit passes
- **WHEN** the app is run under mitmproxy with all models already downloaded and 10 recordings are performed
- **THEN** mitmproxy logs zero outbound HTTP/HTTPS requests attributable to Honyaku

---

### Requirement: UI interactions are covered by XCUITests
The following UI flows SHALL be covered by `XCUITest`, in the `HonyakuUITests` scheme:
- The menu bar icon exists; a test SHALL fail, not skip, when it can't be found
- Clicking the icon opens Settings
- Clicking the icon twice leaves exactly one Settings window
- Right-clicking the icon shows "Settings…" and "Quit Honyaku"
- "Delete all history…" asks for confirmation before deleting
- Launch at Login toggle state persists across re-opens of Settings
- First run shows when Accessibility permission is missing (mocked permission state)

UI tests SHALL set up the state they need through a launch argument that only Debug builds honour, held in memory for that launch. They SHALL NOT depend on, or change, the user's saved settings, history or models, and SHALL NOT start the Control listener or load models.

#### Scenario: Menu bar icon opens Settings
- **WHEN** an XCUITest launches Honyaku with setup marked complete for the test and clicks the menu bar icon
- **THEN** the Settings window appears with its toolbar tabs

#### Scenario: One Settings window
- **WHEN** an XCUITest clicks the menu bar icon twice
- **THEN** exactly one Settings window exists

#### Scenario: The icon is missing
- **WHEN** an XCUITest can't find the Honyaku menu bar icon
- **THEN** the test fails

#### Scenario: Delete all history confirmation
- **WHEN** an XCUITest clicks "Delete all history…" in Settings > History
- **THEN** a confirmation dialog appears; confirming empties the history list

### Requirement: Test targets have the required entitlements and permissions
The `HonyakuTests` and `HonyakuIntegrationTests` targets SHALL declare `NSMicrophoneUsageDescription` in their Info.plist. The Accessibility permission SHALL be granted to the Xcode test runner binary in System Settings before running hotkey or CGEventTap tests. These prerequisites SHALL be documented in the project README.

#### Scenario: Hotkey unit tests run without Accessibility permission
- **WHEN** Accessibility permission has not been granted to the test runner
- **THEN** hotkey tests that require it are skipped with a `XCTSkip` message, not failed, so CI does not break on permission-constrained machines

