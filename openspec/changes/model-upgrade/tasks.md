## 1. Engine plumbing

- [x] 1.1 Add FluidAudio (`from: 0.17.4`) to `project.yml` for the Honyaku and integration-test targets; regenerate; clean build
- [x] 1.2 `ModelEngine` and `ModelInfo.engine` (plus `chatTemplateContext` for cleanup models); update registry consumers
- [x] 1.3 `SpeechEngine` protocol; move the Whisper path into `WhisperKitEngine` with no behaviour change; `TranscriptionService` dispatches by engine; existing tests pass
- [x] 1.4 `ParakeetEngine`: offline `loadLocal`, pad to 4,800 samples, silence → empty, word timings → `TimedSegment`s; unit-test padding, segment grouping and the silence rule

## 2. ModelInstaller

- [x] 2.1 `ModelInstaller` actor with `state`, `install` and `delete` per engine; completeness checks (Parakeet bundle files, MLX safetensors from the index)
- [x] 2.2 Load once after install, so the Neural Engine compile happens at download time
- [x] 2.3 `ModelStore.isDownloaded` delegates to `ModelInstaller`; `SetupWizardView` and `SettingsView` call `ModelInstaller.install`
- [x] 2.4 Unit tests: completeness checks against temporary folders (complete, missing weights, `.partial` left over)

## 3. Registry, migration, recommendation

- [x] 3.1 New registry entries (design Decision 2); remove the old ones; defaults from `recommended(forPhysicalMemory:)`
- [x] 3.2 `migratedID(_:)` applied in `HonyakuApp.init`; fix `AppState`'s fallback IDs
- [x] 3.3 Unit tests: migration mapping, recommendation at 8 and 36 GB

## 4. Cleanup latency

- [x] 4.1 `maxTokens` cap; `enable_thinking: false` through `additionalContext` for Qwen3-1.7B
- [x] 4.2 System-prompt reuse per (model, prompt), with the history reset each call, or the fallbacks in design Decision 5
- [ ] 4.3 Cleanup integration tests pass on both new tiers (faithfulness on the model's own output)

## 5. Benchmark and defaults

- [x] 5.1 `ModelBenchmarkTests`: TTS clip generation, WER and latency per speech engine, faithfulness and latency per cleanup tier, silent-clip check
- [ ] 5.2 Download both speech and both cleanup models on the developer's Mac; run the benchmark; record the numbers in design "Measured"
- [ ] 5.3 Confirm or adjust the defaults from the numbers (Fast cleanup median < 0.5 s)

## 6. Licences and docs

- [x] 6.1 `ThirdPartyNotices.md` bundled; README "Models" and credits sections updated

## 7. Verification

- [ ] 7.1 Clean build with no warnings; unit and integration tests pass
- [ ] 7.2 Developer: dictate with Parakeet (short words, sentences, silence), then switch to Whisper large-v3-turbo and dictate in another language
- [ ] 7.3 Developer: launch with the old Qwen 2.5 and small.en selections saved; they migrate, and the new models download on first use
- [ ] 7.4 Developer: offline dictation with Parakeet (Wi-Fi off)
