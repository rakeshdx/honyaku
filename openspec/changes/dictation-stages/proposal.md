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
- **History:** `TranscriptEntry` gains optional `mode` and `appBundleID` fields. Existing `history.json` files still load.
- **Testability:**
  - the pipeline takes its services through protocols, with the real ones as defaults
  - pipeline unit tests use fakes, temporary folders and a private UserDefaults suite
  - `AppState` and `TranscriptStore` can be created against a private suite or folder

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `testing`: the dictation pipeline is unit-tested end to end with fake services.
- `menu-bar-app`: history entries record the dictation mode and target app, and older history files remain readable.

## Impact

- **Code:**
  - `Pipeline/TranscriptionPipeline.swift`
  - new `Pipeline/DictationContext.swift` and `Pipeline/PipelineStages.swift`
  - `Services/CleanupService.swift`, `Services/Protocols/ServiceProtocols.swift`, `Services/HotkeyService.swift`, `Services/TranscriptionService.swift`, `Services/PasteService.swift`, `Services/AudioCaptureService.swift`, `Services/ModelDownloads.swift`
  - `App/AppState.swift`, `App/AppCoordinator.swift`, `Models/TranscriptEntry.swift`, `Services/TranscriptStore.swift`
- **Tests:** new `HonyakuTests/PipelineTests.swift` and `HonyakuTests/DictationContextTests.swift`, plus additions to `CleanupServiceTests` and `TranscriptStoreTests`.
- **User-visible behaviour:** none.
- **Follows:** `custom-vocabulary`, `per-app-behaviour` and `rewrite-modes`, each in its own worktree from `main` once this merges.
