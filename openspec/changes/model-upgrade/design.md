## Context

Current state:
- **Speech:** only WhisperKit 0.18.0 (`TranscriptionService` → `WhisperKit.transcribe(audioPath:)`), with the tiny.en, small.en and small variants.
- **Cleanup:** mlx-swift-lm 2.30.6 with Qwen 2.5. `CleanupService` creates a fresh `ChatSession` on every call, with no `maxTokens`.
- **Downloads** are split between `SetupWizardView` (`WhisperKit.download` for speech, `ModelDownloader` for MLX) and `SettingsView` (`ModelDownloader` only).
- **`ModelStore.isDownloaded`** returns true for any model with no file list, which covers every speech model.
- **The pipeline** already has both a 16 kHz mono `[Float]` array (from `AudioCaptureService.extractFloatArray`) and a WAV URL for each dictation.

Research (2026-09-30), with sources in the change discussion:
- **Parakeet TDT 0.6B v2:** 6.05% average OpenASR WER, compared with Whisper small.en at 8.59%.
- **FluidAudio v0.17.4:**
  - Swift tools 6.0, macOS 14+, no package dependencies (only Apple frameworks, plus a bundled `NemoTextProcessing.xcframework`).
  - API: `AsrModels.download(to:force:version:progressHandler:)`, `AsrModels.loadLocal(from:version:)` (offline, synchronous), `AsrManager` (an actor), `transcribe(_ samples: [Float], decoderState: inout TdtDecoderState, language:)`.
  - Results: `ASRResult` gives `text`, `confidence` and `tokenTimings`; `buildWordTimings(from:)` turns those into word timings.
  - The minimum input is 4,800 samples (0.3 s).
  - Documented examples use `configure`/`initialize` APIs that no longer exist, so the code is written against the 0.17.4 source.

## Goals / Non-Goals

**Goals:**
- A better default speech model, and a multilingual option.
- Current cleanup models with the cleanup step's latency under control.
- One installer for every model type.
- Defaults chosen from measured numbers.
- A seamless move for existing selections.

