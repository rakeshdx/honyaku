## 1. Prepare

- [ ] 1.1 Rebase onto main after dictation-stages, custom-vocabulary and per-app-behaviour merge; update type names in design.md to the merged ones (DictationMode, DictationContext, CleanupRequest, AppCategory, LLM stage)
- [ ] 1.2 Confirm per-app-behaviour's final stage runs on rewrite output and joins lines for terminals; if not, add the fallback `TerminalOneLine` stage (design Decision 6)

## 2. Gesture

- [ ] 2.1 Verify that an Accessibility-trusted `.defaultTap` receives keyDown and mouse-down events with no new permission prompt
- [ ] 2.2 Extend `PushToTalkGesture`: Shift seen during the hold (union), Command/Option cancel, `keyDown`/`mouseDown` cancel, swallow the Control release after a cancel; mode on `.end`
- [ ] 2.3 `HotkeyService`: add keyDown, left/right/other mouse-down to the mask; read only the event type; pass every event through unchanged; keep the idle path a single state check
- [ ] 2.4 Callbacks: `onRecordingEnded(mode)`, `onModeHint(.rewrite)` when Shift is first seen; wire in `AppCoordinator`
- [ ] 2.5 Unit tests for every row of the design's gesture table, including the tap-disabled recovery path

## 3. Templates and generation

- [ ] 3.1 `RewriteTemplateID` and a `RewriteTemplates` registry: display names, descriptions, default prompts, caps (design Decision 3–4)
- [ ] 3.2 `RewriteSettings` store (injectable UserDefaults): choice, category mapping, edited prompts
- [ ] 3.3 Prompt assembly: shared rules + template + vocabulary `extraRules` + conditional speaker-label line; the "Dictation to rewrite" frame; strip echoed delimiters and labels
- [ ] 3.4 Generation through `CleanupRequest(faithfulness: .none, maxTokens: cap)` with temperature 0 and the 60 s timeout; an empty output counts as a failure
- [ ] 3.5 Unit tests: assembly, caps (including short dictations), label stripping, selection rules

## 4. Pipeline

- [ ] 4.1 Route `.rewrite` through the LLM stage regardless of the cleanup toggle; resolve the template from the "Rewrite as" choice or the category of the app at start
- [ ] 4.2 Fallbacks: no model / error / empty / timeout → fallback text (vocabulary + unambiguous fillers), notice, History entry saved as dictation
- [ ] 4.3 Per-app final stages applied to rewrite output using the app at paste time
- [ ] 4.4 `TranscriptEntry.rewriteTemplateID` (optional); save raw and rewritten text
- [ ] 4.5 Pipeline tests with fake services: rewrite success, each fallback, app switched before paste, terminal single line

## 5. UI

- [ ] 5.1 Capsule: "Rewriting as <template>" while recording once Shift is seen; "Rewriting as <template>…" while generating
- [ ] 5.2 Right-click menu: "Rewrite as" submenu with Automatic, separator, seven templates, checkmark
- [ ] 5.3 Settings > Rewrite tab (own file), placed after Vocabulary and before Apps
- [ ] 5.4 General tab Control+Shift hint
- [ ] 5.5 History row: rewritten text, "Rewritten as …" caption, "Your words" disclosure; Copy copies the rewrite; search matches both
- [ ] 5.6 VoiceOver "Rewriting" state on the status item

## 6. Tests and gates

- [ ] 6.1 Integration tests: Qwen3-4B, Jira ticket and Chat message on fixed transcripts; no invented names, numbers or IDs
- [ ] 6.2 UI test: "Rewrite as" menu items and the Rewrite tab
- [ ] 6.3 Gates (each build under the shared build lock): `xcodegen generate`, clean build with no project warnings, unit tests, UI tests, `openspec validate rewrite-modes --strict`
- [ ] 6.4 Developer: Control+Shift in both orders; Ctrl+C held for 1 s in Terminal transcribes nothing; Control-click cancels; a Slack rewrite, a Jira rewrite in a browser, an agent prompt in Terminal arrives as one line; a timeout fallback; History "Your words"
