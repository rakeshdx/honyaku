## 1. Project Bootstrap

- [x] 1.1 Create Xcode project: macOS App, SwiftUI lifecycle, bundle ID `com.honyaku.app`, deployment target macOS 14.0
- [x] 1.2 Add Swift Package dependencies: WhisperKit (includes SpeakerKit), mlx-swift-lm (MLXLLM/MLXLMCommon)
- [x] 1.3 Configure entitlements: `com.apple.security.microphone`, `com.apple.security.accessibility` (non-sandboxed), `com.apple.security.network.client` (model downloads only)
- [x] 1.4 Set `LSUIElement = YES` in Info.plist to suppress Dock icon
- [x] 1.5 Configure `SMAppService` launch-at-login registration on first run

## 2. App Entry Point & Menu Bar Shell

- [x] 2.1 Implement `@main` `HonyakuApp` with `MenuBarExtra` scene (no window group)
- [x] 2.2 Create `AppState` observable class to hold global status (idle, recording, processing, error)
- [x] 2.3 Build menu bar icon view that switches symbol/animation based on `AppState.status`
- [x] 2.4 Build `MenuBarPopoverView` shell: transcript history list, status label, Settings button
- [x] 2.5 Implement `TranscriptStore` (persists to `~/Library/Application Support/Honyaku/history.json`)

## 3. Permission Onboarding

- [x] 3.1 Create `PermissionManager` that checks and requests Microphone and Accessibility permission status
- [x] 3.2 Build `OnboardingView` with two-step flow: Microphone → Accessibility, each with deep-link to correct System Settings pane
- [x] 3.3 Show onboarding on first launch (or if either permission is missing) before activating any features
- [x] 3.4 Register `CGEventTap` permission check; surface status badge in Settings if revoked post-launch

## 4. Audio Capture (CoreAudio)

- [x] 4.1 Implement `AudioCaptureService` using `AVAudioEngine` + `AVAudioInputNode` tap
- [x] 4.2 Buffer raw PCM audio in memory (ring buffer) while Control key is held
- [x] 4.3 On Control key release, flush buffer to a temporary WAV file at `NSTemporaryDirectory()`
- [x] 4.4 Expose microphone device selection: enumerate `AVCaptureDevice.audioDevices`, persist selection to `UserDefaults`
- [x] 4.5 Handle microphone disconnect: fall back to system default, post notification to popover

## 5. Global Push-to-Talk Hotkey

- [x] 5.1 Implement `HotkeyService` that registers a `CGEventTap` for `.keyDown` / `.keyUp` on `kVK_Control`
- [x] 5.2 Filter out Ctrl+key chords (e.g., Ctrl+C): only trigger recording on bare Control keydown without sibling key; pass all other events through immediately without retaining payload data
- [x] 5.3 Enforce 300ms minimum hold duration before committing the recording
- [x] 5.4 On keydown → start `AudioCaptureService`; on keyup → stop capture and signal transcription pipeline
- [x] 5.5 Gate `HotkeyService` activation behind successful Accessibility permission grant
- [x] 5.6 Implement pipeline-busy guard: if `AppState.status` is not `.idle`, ignore Control keydown and show busy indicator in menu bar icon

## 6. Model Management

- [x] 6.1 Define `ModelRegistry`: catalog of speech models, cleanup models, and diarization models (name, HF repo path, size, tier, SHA-256 checksum)
- [x] 6.2 Implement `ModelDownloader` using `URLSession` with background download task, byte-range resumption, progress publisher, SHA-256 integrity verification on completion, and disk-space pre-check
- [x] 6.3 Implement `ModelStore`: check local presence at `~/Library/Application Support/Honyaku/Models/`, expose `isDownloaded`, `delete()`, `sizeOnDisk`; mark all model directories with `isExcludedFromBackup = true`
- [x] 6.4 Build first-run `SetupWizardView`: speech model picker → cleanup model picker → download progress → completion; handle network-unavailable state with retry prompt; handle wizard cancellation by persisting incomplete state and re-presenting on next launch
- [x] 6.5 Show setup wizard on first launch (persisted via `UserDefaults` flag `setupComplete`); gate push-to-talk until setup is complete
- [x] 6.6 Add model switching UI in Settings with download prompts, size warnings, and integrity re-verification on model switch
- [x] 6.7 Implement HF access token input in setup wizard and Settings: store token in Keychain (`kSecClassGenericPassword`), use only during download requests, expose "Remove Token" action in Settings

