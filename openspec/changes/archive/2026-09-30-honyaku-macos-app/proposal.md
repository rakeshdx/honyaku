## Why

Dictation tools either require a cloud connection (sacrificing privacy) or lack intelligent text cleanup. Honyaku is a native macOS app that delivers fast, accurate speech-to-text with LLM-based cleanup and speaker identification — entirely on-device, with zero data leaving the machine.

## What Changes

This is a greenfield macOS application. There is no existing codebase; this proposal establishes the entire product.

- **Push-to-talk recording**: Hold the Control key to capture audio; release to trigger the transcription pipeline
- **Local speech transcription**: Whisper-family models (via WhisperKit) convert audio to raw text on-device
- **Intelligent text cleanup**: A local LLM removes filler words, false starts, and self-corrections to produce clean prose
- **Speaker diarization**: Identify and label individual speakers when multiple voices are present, using pyannote-audio (bundled Python runtime) or a CoreML-converted equivalent
- **Model selection at setup**: During first-run initialization the user chooses which speech model and which cleanup model to use; selections can be changed later in Settings
- **Menu bar UI**: The app lives in the macOS menu bar — no Dock icon — with a compact popover for history, status, and settings
- **Privacy-first architecture**: All models run locally; no telemetry, no network calls, no cloud APIs

## Capabilities

### New Capabilities

- `push-to-talk`: Global Control-key hotkey that gates audio capture; integrates with macOS Accessibility and CoreAudio
- `speech-transcription`: Local Whisper-based ASR pipeline using WhisperKit; supports multiple model tiers (tiny → large)
- `text-cleanup`: Local LLM post-processing pass via LLM.swift; removes filler words and cleans up raw transcript
- `speaker-diarization`: Multi-speaker identification and timestamped labeling; pyannote-audio models bundled or converted to CoreML
- `model-management`: First-run model selection wizard; download, cache, and switch speech and cleanup models from Hugging Face
- `menu-bar-app`: macOS menu bar host, popover UI with transcript history, settings panel, and permission onboarding
- `privacy`: Cross-cutting privacy guarantees — runtime network isolation, backup exclusion, OS log hygiene, temp file lifecycle, app-quit cleanup, and Privacy Manifest
- `testing`: Unit, integration, UI, and privacy-audit test strategy with audio fixtures and network verification

### Modified Capabilities

*(none — this is a new project)*

## Impact

- **Language / runtime**: Swift 5.9+, SwiftUI, macOS 14.0+ (Apple Silicon required for WhisperKit)
- **Key dependencies**: WhisperKit + SpeakerKit (ASR + diarization, same SPM package, MIT), LLM.swift (cleanup LLM), ServiceManagement (launch at login), Accessibility API (global hotkey + paste)
- **Model storage**: `~/Library/Application Support/Honyaku/Models/` — models downloaded at first run, cached locally
- **Permissions required**: Microphone, Accessibility (global hotkey and simulated paste)
- **No network after setup**: Model downloads happen once from Hugging Face; all runtime processing is offline
