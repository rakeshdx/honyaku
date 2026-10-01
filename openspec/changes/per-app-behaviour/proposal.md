## Why

Honyaku pastes the same text wherever the cursor is. That's wrong in two ways:

- **It doesn't fit the app.**
  - A terminal gets a trailing full stop and curly quotes, which break a shell command.
  - A multi-line paste into a shell can run each line as a command.
  - A code editor gets a full stop after an identifier.
- **It's unsafe.**
  - If a password field is focused, Honyaku pastes into it, and History keeps the text on disk.
  - macOS doesn't stop a simulated ⌘V into a secure field, so Honyaku has to check itself.

## What Changes

- **Password-field guard** (always on, no setting).
  - Honyaku doesn't paste when macOS reports that a password field is focused, or when the app receiving the text has secure input turned on.
  - Blocked text is neither pasted nor saved to History.
  - The status reads "Not pasted: a password field is focused".
  - When some *other* app has secure input on, the paste goes ahead with a notice.
  - When the field type can't be read, Honyaku pastes (fail open). It never forces other apps to expose their accessibility tree.
- **Formatting rules per app.**
  - Deterministic and applied at paste time, for the app that actually receives the text:
    - final full stop (keep or drop)
    - first letter (as spoken or lowercase)
    - quotes (as spoken or straight)
    - line breaks (keep or join into one line)
    - trailing space (off or on)
    - paste (on, or off to save to History only)
  - Rules change formatting only. Plain dictation still never changes your words.
  - The same rules apply to Rewrite output when that change lands.
- **Categories with defaults, and overrides for single apps.**
  - Terminals, Code editors, Chat, Email, Browsers, Everything else.
  - An override for one app (from the running apps or "Choose app…") takes precedence over its category.
- **Settings > Apps tab** to edit categories and overrides, and reset them.
- **History rows show the app** each transcript went to.

## Capabilities

### New Capabilities
<!-- none: this extends existing capabilities -->

### Modified Capabilities
- `text-cleanup`: the paste step applies the receiving app's formatting rules, and honours "History only" apps and the password guard.
- `privacy`: never paste into, or save text meant for, a password field.
- `menu-bar-app`: Settings gets an Apps tab; History rows show the receiving app.
- `testing`: unit tests for the rules, profile lookup and the guard decision.

## Out of scope / follow-ups

- **Detecting a website inside a browser** (e.g. Jira in Chrome) from the URL or window title. Browsers are one category for now.
- **Tone changes per app** ("casual for Slack"). The faithfulness check only allows deletions, so per-app rules are formatting only. Tone belongs to Rewrite's templates.
- **Forcing Electron or Chromium apps to expose web accessibility** (`AXManualAccessibility`): never done. It changes those apps' behaviour and slows them down.
- **Checking whether the push-to-talk listener still fires while secure input is on.** This is a manual check, noted in tasks.

## Impact

- **Code:**
  - New `Sources/Honyaku/PerApp/`: `FormattingRules` (model and rule engine), `AppProfiles` and `AppProfilesStore`, `PasteGuard` (decision, system probe), `FormattingStage` and `PasteGuardStage`, `AppsSettings` (the tab) and `HistoryAppLabel`
  - `Pipeline/Stages/PerAppStages.swift` returns the two final stages
  - Small edits to shared files: the Settings `Tab` enum (Apps), the History row (one line), `TranscriptEntry.pasted`, and the History entry in `TranscriptionPipeline.run()`
- **Data:** a new `~/Library/Application Support/Honyaku/app-profiles.json` (mode 0600, excluded from backup). `TranscriptEntry.appBundleID` is filled in; it was added as optional by the groundwork.
- **Depends on:** `dictation-stages` (`DictationContext`, `AppCategory`, `TextStage` final stages, the injectable pipeline) and `custom-vocabulary`, whose terms are protected from lowercasing. This branch is rebased onto main with the groundwork merged (PR #7) and uses its merged names. Custom vocabulary hasn't merged yet; its terms reach the first-letter exception through the context's glossary (task 7.1 checks this after it merges).