## 7. Speech Transcription (WhisperKit)

- [x] 7.1 Implement `TranscriptionService` wrapping `WhisperKit.transcribe(audioURL:)` with the user-selected model
- [x] 7.2 Load/unload the WhisperKit model on demand; cache the loaded instance to avoid reload overhead
- [x] 7.3 Return `TranscriptionResult` with `rawText`, `language`, `duration`
- [x] 7.4 Handle WhisperKit empty/silence result: discard and reset to idle without triggering cleanup
- [x] 7.5 Implement 15-second timeout for the transcription step; on timeout surface error in popover
- [x] 7.6 Delete temporary WAV file immediately after `WhisperKit.transcribe()` returns (success or failure); on app launch scan `NSTemporaryDirectory()` for leftover Honyaku audio files and delete them
- [x] 7.7 Install `AVAudioInputNode` tap only on Control keydown; remove tap immediately on Control keyup — do not hold microphone session open between recordings

## 8. Text Cleanup (MLXLLM)

- [x] 8.1 Implement `CleanupService` using `MLXLLM`/`MLXLMCommon` with an MLX safetensors model loaded from local model storage
- [x] 8.2 Build default system prompt: remove filler words, false starts, self-corrections; preserve meaning; output clean prose
- [x] 8.3 Persist user-editable cleanup prompt to `UserDefaults`; expose reset-to-default action
- [x] 8.4 Implement cleanup toggle: when off, bypass LLM and return raw transcript directly
- [x] 8.5 Implement 15-second cleanup timeout; on timeout fall back to raw transcript and log

## 9. Transcript Paste

- [x] 9.1 Implement `PasteService`: write text to `NSPasteboard.general`, simulate `⌘V` via `CGEvent`, then restore prior pasteboard contents
- [x] 9.2 Handle paste failure (no focused text field): show "Text copied to clipboard" notification in popover
- [x] 9.3 Trigger paste after cleanup (or raw transcript if cleanup is off/timed out)
- [x] 9.4 On pipeline abort or paste failure: clear transcript text from `NSPasteboard.general` within 5 seconds and restore prior contents; register app-termination handler to restore pasteboard on quit

## 10. Speaker Diarization (WhisperKit SpeakerKit)

- [x] 10.1 Confirm SpeakerKit API surface in WhisperKit SPM package; add `SpeakerKit` target to the Xcode project if it is a separate module
- [x] 10.2 Implement `DiarizationService` wrapping SpeakerKit's diarize API; input: WAV file URL; output: array of `(start, end, speakerID)` segments
- [x] 10.3 Add SpeakerKit CoreML model download to `ModelDownloader` (~10 MB from argmaxinc HF repo); register in `ModelRegistry` as diarization tier
- [x] 10.4 Maintain an in-memory speaker embedding registry per app session for cross-recording label consistency
- [x] 10.5 Merge SpeakerKit segments with WhisperKit transcript segments: prefix each text block with `[Speaker N]` label
- [x] 10.6 Integrate `DiarizationService` into the transcription pipeline in order: WhisperKit → DiarizationService (if enabled) → CleanupService; pass speaker-labeled text to CleanupService; update default cleanup prompt to include instruction to preserve `[Speaker N]` tokens
- [x] 10.7 Gate diarization behind a Settings toggle (`UserDefaults`); skip `DiarizationService` entirely when disabled
- [x] 10.8 Add diarization model download prompt to first-run wizard (shown only if user enables the feature)

## 11. Settings UI

- [x] 11.1 Build `SettingsView` with sections: Models, Audio, Cleanup, Diarization, History, Privacy, General
- [x] 11.2 Models section: active speech model card, active cleanup model card, diarization model card — each with download state and switch action
- [x] 11.3 Audio section: microphone device picker, input level meter
- [x] 11.4 Cleanup section: enable/disable toggle, editable prompt textarea, Reset to Default button
- [x] 11.5 Diarization section: enable/disable toggle, model download status
- [x] 11.6 History section: transcript list with timestamps, Copy button per entry, Clear All button with confirmation
- [x] 11.7 General section: Launch at Login toggle (via `SMAppService`)
- [x] 11.8 Privacy section: HF access token field (show/hide, Remove Token action), confirmation that all processing is local

