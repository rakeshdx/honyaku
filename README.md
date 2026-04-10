# Honyaku

**Hold Control. Speak. Get clean text.**

Honyaku is a native macOS menu bar app that converts speech to clean, intelligent text entirely on your Mac. Nothing leaves your device.

## Features

- **Hold ⌃ Control** to record; release to transcribe and paste
- **Local Whisper models** — tiny, small, multilingual, Parakeet
- **Local LLM cleanup** — removes filler words (um, uh, like), false starts, self-corrections
- **Speaker diarization** — identify multiple speakers with `[Speaker 1]`, `[Speaker 2]` labels
- **Menu bar only** — no Dock icon; lives quietly in your status bar
- **100% private** — all models run on-device; no analytics, no telemetry, no cloud

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1 or newer) — required for WhisperKit Neural Engine acceleration

## Installation

1. Download `Honyaku.dmg` from [Releases](../../releases/latest)
2. Open the DMG and drag Honyaku to Applications
3. Launch Honyaku — it appears in your menu bar
4. Grant **Microphone** and **Accessibility** permissions when prompted
5. Choose your speech and cleanup models in the setup wizard and download them (~500 MB default)

> **Gatekeeper warning?** Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Honyaku. You only need to do this once.

## Permissions

| Permission | Why |
|---|---|
| Microphone | Capture audio while you hold Control |
| Accessibility | Register the global hotkey and paste text into the active app |

## Model selection

| Speech Model | Size | Notes |
|---|---|---|
| Whisper tiny.en | 75 MB | Fastest, English only |
| **Whisper small.en** (default) | 466 MB | Best speed/accuracy balance |
| Whisper small (multilingual) | 466 MB | 99 languages |
| Parakeet v3 | 1.4 GB | 25 languages |

| Cleanup Model | Size | Speed |
|---|---|---|
| **Qwen 0.8B** (default) | 535 MB | ~1–2s |
| Qwen 2B | 1.3 GB | ~4–5s |
| Qwen 4B | 2.8 GB | ~5–7s |

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

### Running tests

```bash
# Unit tests (fast, no models required)
xcodebuild test -scheme HonyakuTests -destination 'platform=macOS'

# Integration tests (requires downloaded models)
INTEGRATION_TESTS=1 xcodebuild test -scheme HonyakuIntegrationTests -destination 'platform=macOS'
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
