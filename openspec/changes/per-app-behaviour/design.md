## Context

Honyaku pastes with a simulated ⌘V into whatever app is in front (`PasteService`).

**Routing today** (`TranscriptionPipeline.destination`):
- first-run test
- discard
- Honyaku in front → History only
- paste

**Groundwork (merged as `dictation-stages`, PR #7).** This change plugs into:
- `DictationContext`: `appAtPaste` (a `TargetApp` with bundle ID, PID, name and `AppCategory`, read right before the final stages), `honyakuIsFrontmost`, `isSecureField`, `pasteAllowed`, `pasteOffNotice` and `notices`
- `AppCategory`: the known-bundle-ID table (terminal, codeEditor, chat, email, browser, other)
- `PerAppStages.make(_:)` in `Pipeline/Stages/PerAppStages.swift`: this feature's only entry into the pipeline. Its `final` stages run after Rewrite's and take the context `inout`
- `TranscriptionPipeline.destination(for:currentTest:)`: first-run test → `isSecureField` → `.blocked(notice:)` → Honyaku in front → `.saveOnly(notice:)` → `!pasteAllowed` → `.saveOnly(notice: pasteOffNotice)` → `.paste`
- Notices in `context.notices` are shown once after routing, the way errors are (orange, on the icon, capsule and General tab), until the next dictation starts
- `FeatureEnvironment.store(_:)`: one shared `FeatureStore` per feature, created from the environment's directory (a temp folder in tests and UI-test launches)
- `TranscriptEntry.appBundleID`, already filled in from `appAtPaste` (nil when Honyaku was in front)

**Facts checked:**
- **Field subrole:** the system-wide accessibility element's `kAXFocusedUIElementAttribute` → `kAXSubroleAttribute` reports `AXSecureTextField` for `NSSecureTextField`. WebKit, Chromium and Firefox map `<input type=password>` to the same subrole when they expose a tree.
- **Secure input is system-wide:** `IsSecureEventInputEnabled()` (Carbon) reports it, but not which process turned it on.
- **Owner PID:** `CGSessionCopyCurrentDictionary()["kCGSSessionSecureInputPID"]` returns the owner's PID while secure input is on, and the key is absent when it's off. Verified on this Mac (macOS 26 / Darwin 25.6) on 2026-10-01: a script called `EnableSecureEventInput()` and the key appeared, then disappeared after `DisableSecureEventInput()`.
  - The reported PID was the *responsible GUI app*, the terminal hosting the script, not the script's own process. Comparing it with `NSWorkspace.frontmostApplication.processIdentifier` is therefore the right test.
  - `IOConsoleUsers` in the IORegistry exposes the same key. It's a fallback only, because the public CGSession call is simpler.
- **macOS allows the paste:** secure input stops other processes reading keystrokes, not injecting them, and `NSSecureTextField` accepts a paste. The guard has to live in Honyaku.
- **Electron and some Chromium windows** (Slack, VS Code) expose no focused web element unless `AXManualAccessibility` is set. Honyaku never sets it.

## Goals / Non-Goals

**Goals:**
- Never paste into, or save text meant for, a password field.
- Text fits the app that receives it.
- Formatting only: words are never added, removed or reordered.

**Non-Goals:**
- Tone changes.
- Website detection inside browsers.
- Per-app model or prompt choice (Rewrite picks templates by app on its own).

## Decisions

### 1. The password guard is a pure decision, evaluated at paste time

```swift
enum PasteGuardDecision: Equatable { case allow, warn(ownerPID: pid_t?), block }

static func decide(focusedSubrole: String?,       // nil when unreadable
                   secureInputOwnerPID: pid_t?,   // nil when off or unknown
                   secureInputOn: Bool,
                   frontmostPID: pid_t?,
                   frontmostCategory: AppCategory?,
                   focusedPID: pid_t?,            // the process of the element with keyboard focus
                   focusedCategory: AppCategory?) -> PasteGuardDecision
```

The stage turns `ownerPID` into an app name (`NSRunningApplication`) for the notice; the decision itself stays pure.

**Rules, in order:**
1. `focusedSubrole == "AXSecureTextField"` → **block**.
2. Secure input is on and owned by the front app (`owner == frontmostPID`), or by the app whose element has keyboard focus (`owner == focusedPID`, e.g. a password dialog from another process while Safari is in front) → **block**. Exception: when that app is a terminal → **allow**, with no notice (see 1a). ⌘V goes to the focused element, so its process counts as much as the front app.
3. Secure input is on but owned by another app, or the owner is unknown → **warn**. The paste goes ahead.
4. Otherwise → **allow**. This includes an unreadable subrole: fail open.

**What happens:**
- **Block:** no ⌘V, no clipboard write and no History entry. The status reads "Not pasted: a password field is focused", shown like the existing "Saved to History" notice (orange, on the icon, the capsule and the General tab). No content goes to the log.
- **Warn:** the paste goes ahead, then the notice "Pasted. Note: <App> has secure input on" is shown through the groundwork notices channel. It is added only when the text will really be pasted (`pasteAllowed` and not `honyakuIsFrontmost`), so blocked, History-only and Honyaku-in-front runs never claim "Pasted". That channel shows notices the way errors are shown, until the next dictation; a separate non-error style would mean changing shared status code, so it is left for later.

**Where it runs:** `PasteGuardStage`, the last of `PerAppStages`' final stages, after `FormattingStage` (review fix: the guard has to know whether the app's rules turned the paste off before it can decide to warn; blocking doesn't depend on the order). It reads the probe, decides, and on **block** sets `context.isSecureField = true`, so the groundwork's routing returns `.blocked(notice: "Not pasted: a password field is focused")`. On **warn** it appends the notice. `TargetAppResolver` is left untouched: the stage runs at the same moment (no `await` between the paste-target read, the final stages and routing), so the decision and the formatting use the same app.

**The probe** (`SystemPasteGuardProbe`, behind the `PasteGuardProbe` protocol):
- **One budget of 0.25 s for all accessibility calls**, so a hung app can't stall the paste or the main thread for longer (worst case ≈ 0.25 s plus microseconds of local work):
  1. The system-wide element's focused element, so the guard sees the element ⌘V will reach, even a dialog from another process. On the system-wide element a messaging timeout is process-wide, so it is set to the budget just for this call and reset to the default (0) right after; nothing else in Honyaku is affected. The reviewers asked for an element-only timeout; reading the focused element of the front app instead would miss dialogs from other processes, so this scoped form is used and recorded here.
  2. `AXUIElementGetPid` on that element (local, no messaging).
  3. Its subrole, with the element's own timeout set to whatever is left of the budget. If the first call timed out or less than 20 ms is left, the subrole reads as unknown (fail open).
- Reads the secure-input owner only when `IsSecureEventInputEnabled()` is true: `CGSessionCopyCurrentDictionary()` first, then `IOConsoleUsers` in the IORegistry. No registry walk on an ordinary paste.
- The focused element's app category comes from its PID's bundle ID.
- Runs on the main actor right before ⌘V.
- Is injected, so tests use a fake.

The guard runs **before** the "Honyaku in front" check. Honyaku's own Hugging Face token field is a `SecureField`, so text dictated into it is blocked rather than saved to History.

#### 1a. Terminals with Secure Keyboard Entry (decided: Q35)

Terminal and iTerm2 "Secure Keyboard Entry" turns secure input on whenever the terminal is active. Under decision Q27 as written ("secure input owned by the frontmost app → block"), anyone with that setting on could never dictate into their terminal.

**Decided (Q35, 2026-10-01):** for apps in the Terminals category, secure input owned by the terminal is ignored: the text is pasted and saved as normal, with no notice. A notice on every dictation would only be noise. The terminal's own `AXSecureTextField` doesn't exist, so a `sudo` password prompt can't be detected either way. The Apps tab footer says so: "Terminals can't report password prompts. Don't dictate passwords."

This refines Q27; the user confirmed it.

### 2. Formatting rules

```swift
struct FormattingRules: Codable, Equatable {
    var finalFullStop: Keep/Drop          // drop: one trailing "." (not "...", "?", "!") after trimming whitespace
    var firstLetter: AsSpoken/Lowercase   // lowercase: see below
    var quotes: AsSpoken/Straight         // ‘ ’ ‚ ‛ → ' and “ ” „ ‟ → "
    var lineBreaks: Keep/Join             // join: whitespace runs containing a newline → one space; never a trailing newline
    var trailingSpace: Bool               // append one space unless the text already ends in whitespace
    var paste: Bool                       // false: History only
}
```

- **Order of application:** quotes → line breaks → final full stop → first letter → trailing space.
- **Dropping the final full stop** only removes a "." that ends a word: it must follow a letter, digit, ")" or a closing quote. So a standalone "." stays (`git add .`, `docker build .`), and an ellipsis stays. Abbreviations keep theirs: dotted ones ("e.g.", "i.e.", "U.S.", "a.m.", letter-dot sequences) and a short list of common ones ("etc.", "vs.", "cf.", "et al.", "approx.", "misc.", "Inc.", "Ltd.", "Corp.", "Co.", "Jr.", "Sr.", "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "St."). A URL, file name or number that ends a sentence ("example.com.", "notes.txt.", "3.5.") still loses the sentence's full stop, as before.
- **Joining line breaks** treats every line separator as a line break (`\R`: CR, LF, CRLF, U+2028, U+2029, U+0085, VT, FF) and removes C0 control characters other than tab, and DEL, so nothing like an escape sequence reaches a terminal.
- **Lowercasing the first letter** leaves the first word alone when it is:
  - "I" or a contraction of it ("I'm", "I'll", "I'd", "I've")
  - a word starting with a digit ("3D", "4K")
  - a word with another capital letter (acronyms, CamelCase: "API", "iOS", "GitHub")
  - a custom-vocabulary term
- **Words are never added, removed or reordered.** A unit test checks that the words in the output (case-insensitive, punctuation stripped) equal the words in the input.
- **The rules are a final `TextStage`** (`FormattingStage`, before `PasteGuardStage` in `PerAppStages`). It runs after cleanup and filler removal, using `context.appAtPaste` (decision Q14). Rewrite's final stages run before it, so Rewrite output passes through the same rules (Q28). The terminal one-line rule is just `lineBreaks: .join`.
- **Honyaku in front:** the text isn't headed for Honyaku, so no rules are applied; routing saves it as before.
- **Vocabulary terms for the first-letter exception** come from `context.speechHints.glossary` for now. The review found that the vocabulary feature fills it only for Whisper in English or Auto, so with Parakeet or another language terms would be lowercased. The custom-vocabulary branch adds `context.vocabularyTerms` (every enabled term, any engine); after it merges and this branch rebases, `FormattingStage` switches to it, with a pipeline test using the real `VocabularyPreparer` (task 7.1).
- **Speaker labels:** a transcript starting with `[Speaker N]` keeps its first letter, so labels are never altered.
- **What History stores:** the text as pasted, after the rules, plus `appBundleID`.
- **History-only apps:** the text is formatted the same way. The stage sets `context.pasteAllowed = false` and `pasteOffNotice = "Saved to History. <App> is set not to paste"`, which the groundwork routes to `.saveOnly(notice:)`. `<App>` is the override's display name, else the app's name, else its bundle ID.

### 3. Categories, defaults and precedence

**Category lookup:**
- `AppCategory` comes from the groundwork's known-bundle-ID list. Unknown apps are **Everything else**.
- Categories: Terminals, Code editors, Chat, Email, Browsers, Everything else.

**Defaults (decision Q26):**

| Category | Final full stop | First letter | Quotes | Line breaks | Trailing space | Paste |
|---|---|---|---|---|---|---|
| Terminals | drop | as spoken | straight | join | off | on |
| Code editors (VS Code, Cursor, Xcode, Zed) | drop | as spoken | straight | keep | off | on |
| Chat | keep | as spoken | as spoken | keep | off | on |
| Email | keep | as spoken | as spoken | keep | off | on |
| Browsers | keep | as spoken | as spoken | keep | off | on |
| Everything else | keep | as spoken | as spoken | keep | off | on |

**Precedence:** a per-app override (matched by bundle ID) beats the app's category, which beats Everything else.
- An override is a complete set of rules, copied from the app's category when it's created, and then edits apply to that app only.
- No merging of partial overrides, which keeps it predictable.

**Matching:** the paste-time `targetApp.bundleID`. With no bundle ID, the app counts as Everything else.

### 4. Routing order at paste time

The groundwork's `destination(for:currentTest:)` already has this order; this change only fills in the flags:
1. **First-run test or discard:** unchanged.
2. **Password guard:** `isSecureField` (set by `PasteGuardStage`, which runs after `FormattingStage`) → `.blocked`: no pasteboard write, no paste, no save.
3. **Honyaku in front:** History only, as today.
4. **Profile with `paste == false`:** `pasteAllowed == false` (set by `FormattingStage`) → History only, with the app-specific notice.
5. **Otherwise:** paste. A warn shows its notice afterwards.

The target app is read once by the groundwork, right before the final stages, so the guard and the formatting use the same app.

### 5. Store

- **`AppProfilesStore`**, a `FeatureStore` created by `FeatureEnvironment.store(_:)` (one per environment, shared by `FormattingStage` and the Apps tab):
  - Reads and writes `app-profiles.json` in Honyaku's Application Support folder.
  - Atomic writes, mode 0600, excluded from backup, the same treatment as `history.json`.
  - Tests pass a temp directory and never touch the user's real files.
- **What's stored:** only categories changed from their defaults, plus the overrides. This lets the built-in defaults improve later without a migration.
  - Contents: `{ version: 1, categories: { "terminal": FormattingRules, … }, apps: [{ bundleID, displayName, rules }] }`, keyed by `AppCategory` raw values. Missing rule fields decode to the as-spoken value, so later additions don't break older files.
- **Unreadable file:** use the defaults, move the file aside as `app-profiles.damaged-<date>.json` (like Vocabulary's `vocabulary.corrupt-<date>.json`), and show a notice in the Apps tab ("Your app rules couldn't be read. They were saved as … and Honyaku is using the default rules."), with Dismiss. Logged with no content.
- **If moving it aside fails, or the file is from a newer version:** leave it where it is, show a notice saying changes won't be saved, and never save over it. Rule changes still apply in memory until Honyaku quits.
- **Live updates:** the store is `@Observable`. The stage reads its current profiles at paste time, so changes apply to the next dictation without a relaunch.
- **Writes happen only when the user changes something**, never on load.

### 6. Settings > Apps tab

- **Position:** after Rewrite, following decision Q30 (General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy). Until Rewrite merges, it sits after Vocabulary.
- **Header line:** "Formatting only. Honyaku never changes your words here."
- **Categories:** one row each, with a disclosure for its six rules (segmented pickers and toggles). "Reset to defaults" appears on a changed category.
- **Apps with their own rules:**
  - A list with each app's icon and name, its rules and a Delete button.
  - The **+** menu lists the running regular apps with bundle IDs (not Honyaku and not ones already listed), plus "Choose app…", which opens an `NSOpenPanel` limited to `.app` in /Applications.
- **Footer:**
  - "Honyaku never pastes into password fields."
  - The terminal note from 1a.
- **Copy:** sentence case, active voice. Error messages say what to do.
- **Accessibility:** pickers have labels, the list rows read as "<App>, own rules", and everything is reachable by keyboard.

### 7. History shows where text went

- Each History row shows a small app icon and name, resolved from `appBundleID` through `NSWorkspace.urlForApplication(withBundleIdentifier:)`. If the app is no longer installed, the row falls back to the bundle ID.
- Entries with no app (older entries, first-run tests) show nothing extra.
- History-only entries show "Not pasted". The pipeline records it as a new optional `TranscriptEntry.pasted` (true for a paste, false for History only; nil on older entries).
- The label is its own view (`HistoryAppLabel`), added to the History row with one line, since Vocabulary and Rewrite also touch that row.

### 8. Testing

- **Unit tests:**
  - each rule, and their combinations
  - the words-unchanged property
  - the first-letter exceptions
  - category lookup and override precedence
  - the guard decision table (every row of Decision 1, including the terminal exception and fail-open)
  - routing order, through the injectable pipeline with a fake probe and fake paste
  - the store round-trip, the corrupt file and the temp directory
- **UI test:** the Apps tab opens, and adding an override from the running apps lists it.
- **Manual:**
  - a Safari password field: blocked and not saved
  - Terminal with Secure Keyboard Entry on: pasted and saved, no notice
  - Slack: paste, fail open
  - checking whether the push-to-talk listener still fires while secure input is on

## Risks / Trade-offs

- **Electron and some web fields fail open:** a password field in Slack or VS Code may not be detected. Browsers turn secure input on for their own password fields, which rule 2 catches.
- **The accessibility calls could hang** on an unresponsive app. Mitigated by one 0.25 s budget across the calls: the main thread waits at most about 0.25 s per paste.
- **Lowercasing the first letter can be wrong** for proper nouns not in the vocabulary. It's off by default in every category.
- **A full stop before a closing quote** (`said "done."`) is left alone, because the rule only drops a full stop that is the last character.
