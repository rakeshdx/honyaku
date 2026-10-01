## 1. Prepare

- [x] 1.1 Rebase onto main after dictation-stages merges (894858c); adopt the merged names (`PerAppStages`, `DictationContext.appAtPaste`/`isSecureField`/`pasteAllowed`/`pasteOffNotice`/`notices`, `.blocked(notice:)`, `FeatureEnvironment.store`) and update design.md where they differ
- [x] 1.2 Confirm the Terminals secure-input exception (design 1a) with the user before implementing the guard (Q35: paste and save, no notice)

## 2. Rules and store

- [x] 2.1 `FormattingRules` model and the rule engine (quotes → line breaks → final full stop → first letter → trailing space), with first-letter exceptions including vocabulary terms
- [x] 2.2 Category defaults (decision Q26) and `rules(for bundleID:)` with override precedence
- [x] 2.3 `AppProfilesStore(directory:)`: app-profiles.json, atomic write, 0600, backup-excluded, changed-only storage, damaged-file handling
- [x] 2.4 Unit tests: each rule, combinations, words-unchanged property, exceptions, precedence, store round-trip and damaged file (temp directory)

## 3. Password guard

- [x] 3.1 `PasteGuard.decide(...)` pure decision (design Decision 1)
- [x] 3.2 `SystemPasteGuardProbe`: focused subrole via the system-wide AX element with a 0.25 s messaging timeout; `IsSecureEventInputEnabled()` + `CGSessionCopyCurrentDictionary()["kCGSSessionSecureInputPID"]`; frontmost PID and bundle ID read together on the main actor; never set `AXManualAccessibility`
- [x] 3.3 Unit tests for the full decision table

## 4. Pipeline

- [x] 4.1 `PerAppStages.make` returns `PasteGuardStage` then `FormattingStage` as final stages; the groundwork routing (guard → Honyaku in front → History only → paste) is driven by `isSecureField` and `pasteAllowed`
- [x] 4.2 Formatting rules as a final `TextStage` using `context.appAtPaste`; History stores the formatted text, `appBundleID` and the new optional `pasted` flag
- [x] 4.3 Status messages: "Not pasted: a password field is focused", "Saved to History. <App> is set not to paste", "Pasted. Note: <App> has secure input on" (no transcript in status or logs)
- [x] 4.4 Pipeline unit tests with a fake probe and fake paste: blocked text is not pasted or saved; routing order; paste-time app wins

## 5. Settings and History

- [x] 5.1 Settings > Apps tab (`Views/AppsSettings.swift`): categories with rule pickers and reset; apps with their own rules (+ from running apps, "Choose app…", Delete); header and footer copy; accessibility labels
- [x] 5.2 Tab order: after Dictation for now (Vocabulary and Rewrite insert theirs before Apps when they merge)
- [x] 5.3 History rows show the app's icon and name (fallback: bundle ID) and "Not pasted" for History-only entries
- [x] 5.4 UI test: Settings > Apps opens and adding a running app lists it

## 6. Gates and checks

- [x] 6.1 `xcodegen generate`; clean build with no warnings in project code (through the shared build lock)
- [x] 6.2 Unit tests (230) and the HonyakuUITests scheme (6) pass (through the shared build lock); history.json unchanged and no app-profiles.json created by the tests
- [x] 6.3 `openspec validate per-app-behaviour --strict`
## 7. After custom-vocabulary merges

- [ ] 7.1 Check that every enabled vocabulary term reaches the first-letter exception (today through `context.speechHints.glossary`); pass the full list if the vocabulary only fills the glossary for Whisper

## 8. Manual checks

- [ ] 8.1 Developer, by hand: Safari password field (blocked, not saved); Terminal with Secure Keyboard Entry (pasted and saved, no notice); Slack (pasted); terminal one-line and no full stop; does push-to-talk still fire while secure input is on?
