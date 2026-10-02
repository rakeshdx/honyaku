## 1. Prepare

- [x] 1.1 Rebase onto main after dictation-stages merges (vocabulary and per-app are built in parallel); update type names in design.md to the merged ones (DictationMode, DictationContext, CleanupRequest, AppCategory, llmStage)
- [x] 1.2 Add the `TerminalOneLine` stage in `RewriteStages.final` (design Decision 6); per-app-behaviour may later subsume it

## 2. Gesture

- [ ] 2.1 Verify that an Accessibility-trusted `.defaultTap` receives keyDown and mouse-down events with no new permission prompt (Apple documents that key events reach a tap when the process is trusted for Accessibility; a terminal-run script couldn't check it because the terminal isn't trusted. If the tap with key and mouse events can't be created, `HotkeyService` falls back to the flags-only mask. Developer check: after installing this build, hold Control and press C in Terminal; nothing is transcribed and no Input Monitoring prompt appears. `HotkeyServiceTests` now shows the app, with Accessibility alone, gets the tap with key and mouse events)
- [x] 2.2 Extend `PushToTalkGesture`: Shift seen during the hold (union), Command/Option cancel, `keyDown`/`mouseDown` cancel, swallow the Control release after a cancel; mode on `.end`
- [x] 2.3 `HotkeyService`: add keyDown, left/right/other mouse-down to the mask; read only the event type; pass every event through unchanged; keep the idle path a single state check
- [x] 2.4 Callbacks: `onRecordingStarted(mode)`, `onRewriteHint()` when Shift is first seen mid-hold, `onRecordingEnded(mode)`; wire in `AppCoordinator`; fall back to the flags-only mask if the full tap can't be created
- [x] 2.5 Unit tests for every row of the design's gesture table, including the tap-disabled recovery path

## 3. Templates and generation

- [x] 3.1 `RewriteTemplateID` and a `RewriteTemplates` registry: display names, descriptions, default prompts, caps (design Decision 3–4)
- [x] 3.2 `RewriteSettings` store (injectable UserDefaults): choice, category mapping, edited prompts
- [x] 3.3 Prompt assembly: shared rules + template + vocabulary `extraRules` + conditional speaker-label line; the "Dictation to rewrite" frame; strip echoed delimiters and labels
- [x] 3.4 Generation through `CleanupRequest(faithfulness: .none, maxTokens: cap)` with temperature 0 and the 60 s timeout; an empty output counts as a failure
- [x] 3.5 Unit tests: assembly, caps (including short dictations), label stripping, selection rules

## 4. Pipeline

- [x] 4.1 Route `.rewrite` through the LLM stage regardless of the cleanup toggle; resolve the template from the "Rewrite as" choice or the category of the app at start
- [x] 4.2 Fallbacks: no model / error / empty / timeout → fallback text (vocabulary + unambiguous fillers), notice, History entry saved as dictation
- [x] 4.3 Per-app final stages applied to rewrite output using the app at paste time (`RewriteStages.final` runs before `PerAppStages.final`; the terminal join is `TerminalOneLine` until per-app subsumes it)
- [x] 4.4 `TranscriptEntry.rewriteTemplateID` (optional); save raw and rewritten text
- [x] 4.5 Pipeline tests with fake services: rewrite success, each fallback, app switched before paste, terminal single line

## 5. UI

- [x] 5.1 Capsule: "Rewriting as <template>" while recording once Shift is seen; "Rewriting as <template>…" while generating
- [x] 5.2 Right-click menu: "Rewrite as" submenu with Automatic, separator, seven templates, checkmark
- [x] 5.3 Settings > Rewrite tab (own file), placed after Vocabulary and before Apps
- [x] 5.4 General tab Control+Shift hint
- [x] 5.5 History row: rewritten text, "Rewritten as …" caption, "Your words" disclosure; Copy copies the rewrite; search matches both
- [x] 5.6 VoiceOver "Rewriting" state on the status item

## 6. Tests and gates

- [x] 6.1 Integration tests: Qwen3-4B, Jira ticket and Chat message on fixed transcripts; no invented names, numbers or IDs
- [x] 6.2 UI test: "Rewrite as" menu items and the Rewrite tab
- [x] 6.3 Gates (each build under the shared build lock): `xcodegen generate`, clean build with no project warnings, unit tests (238), UI tests (6), rewrite integration tests (2, Qwen3-4B), `openspec validate rewrite-modes --strict`; history.json and the real `settingsTab` untouched
- [ ] 6.4 Developer: Control+Shift in both orders; Ctrl+C held for 1 s in Terminal transcribes nothing; Control-click cancels; a Slack rewrite, a Jira rewrite in a browser, an agent prompt in Terminal arrives as one line; a timeout fallback; History "Your words"

## 7. Review fixes (design Decision 9)

- [x] 7.1 Event tap on its own thread and run loop; busy state as a lock-protected flag set by the coordinator; own-process key-downs pass straight through; tap-disabled recovery on that thread; clean stop
- [x] 7.2 No stuck Control: clear Control from modifier events passed through during a hold; pass the Control release through after a cancel; gesture tests
- [x] 7.3 Notices match the outcome: "used your words as dictated"; only the routing notice for `.blocked` and `.saveOnly`; pipeline tests
- [x] 7.4 Echo stripping only for template headings, the dictation label and prompt lines; tests
- [x] 7.5 Cut short at the cap: `CleanupService.generate` reports the stop reason; trim to the last complete line or sentence; notice; tests
- [x] 7.6 Unclosed `<think>` dropped by `stripDelimiters`; a rewrite with one fails; tests
- [x] 7.7 Caps for scripts without spaces; tests with Japanese
- [x] 7.8 Flags-only fallback: a one-time notice and a General-tab line
- [x] 7.9 `ModelRegistry.smallCleanupModelID` in the Rewrite tab; an emptied prompt counts as the default; tests
- [x] 7.10 Prompt cache with up to three prompts
- [x] 7.11 `TerminalOneLine` handles every line break and strips control characters other than tab; tests
- [x] 7.12 MODIFY "Settings is a single window" (eight tabs, History row)
- [x] 7.13 Tests remove their temporary folders
- [x] 7.14 Gates: `xcodegen generate`, clean build with no project warnings, unit tests (256), UI tests (6), rewrite integration tests (2, Qwen3-4B), `openspec validate rewrite-modes --strict`; history.json and the models folder untouched


## 8. Merge with custom-vocabulary and per-app-behaviour

- [x] 8.1 Rebase onto main after custom-vocabulary and per-app-behaviour merged: tabs `general, models, dictation, vocabulary, rewrite, apps, history, privacy`; `TranscriptEntry` keeps `pasted` and `rewriteTemplateID`; `CleanupRequest` keeps `protectedTerms` with the rewrite's label and speaker rule; `DictationContext` keeps `vocabularyTerms` and `rewrite`; final stages run `TerminalOneLine`, then Per-app's formatting and password guard
- [x] 8.2 Tests across the merged features (`MergedFeaturesTests`): the 8-tab order; a rewrite into a terminal through the real per-app rules (one line, straight quotes, no final full stop, no trailing newline), also with the terminal's line breaks set to keep; the password guard still blocks a rewrite; a vocabulary correction reaches the rewrite and its keep-these-terms rule is in the rewrite prompt
- [ ] 8.3 Rebase onto main after fix-qwen-chat-template merges (CleanupService, TranscriptionPipeline, ServiceProtocols)
