## 1. Spec

- [x] 1.1 Proposal, design, testing and menu-bar-app deltas; `openspec validate dictation-stages --strict`

## 2. Context and categories

- [x] 2.1 `DictationMode`, `TargetApp`, `AppCategory` with the bundle-ID table, `SpeechHints`, `DictationContext`
- [x] 2.2 `TargetAppResolving` and the real `TargetAppResolver` (frontmost app, Honyaku active)
- [x] 2.3 Unit tests: category lookup (known, case-insensitive, unknown → other), mode IDs

## 3. Services behind protocols

- [x] 3.1 `AudioCapturing`, `ModelAvailability`; extend `ASRService` (hints, warm-up), `CleanupServiceProtocol` (request, prepare), `PasteServiceProtocol` (clear)
- [x] 3.2 `CleanupRequest`, `CleanupService.systemPrompt(for:transcript:)`, `accept(_:raw:request:)`, `clean(_:request:)`; keep `clean(_:prompt:englishFillers:)`
- [x] 3.3 Unit tests: an empty request matches today's prompt and token cap; strict vs no faithfulness; extra rules appended

## 4. Pipeline

- [x] 4.1 `PipelineServices` with `.live(appState:)`; `PipelineStages` with `.live`; `UserDefaults` injection
- [x] 4.2 `run()` in the order of design Decision 3; `llmStage(_:context:)`
- [x] 4.3 Mode-carrying hotkey callbacks; `startRecording(mode:)`, `stopRecordingAndProcess(mode:)` returning its task
- [x] 4.4 `AppState(defaults:)`, `TranscriptStore(fileURL:)`; `TranscriptEntry.mode` and `appBundleID`

## 5. Tests and gates

- [x] 5.1 `PipelineTests` with fakes: paste and save, silence, empty, cleanup failure fallback, cleanup off, Honyaku in front, first-run test routing, stage order, mode and app recorded in history
- [x] 5.2 History decoding of an old-format file
- [x] 5.3 Clean build with no warnings in project sources; unit tests (166 pass)
- [x] 5.4 UI tests (`HonyakuUITests`): 4 pass (rerun after the user approved Automation Mode)
