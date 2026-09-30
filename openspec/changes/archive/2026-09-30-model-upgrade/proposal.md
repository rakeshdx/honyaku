## Why

Honyaku's models are a generation behind:
- **Speech:** Whisper tiny.en scores 12.8% word error rate on the OpenASR benchmarks, and small.en 8.6%. NVIDIA's Parakeet TDT 0.6B v2 scores 6.1%, runs far faster on Apple Silicon, and adds its own punctuation.
- **Cleanup:** the Qwen 2.5 models have been superseded by Qwen3. Qwen3-4B-Instruct-2507 scores 83.4 on IFEval (a test of following instructions), and faithful instruction-following is exactly what the cleanup step needs.
- **Cleanup latency:** the code re-processes the full system prompt on every dictation and never caps the output length. That costs more time than the model choice does.

## What Changes

- **Speech lineup:**

  | Model | Size | Role |
  |---|---|---|
  | **Parakeet TDT 0.6B v2** via FluidAudio | about 0.6 GB | English; the new default |
  | **Whisper large-v3-turbo**, 626 MB compressed build, via WhisperKit | 627 MB | 99 languages |

  Whisper tiny.en, small.en and small are removed.
- **Cleanup lineup:**

  | Model | Size | Role |
  |---|---|---|
  | **Qwen3-1.7B**, 4-bit | 968 MB | fast; the default under 16 GB, with thinking turned off |
  | **Qwen3-4B-Instruct-2507**, 4-bit | 2.3 GB | best; the default at 16 GB and above |

  The three Qwen 2.5 models are removed.
- **Faster cleanup:**
  - The system prompt's processed state is kept and reused between dictations.
  - Output is capped at a token limit based on the input length.
  - Thinking mode is turned off through the chat template.
- **Migration:** existing selections move to the nearest new model, fetched on first use.
  - Whisper tiny.en and small.en → Parakeet.
  - Whisper small (multilingual) → large-v3-turbo.
  - Qwen 2.5 1.5B → Qwen3-1.7B.
  - Qwen 2.5 3B and 7B → Qwen3-4B.

  Old model files stay on disk until deleted.
- **Recommendation by memory:** `ModelRegistry.recommended(forPhysicalMemory:)` gives the default set for the Mac's RAM. The redesign's first run uses it.
- **`ModelInstaller`:** one service for checking, downloading, verifying and deleting models of every engine. Download logic moves out of `SetupWizardView` and `SettingsView`.
- **Benchmark:** integration tests that measure each candidate on this Mac, so the defaults come from measured numbers.
  - Speech: accuracy and latency on clips generated with macOS `say`.
  - Cleanup: faithfulness and latency on held-out sentences.
- **Credit:** Parakeet's weights are CC-BY-4.0, so the required attribution goes into a licences notice and the README.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `speech-transcription`:
  - The engine becomes Parakeet or Whisper.
  - New tier table.
  - Launch warm-up covers both engines.
- `text-cleanup`:
  - New tier table.
  - An ADDED latency requirement: cached prompt, token cap, thinking off.
- `model-management`:
  - The cleanup-model change example is updated.
  - ADDED: migration of old selections, recommendation by memory, licence credit.
- `privacy`: the no-network rule for a downloaded model now covers Parakeet too.

## Impact

- **Dependencies:** adds FluidAudio (`from:` its current release). WhisperKit stays at 0.18.0 and mlx-swift-lm at 2.30.6.
- **Code:**
  - `ModelRegistry`, `ModelInfo` (an engine field)
  - a new `SpeechEngine` protocol, with `WhisperKitEngine` and `ParakeetEngine`
  - `TranscriptionService` (dispatches to the engine)
  - `CleanupService` (cache, cap, thinking flag)
  - a new `ModelInstaller`
  - `ModelStore`: `isDownloaded` becomes correct for speech models
  - `SetupWizardView` and `SettingsView`: their download calls switch to `ModelInstaller`, with no redesign
- **Parallel work:** `ui-redesign`, in another worktree, rewrites the views and rebases onto this change after it merges.
- **Disk:** a new default install is about 0.6 GB of speech model plus 1–2.3 GB of cleanup model.
