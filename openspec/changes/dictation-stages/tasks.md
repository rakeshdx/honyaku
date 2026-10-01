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

## 6. Review fixes (user chose "All of it")

- [x] 6.1 Spec: proposal, design Decisions 7–12, the testing and push-to-talk deltas; `openspec validate dictation-stages --strict`
- [x] 6.2 Test isolation first: history, clipboard, settings, language, model delete; the test host and UI-test launches use an in-memory History, a separate settings suite and a temporary feature folder; `migratedSelectionKeys` is instance state
- [x] 6.3 Routing outcomes `.blocked(notice:)` and `.saveOnly(notice:)`; `destination(for:currentTest:)`; `pasteAllowed`, `pasteOffNotice`; text stages take the context `inout`
- [x] 6.4 Notices: `context.notices`, shown once after routing
- [x] 6.5 Feature slots (`VocabularyStages`, `RewriteStages`, `PerAppStages`) and `FeatureEnvironment` with `store(_:)`; `PipelineStages.live(_:)`; injected from `AppCoordinator`
- [x] 6.6 A failed dictation never interrupts the next recording; a failed paste reports at once and clears the pasteboard once
- [x] 6.7 Error-path tests (speech model fails, paste fails, mic permission, missing speech model status), final idle asserted, stage-order test without a cross-actor write
- [x] 6.8 Advisories: `speechModelID` in the context, whitespace-only text isn't pasted, no app recorded when Honyaku is in front, `ModelDownloads` names, the cleanup convenience removed, README line, more bundle IDs, the dictation language in `SpeechHints`
- [x] 6.9 Gates: clean build with no warnings in project sources; 188 unit tests pass with history.json untouched before and after; 4 UI tests pass; `openspec validate --strict`
- [x] 6.10 UI tests don't depend on the developer's menu bar: Finder is brought to the front so the icon isn't behind the notch, the icon must be hittable, and the right-click test reads the icon's own menu (`statusMenu.*` identifiers) instead of the app's main menu
