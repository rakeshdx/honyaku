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
- **Rewrite:** the hotkey mode, the model step, messages when a rewrite can't run, and joining lines for terminals.
- **Per-app:** the target app and the end of the flow (formatting, "History only" apps, the password guard).

## Goals / Non-Goals

**Goals**
- One place for each feature to plug in, so three branches change different files.
- Today's behaviour, byte for byte, apart from the two older bugs fixed in Decisions 11 and 12.
- `run()` tested end to end without models, microphone, pasteboard, network, or the user's settings, history or Application Support.

**Non-Goals**
- No feature behaviour.
- No new Settings tabs; each feature adds its own.
- No change to the services themselves beyond taking a request or hint struct and an injectable pasteboard.

## Decisions

### 1. `DictationContext` travels with each dictation
```swift
struct DictationContext {
    var mode: DictationMode            // .dictate today; Rewrite adds a case
    var appAtStart: TargetApp?         // captured in startRecording
    var appAtPaste: TargetApp?         // captured just before the final stages
    var honyakuIsFrontmost: Bool       // at paste time
    var isSecureField: Bool            // at paste time; false until Per-app fills it
    var pasteAllowed: Bool             // true; a final stage may turn it off (an app set to History only)
    var pasteOffNotice: String?        // shown when pasteAllowed is off
    var notices: [String]              // messages for the user, shown once after routing (Decision 9)
    var firstRunTestSession: Int?      // the Try it test running when recording started
    var speechModelID: String?         // the speech model for this dictation, set before the preparers
    var language: String?              // detected by the speech model
    var englishFillers: Bool           // derived from language
    var speechHints: SpeechHints       // the chosen dictation language, plus what preparers add
    var cleanupRules: [String]         // preparers add; appended to the cleanup prompt
}
```
- **Why a single value type:** the pipeline owns it; preparers and stages get it `inout` and may only change it through these fields.
- **Alternative rejected:** properties on `AppState`. That would mix per-dictation facts with app state and invite races between overlapping dictations.
- **The dictation language** moves into `SpeechHints.language`: the pipeline reads the setting from its injected `UserDefaults` on every dictation, as `WhisperKitEngine` used to read `.standard` directly. Behaviour is the same, and tests no longer have to change the user's setting.

