# Honyaku

**Hold Control. Speak. Get clean text.**

Honyaku is a native macOS menu bar app that converts speech to clean, intelligent text entirely on your Mac. Nothing leaves your device.

## Features

- **Hold ⌃ Control** to record; release to transcribe and paste
- **Local speech models** — NVIDIA Parakeet for English, Whisper large-v3-turbo for 99 languages
- **Local LLM cleanup** — removes filler words (um, uh, like), false starts, self-corrections
- **Speaker diarization** — identify multiple speakers with `[Speaker 1]`, `[Speaker 2]` labels
- **Menu bar only** — no Dock icon; lives quietly in your status bar
- **100% private** — all models run on-device; no analytics, no telemetry, no cloud

## Requirements

### Operating system

| Version | Support |
|---|---|
| macOS 14 Sonoma | ✅ Minimum supported |
| macOS 15 Sequoia | ✅ Supported |
| macOS 13 Ventura or earlier | ❌ Not supported |
| iOS / iPadOS / visionOS | ❌ Not supported |

### Hardware

| Device | Support |
|---|---|
| Apple Silicon (M1, M2, M3, M4 series) | ✅ Required |
| Intel Mac | ❌ Not supported |

Apple Silicon is required for:
- **FluidAudio** (Parakeet) and **WhisperKit** (Whisper) — Core ML models that run on the Apple Neural Engine (ANE)
- **MLXLLM** — MLX framework requires Apple Silicon Metal/ANE for inference
- **SpeakerKit** — CoreML diarization models optimised for ANE

> Honyaku will not build or run on Intel Macs.

## Installation

1. Download `Honyaku.dmg` from [Releases](../../releases/latest)
2. Open the DMG and drag Honyaku to Applications
3. Launch Honyaku — it appears in your menu bar
4. Grant **Microphone** and **Accessibility** permissions when prompted
5. Choose your speech and cleanup models in the setup wizard and download them (about 1.4 GB on 8 GB Macs, 2.7 GB on 16 GB and up)

> **Gatekeeper warning?** Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Honyaku. You only need to do this once.

## Permissions

| Permission | Why |
|---|---|
| Microphone | Capture audio while you hold Control |
| Accessibility | Register the global hotkey and paste text into the active app |

## Model selection

| Speech model | Size | Notes |
|---|---|---|
| **Parakeet TDT 0.6B v2** (default) | 464 MB | English; most accurate and fastest; adds punctuation |
| Whisper large-v3-turbo | 627 MB | 99 languages |

| Cleanup model | Size | Default for |
|---|---|---|
| **Qwen3 1.7B 4-bit MLX** | ~970 MB | Macs with less than 16 GB of memory |
| **Qwen3 4B Instruct 2507 4-bit MLX** | ~2.3 GB | Macs with 16 GB or more |

Selections of older models (Whisper tiny/small, Qwen 2.5) move to the nearest new model automatically; the old files stay on disk until you delete them in Settings.

Cleanup runs with **temperature 0.0** (greedy decoding) for deterministic, faithful output — the model removes fillers without paraphrasing or inventing content.

## Privacy guarantee

- No audio, transcripts, or speaker data ever leaves your Mac
- Models are downloaded once from Hugging Face; all runtime inference is offline
- Transcript history stored at `~/Library/Application Support/Honyaku/history.json` (permissions 600, excluded from iCloud and backups)
- You can clear all history at any time from Settings → History

## Building from source

```bash
# Install dependencies
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open Honyaku.xcodeproj
```

Press **⌘R** to build and run.

### Development signing

Debug builds are ad-hoc signed by default, which means macOS forgets the Accessibility grant on every rebuild. To keep it, sign Debug builds with your Apple Development certificate (a free Personal Team works):

1. Add your Apple ID in Xcode → Settings → Accounts, then Manage Certificates → **+** → Apple Development.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and set `DEVELOPMENT_TEAM` to your team ID.
3. Run `xcodegen generate`, then build and run.
4. One time only: remove the old Honyaku entry from Accessibility (or run `tccutil reset Accessibility com.honyaku.app`) and grant it again. If an earlier Debug build was registered as a login item, remove it in System Settings → General → Login Items.

Debug builds don't register themselves as a login item. Launching a new copy of Honyaku quits any older copy that's still running.

### Running tests

```bash
# Unit tests (fast, no models required)
xcodebuild test -scheme HonyakuTests -destination 'platform=macOS'

# Integration tests (requires downloaded models). The TEST_RUNNER_ prefix passes the variable to the test process.
TEST_RUNNER_INTEGRATION_TESTS=1 xcodebuild test -scheme HonyakuIntegrationTests -destination 'platform=macOS'

# Model benchmark: accuracy and latency of every installed model on this Mac
TEST_RUNNER_INTEGRATION_TESTS=1 xcodebuild test -scheme HonyakuIntegrationTests -destination 'platform=macOS' \
  -only-testing:HonyakuIntegrationTests/ModelBenchmarkTests
```

**Before running hotkey tests**: grant Accessibility permission to `xctest` in System Settings → Privacy & Security → Accessibility.

### Network privacy audit (pre-release)

```bash
brew install mitmproxy
mitmproxy --mode transparent
# Run Honyaku, perform 10+ recordings, verify zero outbound requests in mitmproxy log
```

## License

MIT

## Credits

Parakeet TDT 0.6B v2 by NVIDIA, licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), with Core ML conversion by FluidInference, used unmodified. The full list of models and libraries is in [`Sources/Resources/ThirdPartyNotices.md`](Sources/Resources/ThirdPartyNotices.md), which ships inside the app.