**Non-Goals:**
- Upgrading WhisperKit to 1.x (argmax-oss-swift) or mlx-swift-lm to 3.x.
- Qwen3.5 or Gemma 4.
- Apple SpeechTranscriber.
- Streaming transcription.
- A redesign of the model UI (that's `ui-redesign`).

## Decisions

### 1. The `SpeechEngine` abstraction

```swift
protocol SpeechEngine: Sendable {
    func transcribe(audioURL: URL, samples16k: [Float], options: DecodeHints) async throws -> TranscriptionResult
}
```

`TranscriptionService` keeps its public API, the single-flight loading and the timeout. It resolves `ModelInfo.engine` and delegates:
- **`WhisperKitEngine`:** today's code moved as is: the local-first load, the `decodeOptions` short-clip trim, and `assembleText`/`stripNonSpeech`.
- **`ParakeetEngine`:** wraps `AsrManager`.
  - Input shorter than 4,800 samples is zero-padded up to 4,800.
  - Text, annotations and silence: `stripNonSpeech` runs on its text too. Empty text, or `confidence ≤ 0.1` with no token timings, is treated as silence, so the pipeline's silent discard applies.
  - Timed segments come from `buildWordTimings`: consecutive words are grouped into segments, breaking at a gap of more than 0.6 s or after sentence-final punctuation. This keeps `DiarizationService.mergeWithTranscript` working unchanged.
  - FluidAudio issue #971 (some word end times reported about 0.5 s early) only slightly affects the speaker-overlap maths; acceptable.

Both return the existing `TranscriptionResult`, so the pipeline, diarisation, cleanup and paste are untouched.

### 2. `ModelInfo.engine` and the registry

`ModelInfo` gains `engine: ModelEngine` (`.whisperKit`, `.parakeet`, `.mlx`, `.speakerKit`) in place of the "is `whisperVariant` set?" check. Registry entries:

| ID | Engine | Source | Size |
|---|---|---|---|
| `parakeet-tdt-v2` | parakeet | `FluidInference/parakeet-tdt-0.6b-v2-coreml` (downloaded by FluidAudio) | 464 MB |
| `whisper-large-v3-turbo` | whisperKit | `argmaxinc/whisperkit-coreml`, `openai_whisper-large-v3-v20240930_626MB` | 627 MB |
| `qwen3-1.7b` | mlx | `mlx-community/Qwen3-1.7B-4bit`, template flag `enable_thinking: false` | 968 MB |
| `qwen3-4b-2507` | mlx | `mlx-community/Qwen3-4B-Instruct-2507-4bit` | 2.3 GB |

Cleanup entries carry `chatTemplateContext: [String: Sendable]`, passed as `ChatSession(additionalContext:)`. The research confirmed that 2.30.6 forwards this to the Jinja template.

### 3. Where models live

- **Parakeet:** `~/Library/Application Support/Honyaku/Models/speech/parakeet-tdt-0.6b-v2`. FluidAudio's `download(to:)` ignores the last path component and always writes to `<parent>/<Repo.folderName>`, which is the repo name without "-coreml". So the path comes from `Repo.parakeetV2.folderName`, not a hard-coded string. Keeping it under Honyaku's folder means Delete and disk-usage work like the other models. Loading always uses `loadLocal`, never the `ModelHub`-backed `load`, which would fetch anything missing.
- **Whisper:** stays where WhisperKit's Hub layout puts it (`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>`), using the existing local-first loader.
- **MLX:** unchanged, under Honyaku's `ModelStore` directory.

### 4. `ModelInstaller`

`actor ModelInstaller` is the only place that knows how each engine checks, installs and deletes:

```swift
func state(of: ModelInfo) -> InstallState     // .notInstalled / .installed(bytes) / .incomplete
func install(_: ModelInfo, progress: @Sendable (Double) -> Void) async throws
func delete(_: ModelInfo) throws
```

- **Completeness checks, per engine:**
  - Parakeet: every `.mlmodelc` must contain `coremldata.bin`, `model.mil`, `metadata.json` and `weights/weight.bin`, plus `parakeet_vocab.json`, with no `*.partial` files.
  - Whisper: the existing `isModelDownloaded` plus the tokenizer.
  - MLX: the config plus every `*.safetensors` file listed in the index. This also fixes the known "partial MLX download counts as installed" problem.
- **Install:**
  - Parakeet: `AsrModels.download(to:force:version:.v2)` with progress. `force` is used when the state is `.incomplete`.
  - Whisper: `WhisperKit.download`.
  - MLX: `ModelDownloader`.
  - After any install, the model is loaded once, which compiles it on the Neural Engine at download time rather than on the first dictation.
- **Call sites:** `ModelStore.isDownloaded` delegates to `state(of:)`, so "Use" is only offered when a model is really installed. `SetupWizardView` and `SettingsView` swap their inline download code for `ModelInstaller.install`, with no layout changes. `ui-redesign` builds its views on this API.

### 5. Cleanup latency

- **Output cap:** `GenerateParameters(maxTokens: min(512, 2 × inputTokenEstimate + 32))`, where the input estimate is characters divided by 3.
- **Thinking off:** passed through `additionalContext` for Qwen3-1.7B. Qwen3-4B-Instruct-2507 has no thinking mode.
- **Reusing the system prompt:** keep one `ChatSession` per (model, prompt), and reset its conversation history before each call, so the processed system prompt is reused but earlier dictations never leak into the next.
  - If 2.30.6's `ChatSession` can't reset history while keeping the system prompt's key-value cache, fall back to the model's prompt cache (`PromptCache`/`KVCache` in MLXLMCommon), primed once with the system prompt.
  - If neither is possible in 2.30.6, measure without reuse and shorten the default prompt instead. The spec's under-0.5 s target for the Fast tier decides whether that's enough.
  - This is verified in the benchmark (Decision 7) before the defaults are set.

### 6. Migration and recommendation

- **Migration:** `ModelRegistry.migratedID(_:) -> String?` maps old IDs:
  - `whisper-tiny-en` and `whisper-small-en` → `parakeet-tdt-v2`
  - `whisper-small-multilingual` → `whisper-large-v3-turbo`
  - `qwen-1.5b-mlx` → `qwen3-1.7b`
  - `qwen-3b-mlx`, `qwen-7b-mlx` and the stray `qwen-0.8b` → `qwen3-4b-2507`

  `HonyakuApp.init` applies it to the saved selections before `AppState` reads them. The fallback in `AppState`'s initialiser is corrected too. Old files are left in place.
- **Recommendation:** `ModelRegistry.recommended(forPhysicalMemory:) -> (speech: String, cleanup: String)`. Below 16 GiB it's Parakeet and Qwen3-1.7B; otherwise Parakeet and Qwen3-4B. `defaultCleanupModelID` becomes `recommended(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory).cleanup`.

### 7. Benchmark (integration tests)

`HonyakuIntegrationTests/ModelBenchmarkTests.swift` runs only with `INTEGRATION_TESTS=1` and the models on disk. It prints a table and records numbers for the design; it only fails on the spec limits.
- **Speech:**
  - Clips: 12 sentences, 1–8 s long, rendered with `say -v Samantha` and converted to 16 kHz mono WAV with `afconvert`, in the test's temporary folder.
  - Each engine is measured on word error rate (a normalised word-level Levenshtein distance) and median time to text.
  - The same sentences are used for both engines. TTS audio is cleaner than a real mic, so this compares the engines relative to each other; it doesn't give absolute WER.
- **Cleanup:**
  - Sentences: the held-out set from `CleanupIntegrationTests` plus the TTS transcripts.
  - Each tier is measured on the pass rate of `isFaithful(raw:modelOutput)`, median and 90th-percentile cleanup latency (warm), and time to first dictation after load (cold).
  - The Fast tier's median must be under 0.5 s.

The results go into this design's "Measured" section before merging.

### 8. Licences

- `Sources/Resources/ThirdPartyNotices.md` (bundled) and a README section credit:
  - "Parakeet TDT 0.6B v2 by NVIDIA, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/); Core ML conversion by FluidInference; unmodified."
  - FluidAudio (Apache-2.0), WhisperKit (MIT), mlx-swift-lm (MIT), and the Qwen3 models (Apache-2.0).
- `ui-redesign` surfaces the notice in Settings > Privacy.

## Implementation notes

These are where the implementation differs from the decisions above, and why.

- **Decision 2 (thinking flag):** `ModelInfo` gained `disablesThinking: Bool` rather than a `chatTemplateContext` dictionary, because `ModelInfo` is `Codable` and `Equatable` and `[String: any Sendable]` is neither. `CleanupService` turns the flag into `["enable_thinking": false]` for the chat template.
- **Decision 5 (reusing the system prompt): implemented with the key-value-cache fallback, not `ChatSession`.**
  - `ChatSession` in 2.30.6 can't be used. In its cached mode it re-adds the system message and appends each call to the conversation, and it offers no way to reset the history while keeping the cache.
  - `CleanupService` therefore calls `ModelContainer.perform` directly and keeps a `PromptPrefixCache` per (model, thinking flag, prompt).
  - **The shared prefix** is the longest common token prefix of two probe prompts, `frame("a")` and `frame("b")`: the system prompt plus the user turn's opening markup.
  - **Each dictation** reuses the primed cache and feeds only the tokens after the prefix. Afterwards, every layer is trimmed back to the prefix length. The loop is written out because `trimPromptCache` in 2.30.6 only trims the first layer.
  - **Fallback:** if the prompt doesn't start with the prefix, or the cache can't be trimmed, it falls back to a fresh cache for that call.
  - **Dependency:** building `LMInput` needs `MLXArray`, so `mlx-swift` is now declared explicitly, pinned to the 0.30.x series (`minorVersion: 0.30.6`) that mlx-swift-lm already resolves.
- **Decision 5 (safety):** `stripDelimiters` also removes any `<think>…</think>` block, so reasoning is never pasted even if a model ignores `enable_thinking: false`.
- **Decision 6 (where migration runs):** migration happens in `AppState`'s property initialisers, through `AppState.resolvedSelection`, not in `HonyakuApp.init`. SwiftUI's `@State` stored properties are initialised before `init`'s body runs, so `HonyakuApp.init` would be too late. A migrated ID is written back to `UserDefaults`, because `CleanupService` reads the cleanup selection from there.
- **The ASR interface:** `ASRService` gained `transcribe(audioURL:samples16k:modelID:)`, and the pipeline passes the 16 kHz float samples it already extracts, so Parakeet never re-decodes the WAV. The old two-argument call remains for the tests; Parakeet decodes the file itself when it's given no samples.
- **Fetching on first use:** when Parakeet is selected but missing, the first dictation installs it through `ModelInstaller` (FluidAudio downloads and compiles it), then loads it locally. Launch warm-up never does this.
- **What "installed" means for Whisper:** a Whisper model counts as installed only once its tokenizer is on disk too. `ModelInstaller.install` loads it once after `WhisperKit.download`, which compiles it and fetches the tokenizer.
- **Benchmarks:** `CleanupService(modelID:)` can pin one model, so the benchmark compares tiers without changing the user's saved selection.
- **README:** the integration-test command now uses `TEST_RUNNER_INTEGRATION_TESTS=1`. The old `INTEGRATION_TESTS=1` never reached the test process.

### 9. What the benchmark changed

The first benchmark run exposed two problems the design hadn't anticipated.
- **The speaker-label rule broke Qwen3-4B.** With the original prompt, it answered "[Speaker 1]" to 4 of 10 sentences containing a filler, whether or not the prompt cache was reused (a probe compared fresh and reused runs and found them identical).
- **Qwen3-1.7B barely removed fillers.** It echoed its input, which scored "faithful" but did no cleaning.

A probe compared three prompts on both models, scoring "faithful, and fillers removed" across 10 sentences:

| Prompt | Qwen3-1.7B | Qwen3-4B |
|---|---|---|
| current | 4/10 | 6/10 |
| without the label rule | 6/10 | 10/10 |
| short and direct | 8/10 | 10/10 |

Changes made as a result:
- The default prompt becomes the short one: delete the fillers, add punctuation and capitals, change nothing else, output only the transcript, plus the same two worked examples.
- The speaker-label rule is appended only when the transcript contains `[Speaker`.
- `removeUnambiguousFillers` always runs on the final text, whether it came from the model, the fallback or with cleanup off.
- The benchmark scores filler removal alongside faithfulness.
- **Silence gate:** Whisper large-v3-turbo returned "Thank you." for a silent clip. The pipeline now computes a 100 ms-window RMS over the 16 kHz samples, and skips transcription when no window exceeds −45 dBFS. Parakeet already returned empty text for silence; the gate covers every engine.

### 10. Dictation language

On short clips, Whisper's per-dictation language detection is unreliable. In testing, an Italian phrase was taken as English and translated, and another came out as Russian.
- **Storage:** a new `dictationLanguage` setting in `UserDefaults`. It's either `nil` (Auto-detect) or a Whisper language code. `WhisperKit.Constants.languages` supplies the name-to-code table of about 99 languages, shown sorted by name.
- **How it's applied:** `decodeOptions(forDurationSeconds:language:)` sets `language = code, detectLanguage = false` when a language is chosen, or `detectLanguage = true` otherwise. `task` is always `.transcribe`. `WhisperKitEngine` reads the setting per dictation.
- **Parakeet** ignores it.
- **UI on this branch:** a `Picker` in the existing Settings Models section, disabled with an explanatory caption when the selected speech model is English-only. `ui-redesign` moves it into its Dictation tab when it rebases (its task 6.5).

## Risks / Trade-offs

- **[Risk] Parakeet and Whisper both compile for the Neural Engine at first load (seconds to minutes).** → Compile at install time (Decision 4). Launch warm-up loads a compiled model.
- **[Risk] FluidAudio's bundled Rust framework.** → Honyaku links no Rust. Check the Release archive signs and notarises with it (this belongs to `release-distribution`).
- **[Risk] `ChatSession` prefix reuse may not be available in 2.30.6.** → Fallbacks in Decision 5. The benchmark decides.
- **[Risk] Parakeet makes up text on silence.** → `stripNonSpeech` plus the confidence and empty-timing check. The benchmark includes silent clips.
- **[Trade-off] Dropping Whisper small.en removes the smallest English option** (487 MB vs Parakeet's 464 MB). → Parakeet is smaller and better anyway.
- **[Trade-off] The multilingual model (627 MB) is larger than the old small (466 MB)** → It's much more accurate. Offered, not defaulted.

## Measured

Measured on the developer's Mac (M3 Max, 36 GB, macOS 26.6.2) on 2026-09-30, with warm models and after the design Decision 9 fixes.

**Speech:** 12 `say`-rendered sentences, 1–8 s long. The WER compares engines relative to each other; TTS audio is cleaner than a real mic.

| Model | WER | Median time | Slowest | Silence, engine alone |
|---|---|---|---|---|
| parakeet-tdt-v2 | 4.2% | 52 ms | 58 ms | empty |
| whisper-large-v3-turbo | 5.0% | 810 ms | 871 ms | "Thank you." (stopped by the silence gate) |

**Cleanup:** 8 held-out sentences, 4 of them with fillers. Faithful means `isFaithful` passes on the model's own output.

| Model | Faithful | Fillers removed | Cold (first call) | Median | 90th pct |
|---|---|---|---|---|---|
| qwen3-1.7b | 8/8 | 4/4 | 1250 ms | 158 ms | 174 ms |
| qwen3-4b-2507 | 8/8 | 4/4 | 1389 ms | 307 ms | 334 ms |

**Multilingual:** with WhisperKit's default options, the multilingual model translated Japanese and Italian dictations into English, because the defaults start every decode with `<|en|>` (`detectLanguage` defaults to false while `usePrefillPrompt` is true). `decodeOptions` now always sets `detectLanguage: true`. The benchmark renders Italian and French clips with `say` and checks the output isn't translated: Italian came back exact ("Dov'è la stazione dei treni?"), and French came back in French, though with a mis-heard phrase from the synthetic voice.

**Defaults confirmed:**
- Parakeet for speech on every Mac: better accuracy than Whisper, and about 15× faster.
- Qwen3-1.7B under 16 GB. Its 158 ms median meets the Fast-tier target of under 0.5 s.
- Qwen3-4B at 16 GB and above, which is still well under half a second.

**Before the Decision 9 fixes:**
- Qwen3-4B was faithful on only 6/8 sentences, with a 90th percentile of 1193 ms, because it answered "[Speaker 1]".
- Qwen3-1.7B removed almost no fillers.