### 2. `AppCategory` and `TargetApp`
- `AppCategory`: `terminal`, `codeEditor`, `chat`, `email`, `browser`, `other`.
- A static bundle-ID table.
  - **Verified on a Mac:** Terminal, VS Code, Cursor, Xcode, Slack, Teams (new), Outlook, Chrome, Safari, Firefox, cmux.
  - **Common but unverified:** iTerm2, Ghostty, Warp, Kitty, Alacritty (both IDs), WezTerm, Zed, VS Code Insiders, Arc, Edge, Brave, Teams classic, Messages, Discord, Mail.
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
  @MainActor protocol TextStage { func apply(_ text: String, context: inout DictationContext) -> String }
  struct PipelineStages { var preparers; var afterTranscription; var final }
  ```
- **Why stages take the context `inout`:** a final stage must be able to turn off the paste (`pasteAllowed`, `pasteOffNotice`) and any stage may add a notice. Returning a result struct instead would need a second type for the same fields.
- **Synchronous on purpose:** stages are fast string transforms on the main actor. A stage that needs I/O loads its data ahead of time (its store reads the file once and on change), never inside `apply`.
- **Order in `run()`:**
  1. silence gate
  2. speech model check (`context.speechModelID` set)
  3. the chosen dictation language goes into `speechHints`
  4. preparers
  5. transcription (with `speechHints`)
  6. empty check
  7. diarization
  8. `afterTranscription` stages
  9. `llmStage`
  10. English filler removal
  11. resolve paste target
  12. `final` stages
  13. empty check (whitespace counts as empty)
  14. routing (Decision 7)
  15. paste or save
  16. notices shown (Decision 9)
- **What each feature adds:**
  - **Vocabulary:** a preparer (glossary and the cleanup rule) and an `afterTranscription` stage (replacements).
  - **Rewrite:**
    - a mode case
    - the branch in `llmStage` on `context.mode`, with `faithfulness: .none` and its own `maxTokens`
    - notices when a rewrite can't run
    - a `final` stage that joins lines for terminals
  - **Per-app:**
    - a `final` stage for formatting and History-only apps (`pasteAllowed = false`)
    - the password check in `TargetAppResolver.pasteTarget()` (`isSecureField`)
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
- **One entry point:** `clean(_:request:)`. The old `clean(_:prompt:englishFillers:)` convenience is removed; the integration tests build a `CleanupRequest`.
- **`llmStage(_:context:)`:**
  - takes the context `inout`, so it can add notices
  - reads the cleanup toggle, model and prompt
  - starts a missing model's download and returns the text as is
  - otherwise runs cleanup and falls back on error
  - Rewrite will branch here on `context.mode`; this function is the one place in the pipeline file Rewrite edits.

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
- **Pasteboard:** `PasteService(pasteboard:)` defaults to `.general`; tests pass a uniquely named pasteboard.
- **Tests:** `stopRecordingAndProcess` returns its `Task`, so tests can await a run.

### 7. Routing outcomes
```swift
enum DictationDestination: Equatable {
    case paste
    case saveOnly(notice: String?)   // saved to History, not pasted
    case blocked(notice: String)     // not pasted, not saved, nothing written to the pasteboard
    case firstRunTest                // shown in the first-run window
    case discard                     // started in a first-run test that has since ended
}
static func destination(for context: DictationContext, currentTest: Int?) -> DictationDestination
```
- **Order:**
  1. a recording started in a first-run test → `firstRunTest` if that test is still running, else `discard`
  2. `isSecureField` → `blocked("Not pasted: a password field is focused")`
  3. Honyaku in front → `saveOnly("Saved to History — Honyaku was in front")`
  4. `pasteAllowed == false` → `saveOnly(pasteOffNotice)`
  5. otherwise `paste`
- **The password guard comes before "Honyaku in front"**, so text dictated into Honyaku's own token field is blocked rather than saved (the Per-app spec relies on this).
- **Defaults keep today's behaviour:** with the flags at their defaults, the outcomes are the old `paste`, `saveOnly`, `firstRunTest` and `discard`.
- **The real `TargetAppResolver`** supplies `honyakuIsFrontmost` from `NSApplication.shared.isActive` and the app from `NSWorkspace.shared.frontmostApplication`, as today. Per-app fills `isSecureField` there.

### 8. History fields
- **New fields:** `TranscriptEntry.mode: String?` (`"dictate"` today) and `appBundleID: String?`.
  - `appBundleID` is the app at paste time.
  - It is `nil` when Honyaku itself was in front: Honyaku isn't where the text went.
  - For an app set to History only, it is that app.
- **Old entries still decode:** both fields are optional with nil defaults, so entries written before this change load. A fixture in the old format tests this.
- **Privacy:** the README says History records which app each dictation went to. It stays local, mode 0600 and excluded from backup.

### 9. Notices
- **Who adds them:** preparers, stages and `llmStage` append to `context.notices`, for example Rewrite's "Couldn't rewrite: pasted your words as dictated".
- **When they show:** after routing, the pipeline shows the routing outcome's notice (if any) followed by `context.notices`, joined into one message.
- **How they show:** the same way "Saved to History — Honyaku was in front" does today. The status ends on that message (orange, on the icon, the capsule and the General tab), and the next dictation clears it.
- **No early status change:** the status never leaves `.transcribing` or `.processing` before the run ends. So a notice can't open a gap in which a new recording starts while this one is still pasting.
- **When nothing shows:** a discarded dictation and a first-run test show no notices.

### 10. Feature slots and settings stores
- **One file per feature:**
  - Each feature has its own stage file in `Pipeline/Stages/` (`VocabularyStages`, `RewriteStages`, `PerAppStages`).
  - Each has `static func make(_ environment: FeatureEnvironment) -> PipelineStages`, which returns `.none` for now.
  - `PipelineStages.live(_:)` combines them in this order: Vocabulary, Rewrite, Per-app.
  - So in `final`, Rewrite's terminal join runs before Per-app's formatting; once Per-app's "join lines" rule exists it covers rewrites too, and Rewrite's join becomes a no-op.
  - A feature changes only its own file to plug in.
- **`FeatureEnvironment`** holds a folder and a `UserDefaults`:
  ```swift
  @MainActor @Observable final class FeatureEnvironment {
      let directory: URL         // Application Support/Honyaku in the app
      let defaults: UserDefaults // .standard in the app
      func store<S: FeatureStore>(_ type: S.Type) -> S   // one shared instance per type
  }
  @MainActor protocol FeatureStore: AnyObject { init(environment: FeatureEnvironment) }
  ```
- **One store per feature:**
  - A feature's stages and its Settings tab both call `environment.store(VocabularyStore.self)`, so they share one instance without a singleton and without editing `AppCoordinator`.
  - `AppCoordinator` creates the environment once, passes it to the pipeline, and puts it in the SwiftUI environment for Settings and first run.
- **Tests and UI-test launches** get a temporary folder and a private suite.

### 11. Tests never touch the user's data (older bug)
- **The bug:** some tests used the user's real data:
  - `TranscriptStoreTests` saved to the real `history.json`, and `clearAll()` deleted it.
  - `PasteServiceTests` overwrote the real clipboard.
  - `RedesignTests` built `AppState()` on `.standard`.
  - `ModelBenchmarkTests` changed the real dictation-language setting.
  - `ModelInstallerTests` asked the real installer to delete a bad model, relying on the refusal.
- **The fix:**
  - Every test uses temporary folders, private `UserDefaults` suites (removed afterwards), in-memory stores, uniquely named pasteboards and fakes.
  - Delete checks are tested through a pure function given a temporary base folder.
  - Integration tests may read the installed models but never write or delete outside temporary folders.
- **The host app:** when the app hosts unit tests, or is launched by UI tests:
  - it keeps History in memory
  - it keeps settings in a separate suite (`com.honyaku.app.tests`, wiped at launch)
  - its feature folder is temporary
  - it doesn't clean the temporary audio folder, so a dictation in the user's running copy is never touched.
- **Model migrations:** `AppState.migratedSelectionKeys` becomes instance state, so one test's migration can't leak into another.

### 12. A failed dictation never interrupts the next recording (older bug)
- **The bug:**
  - After a failed run, the pipeline waited 5 s to clear the transcript from the pasteboard, then set the status to idle unless it was an error.
  - An error isn't busy, so pressing Control during those 5 s started a new recording.
  - The reset then set the status to idle while the microphone was on, and key-up ignored the recording, leaving the tap running.
- **The fix:**
  - The status is settled first; then the pasteboard clear waits in the same task, never writing the status afterwards.
  - A failed paste no longer waits 5 s inside the run (still busy) before reporting. It throws at once, and the outer handler shows the error and clears the pasteboard once (not twice).
- **Device disconnect** already only acts on `.recording` and leaves in-flight runs alone. Unchanged.

## Risks / Trade-offs

- **Indirection makes `run()` harder to read.** Each stage list is named for its position, and Decision 3 documents the order.
- **The `@MainActor` stage protocols** keep feature stores on the main actor. Stages are fast string transforms, so that's fine.
- **`FeatureEnvironment.store(_:)` is a type-keyed cache.** That's simple, but two features must not share a store type; each owns its own.
- **Notices reuse the error status.** That matches today's "Saved to History" notice. A separate notice style can come later without changing the stages.

## Migration Plan

- **No migration step:** existing data needs no conversion. New history fields are optional.
- **Stored data does change from now on:** new entries record `mode`, and (unless Honyaku was in front) the receiving app's bundle ID.
- **Settings in tests:** the separate suite `com.honyaku.app.tests` holds the test host's settings; the user's `com.honyaku.app` settings are never written by tests.
