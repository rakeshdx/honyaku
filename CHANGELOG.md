# Changelog

All notable changes to Honyaku are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-04-10

Initial release.

### Added

#### Core features
- **Push-to-talk** — hold ⌃ Control to record; release to transcribe and paste
- **Local speech transcription** via WhisperKit (CoreML / Apple Neural Engine)
  - Whisper tiny.en (75 MB), small.en (466 MB, default), small multilingual (466 MB)
- **LLM transcript cleanup** via MLXLLM (ml-explore/mlx-swift-lm v2.30.6)
  - Qwen 2.5 1.5B 4-bit MLX (950 MB, default), 3B (1.9 GB), 7B (4.3 GB)
  - Temperature 0.0 (greedy decoding) for deterministic, faithful output
  - User-customisable system prompt with reset-to-default
  - Enable/disable toggle in Settings
- **Speaker diarization** via SpeakerKit (CoreML / ANE)
  - `[Speaker N]` labels injected before cleanup step
  - Enable/disable toggle; skipped when only one speaker detected
- **Auto-paste** — cleaned text written to frontmost app via simulated ⌘V; prior clipboard restored
- **Transcript history** — persisted to `history.json` (perms 600, excluded from iCloud/backup)

#### App & UX
- Menu bar only — no Dock icon (`LSUIElement = YES`)
- Animated menu bar icon reflects pipeline state (idle / recording / transcribing / processing / error)
- Menu bar popover with transcript history list, status header, clear-all button, Settings shortcut
- First-run setup wizard — model picker, download progress, permission onboarding
- Settings panel — Models, Audio, Cleanup, Diarization, History, Privacy, General sections
- Launch at login via `SMAppService` (enabled by default, toggleable)

#### Privacy & security
- All inference runs on-device; zero network traffic at runtime
- `NetworkAuditDelegate` asserts no unexpected outbound requests in debug builds
- Hugging Face access token stored exclusively in macOS Keychain
- `PrivacyInfo.xcprivacy` manifest declaring microphone usage and no data collection
- App-quit handler clears pasteboard and deletes temp audio files

#### Model management
- `ModelDownloader` — `URLSession` download with disk-space pre-check and SHA-256 integrity verification
- `ModelStore` — per-type local cache at `~/Library/Application Support/Honyaku/Models/`
- Automatic HuggingFace repo file listing for MLX models (safetensors directory format)
- Model download excluded from iCloud and Time Machine backup

#### Tests
- Unit test suite (`HonyakuTests`) — ModelDownloader, PasteService, HotkeyService, TranscriptStore, pipeline ordering, temp file cleanup
- Integration test suite (`HonyakuIntegrationTests`) — gated by `INTEGRATION_TESTS=1`
- UI tests (`HonyakuUITests`) — popover, settings navigation, history, launch at login

#### Developer tooling
- `project.yml` (XcodeGen) for reproducible project generation
- OpenSpec spec-driven development workflow with proposal, specs, design, and tasks
- C4 architecture diagrams (Context, Container, Component) in `design.md`
- `/review` slash command — automated pre-push review pipeline (tests, lint, secrets scan, licence check, multi-agent static analysis)

### Technical decisions

- Replaced LLM.swift / llama.cpp (xcframework) with MLXLLM — eliminates code-signing complexity, uses native Apple Silicon Metal/ANE inference
- WhisperKit chosen over whisper.cpp / mlx-whisper for native Swift, CoreML, ANE acceleration
- SpeakerKit (argmaxinc) chosen for diarization — zero-cost addition to existing WhisperKit dependency, ~10 MB CoreML model, ~122× real-time on M1

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 or newer) — Intel Macs are not supported
