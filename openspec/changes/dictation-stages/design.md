## Context

`TranscriptionPipeline.run()` does everything inline:
- silence gate
- model check
- transcription
- diarization
- cleanup
- filler removal
- routing
- paste
- history

It builds its own services, and reads settings from `UserDefaults.standard` and the frontmost state from `NSApplication.shared`.

The three planned features each need a different point in that flow:
- **Vocabulary:** before transcription (Whisper hint), after transcription (replacements), and a cleanup rule.
- **Rewrite:** the hotkey mode and the model step.
- **Per-app:** the target app and the end of the flow (formatting, password guard).

## Goals / Non-Goals

**Goals**
- One place for each feature to plug in, so three branches change different lines.
- Today's behaviour, byte for byte.
- `run()` tested end to end without models, microphone, pasteboard, network, or the user's settings, history or Application Support.

**Non-Goals**
- No feature behaviour.
- No new Settings tabs; each feature adds its own.
- No change to the services themselves beyond taking a request or hint struct.

## Decisions

### 1. `DictationContext` travels with each dictation
```swift
struct DictationContext {
    var mode: DictationMode            // .dictate today; Rewrite adds a case
    var appAtStart: TargetApp?         // captured in startRecording
    var appAtPaste: TargetApp?         // captured just before the final stages
    var honyakuIsFrontmost: Bool       // at paste time
    var isSecureField: Bool            // at paste time; false until Per-app fills it
    var firstRunTestSession: Int?      // the Try it test running when recording started
    var language: String?              // detected by the speech model
    var englishFillers: Bool           // derived from language
    var speechHints: SpeechHints       // preparers fill it; passed to transcription
    var cleanupRules: [String]         // preparers add; appended to the cleanup prompt
}
```
- **Why a single value type:** the stages receive it read-only, and only the pipeline and preparers mutate it.
- **Alternative rejected:** properties on `AppState`. That would mix per-dictation facts with app state and invite races between overlapping dictations.

### 2. `AppCategory` and `TargetApp`
- `AppCategory`: `terminal`, `codeEditor`, `chat`, `email`, `browser`, `other`.
- A static bundle-ID table.
  - **Verified on a Mac:** Terminal, VS Code, Cursor, Xcode, Slack, Teams (new), Outlook, Chrome, Safari, Firefox, cmux.
  - **Common but unverified:** iTerm2, Ghostty, Warp, Kitty, Alacritty (both IDs), WezTerm, Zed, Arc, Teams classic, Mail.
  - Matching is case-insensitive, and unknown IDs are `other`.
- `TargetApp(bundleID:pid:name:category:)`.
- **Who uses it:**
  - Rewrite needs the category to pick a template and to join lines for terminals.
  - Per-app needs it for its profiles.
  - Both read the same table, so it lives here.

### 3. Extension points: preparers and two text-stage lists
- **Protocols:**
  ```swift
  @MainActor protocol DictationContextPreparer { func prepare(_ context: inout DictationContext) }
  @MainActor protocol TextStage { func apply(_ text: String, context: DictationContext) -> String }
  struct PipelineStages { var preparers; var afterTranscription; var final }
  ```
- **Order in `run()`:**
  1. silence gate
  2. preparers
  3. transcription (with `speechHints`)
  4. empty check
  5. diarization
  6. `afterTranscription` stages
  7. `llmStage`
  8. English filler removal
  9. resolve paste target
  10. `final` stages
  11. empty check
  12. routing
  13. paste or save
- **What each feature adds:**
  - Vocabulary: a preparer (glossary and the cleanup rule) and an `afterTranscription` stage (replacements).
  - Per-app: a `final` stage (formatting) and the password check in the target resolver.
- **Live wiring:** `PipelineStages.live` lives in its own file, with each list on separate lines, so the features add lines in different hunks.
- **Diarization comes first:** `afterTranscription` runs after diarization because the speaker merge rebuilds text from timed segments. Replacements applied before it would be lost.
- **What history records:** `rawText` keeps the speech model's output; `cleanedText` is what was pasted.

### 4. `CleanupRequest` and `llmStage`
- **The request:**
  ```swift
  struct CleanupRequest { systemPrompt, extraRules: [String], faithfulness: .strict | .none,
                          maxTokens: Int?, englishFillers }
  ```
- **Prompt and output:**
  - `CleanupService.systemPrompt(for:transcript:)` appends the speaker-label rule (as today), then each extra rule on its own line.
  - `CleanupService.accept(_:raw:request:)` holds today's empty-output and faithfulness fallback, now unit-testable. `.none` skips the check; Rewrite uses it.
  - `maxTokens: nil` keeps `outputTokenLimit(for:)`.
- **Compatibility:** `clean(_:prompt:englishFillers:)` stays as a convenience, so integration tests don't change.
- **`llmStage(_:context:)`:**
  - reads the cleanup toggle, model and prompt
  - starts a missing model's download and returns the text as is
  - otherwise runs cleanup and falls back on error
  - Rewrite will branch here on `context.mode`.

### 5. Mode-carrying hotkey callbacks
- **Signatures:** `onRecordingStarted: (DictationMode) -> Void` and `onRecordingEnded: (DictationMode) -> Void`.
- **Mode on release:** the pipeline takes the mode at start and lets the mode on release override it. Rewrite decides its mode from every modifier seen during the hold, which is only known at release.
- **Today:** the gesture always reports `.dictate`.

### 6. Injected services
- **The bundle:**
  ```swift
  struct PipelineServices { audioCapture: AudioCapturing, transcription: ASRService,
      diarization: DiarizationServiceProtocol, cleanup: CleanupServiceProtocol,
      paste: PasteServiceProtocol, models: ModelAvailability, targets: TargetAppResolving }
  ```
- **Production wiring:** `PipelineServices.live(appState:)` builds the real services.
- **Settings:** the pipeline also takes a `UserDefaults` (default `.standard`) for the values it reads on every dictation. `AppState(defaults:)` uses the same suite, so tests use one private suite.
- **History store:** `TranscriptStore(fileURL:)` lets tests use a temporary file.
- **Tests:** `stopRecordingAndProcess` returns its `Task`, so tests can await a run.

### 7. Routing reads the context
`destination(recordedInTest:currentTest:honyakuIsFrontmost:)` is unchanged. `run()` passes `context.firstRunTestSession` and `context.honyakuIsFrontmost`. The real `TargetAppResolver` supplies those, from `NSApplication.shared.isActive` and `NSWorkspace.shared.frontmostApplication`, as today.

### 8. History fields
- **New fields:** `TranscriptEntry.mode: String?` (`"dictate"` today) and `appBundleID: String?` (the app at paste time). Both are optional with nil defaults, so entries written before this change decode.
- **Tested:** a fixture in the old format.

## Risks / Trade-offs

- **Indirection makes `run()` harder to read.** Each stage list is named for its position, and design Decision 3 documents the order.
- **The `@MainActor` stage protocols** keep feature stores on the main actor. Stages are fast string transforms, so that's fine.
- **A one-line merge conflict** remains in `PipelineStages.live` when two features add to the same list. Vocabulary and Per-app use different lists, so this is low risk.

## Migration Plan

None: no stored data changes shape for existing users. New history fields are optional.