## 12. Privacy & Security Hardening

- [x] 12.1 Implement `NetworkAuditDelegate` for `URLSession`: in debug builds, assert on any outbound request that is not an explicit user-initiated model download; in release, entitlement scope blocks unexpected requests
- [x] 12.2 Set `history.json` permissions to 600 (owner read/write only) on creation; apply `isExcludedFromBackup = true` to the entire `~/Library/Application Support/Honyaku/` directory tree on first launch
- [x] 12.3 Disable MetricKit and Xcode Organizer crash reporting: set `MetricKitManager` payload delivery to nil; confirm no `MXMetricManager` subscription exists
- [x] 12.4 Audit all `os_log` call sites: ensure no transcript text, file contents, or user-generated data appears in log messages; log only operational metadata (durations, model IDs, error codes)
- [x] 12.5 Add `PrivacyInfo.xcprivacy` Privacy Manifest: declare microphone usage, no data collection, no third-party SDKs that transmit data, and all required-reason API usages (file timestamps, pasteboard)
- [x] 12.6 Implement app-quit cleanup handler (via `NSApplicationDelegate.applicationWillTerminate` and SIGTERM handler): abort in-flight pipeline, delete temp audio files, deregister CGEventTap, restore pasteboard

## 13. Tests

- [x] 13.1 Define service protocols: `ASRService`, `CleanupService`, `DiarizationService`, `HotkeyService`, `PasteService`, `ModelDownloading` — all production implementations conform; test doubles substitute freely
- [x] 13.2 Create `HonyakuTests` unit test target; add `NSMicrophoneUsageDescription` to its Info.plist; document Accessibility permission grant step in README
- [x] 13.3 Write unit tests for `ModelDownloader`: mock URLSession to cover successful download, network error + retry, disk-full abort, and SHA-256 checksum mismatch paths
- [x] 13.4 Write unit tests for `PasteService`: verify pasteboard restore on success, pasteboard clear within 5s on failure/abort
- [x] 13.5 Write unit tests for pipeline ordering: mock ASR + mock diarization → assert `[Speaker N]` tokens present in CleanupService input
- [x] 13.6 Write unit tests for `HotkeyService` state machine: verify Control keydown is ignored when `AppState.status == .processing`; use `XCTSkip` guard if Accessibility permission is absent
- [x] 13.7 Write unit test for `TranscriptStore`: assert `history.json` created with permissions `0o600` and `isExcludedFromBackup == true`
- [x] 13.8 Write unit test for launch-time temp file cleanup: pre-create a fake Honyaku WAV in `NSTemporaryDirectory()`, call the cleanup routine, assert file is gone
- [x] 13.9 Create `HonyakuIntegrationTests` target gated by `INTEGRATION_TESTS=1` environment variable
- [x] 13.10 Record audio fixtures: `silence.wav` (3s), `filler_heavy.wav` (20s), `clean_monologue.wav` (20s), `two_speakers.wav` (30s), `single_speaker.wav` (30s); commit to `Tests/Fixtures/`
- [x] 13.11 Write integration tests for `TranscriptionService` + `CleanupService` using `filler_heavy.wav` and `clean_monologue.wav` fixtures
- [x] 13.12 Write integration test for `DiarizationService` using `two_speakers.wav` (assert ≥2 speaker IDs) and `single_speaker.wav` (assert no labels)
- [x] 13.13 Write integration test for silence fixture: assert no pasteboard write and app returns to idle
- [x] 13.14 Write integration test verifying temp WAV deletion after `TranscriptionService` completes (success and error paths)
- [x] 13.15 Write XCUITests for: popover opens on menu bar click, Settings panel navigation, Clear History confirmation dialog, Launch at Login toggle persistence
- [x] 13.16 Add release checklist entry: run 10 recordings under mitmproxy (`brew install mitmproxy`), verify zero outbound requests; document result before tagging release

## 14. Distribution

- [ ] 14.1 Configure code signing with Developer ID Application certificate
- [ ] 14.2 Notarise build via `notarytool` in CI (GitHub Actions or Xcode Cloud)
- [ ] 14.3 Build DMG installer with drag-to-Applications layout
- [ ] 14.4 Publish first release on GitHub Releases with DMG artifact
- [x] 14.5 Write brief README: installation, permissions, model selection, privacy guarantee
