## Why

Three features are planned next: custom vocabulary, rewrite modes and per-app behaviour. All of them would edit the same code:
- `TranscriptionPipeline.run()`
- `CleanupService.clean(_:prompt:englishFillers:)`
- the hotkey callbacks

The pipeline also creates its own services, so `run()` has no tests. The three features can't be built in parallel worktrees without heavy merge conflicts, and none of them could be tested end to end.

This change makes the pipeline pluggable and testable first, with no change a user can see.

## What Changes

- **Context:** each dictation carries a `DictationContext` with:
  - its mode (only plain dictation for now)
  - the app in front when recording started and when the text is pasted, as bundle ID, PID and category
  - a password-field flag, which nothing sets yet
- **App categories:** `AppCategory` sorts known bundle IDs into terminal, code editor, chat, email, browser and other.
- **Pipeline stages:**
  - context preparers run before transcription and can add speech hints and cleanup rules
  - text stages run after transcription, before cleanup
  - text stages also run at the end, after cleanup and filler removal, before routing
  - all of these start empty
- **Cleanup request:** `CleanupService` takes a `CleanupRequest` (system prompt, extra rules, faithfulness, token cap, English fillers). An empty request behaves exactly as today. The cleanup step moves out of `run()` into its own `llmStage` function.
- **Hotkey:** the hotkey callbacks carry a `DictationMode`. The mode reported on release wins, so a later mode can be decided from the modifiers held during the recording.
- **History:** `TranscriptEntry` gains optional `mode` and `appBundleID` fields. Existing `history.json` files still load. New entries record which app the text went to (nothing when Honyaku itself was in front).
- **Routing outcomes:** besides paste, save-only and the first-run test, a dictation can be **blocked** (not pasted, not saved, with a message) or **saved only with a message**. The context carries `pasteAllowed` and a password-field flag that a resolver or final stage can set. Nothing sets them yet.
- **Notices:** stages, preparers and the model step can add messages for the user to the context. The pipeline shows them once, after the text is routed, the way "Saved to History — Honyaku was in front" is shown today.
- **Feature slots:** each feature has its own stage file (`VocabularyStages`, `RewriteStages`, `PerAppStages`, all empty) that `PipelineStages.live` combines, so the three features edit different files.
- **Feature settings:** a `FeatureEnvironment` (a folder and a `UserDefaults`) gives each feature one shared settings store, used by both its stages and its Settings tab. The app uses Application Support and `.standard`; tests and UI-test launches use a temporary folder and a private suite.
- **Testability:**
  - the pipeline takes its services through protocols, with the real ones as defaults
  - pipeline unit tests use fakes, temporary folders and a private UserDefaults suite
  - `AppState` and `TranscriptStore` can be created against a private suite or folder
- **Tests never touch the user's data** (fixes an older bug): some tests saved to and deleted the user's real `history.json`, wrote to the real clipboard, or changed the real dictation-language setting. Every test now uses temporary folders, private settings suites and private pasteboards, and the app hosting the unit tests (or launched by UI tests) keeps its history in memory and its settings in a separate suite.
- **A failed dictation never interrupts the next recording** (fixes an older bug): after an error, the status was reset 5 seconds later, when the clipboard was cleared. If Control was pressed in those 5 seconds, the reset ended the new recording's status and left the microphone on. The status is now settled before the wait, and a failed paste is reported at once.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `testing`: the dictation pipeline is unit-tested end to end with fake services.
- `menu-bar-app`: history entries record the dictation mode and target app, and older history files remain readable.
- `testing`: tests never read, change or delete the user's history, settings, clipboard or models.
- `push-to-talk`: a failed dictation never interrupts the next recording.

## Impact

- **Code:**
  - `Pipeline/TranscriptionPipeline.swift`
  - new `Pipeline/DictationContext.swift`, `Pipeline/PipelineStages.swift`, `Pipeline/FeatureEnvironment.swift`, and `Pipeline/Stages/VocabularyStages.swift`, `RewriteStages.swift`, `PerAppStages.swift`
  - `Services/CleanupService.swift`, `Services/Protocols/ServiceProtocols.swift`, `Services/HotkeyService.swift`, `Services/TranscriptionService.swift`, `Services/SpeechEngine.swift`, `Services/ParakeetEngine.swift`, `Services/WhisperKitEngine.swift`, `Services/PasteService.swift` (injectable pasteboard), `Services/AudioCaptureService.swift`, `Services/ModelDownloads.swift`, `Services/ModelInstaller.swift`
  - `App/AppState.swift`, `App/AppCoordinator.swift`, `Models/TranscriptEntry.swift`, `Services/TranscriptStore.swift`
  - `README.md` (Privacy: History records the receiving app)
- **Tests:** new `HonyakuTests/PipelineTests.swift` and `HonyakuTests/DictationContextTests.swift`; `CleanupServiceTests`, `TranscriptStoreTests`, `PasteServiceTests`, `RedesignTests`, `ModelRegistryTests`, `ModelInstallerTests` and the integration tests no longer touch the user's data.
- **User-visible behaviour:**
  - none from the groundwork itself
  - after a failed dictation, a new recording started within 5 seconds keeps working, and a failed paste shows its error at once
  - History entries now record the receiving app's bundle ID (not shown yet)
- **Follows:** `custom-vocabulary`, `per-app-behaviour` and `rewrite-modes`, each in its own worktree from `main` once this merges.
