## Context

Honyaku pastes with a simulated ⌘V into whatever app is in front (`PasteService`).

**Routing today** (`TranscriptionPipeline.destination`):
- first-run test
- discard
- Honyaku in front → History only
- paste

**Groundwork.** The `dictation-stages` change, which merges first, adds:
- `DictationContext`: the target app captured at recording start and refreshed at paste time, and an `isSecureField` slot
- `AppCategory`: a list of known bundle IDs per category
- a final `TextStage` list in the pipeline
- injectable services, so `run()` is unit-tested with fakes
- an optional `TranscriptEntry.appBundleID`

This design uses those planned names. If the groundwork merges with different names, the implementation follows the merged code.

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
enum PasteGuardDecision: Equatable { case allow, warn(ownerName: String?), block }

static func decide(focusedSubrole: String?,       // nil when unreadable
                   secureInputOwnerPID: pid_t?,   // nil when secure input is off
                   secureInputOn: Bool,
                   frontmostPID: pid_t?,
                   frontmostCategory: AppCategory?) -> PasteGuardDecision
```

**Rules, in order:**
1. `focusedSubrole == "AXSecureTextField"` → **block**.
2. Secure input is on and owned by the front app (`owner == frontmostPID`) → **block**. Exception: when the front app is a terminal → **warn** (see 1a).
3. Secure input is on but owned by another app, or the owner is unknown → **warn**. The paste goes ahead.
4. Otherwise → **allow**. This includes an unreadable subrole: fail open.

**What happens:**
- **Block:** no ⌘V, no clipboard write and no History entry. The status reads "Not pasted: a password field is focused", shown like the existing "Saved to History" notice (orange, on the icon, the capsule and the General tab). No content goes to the log.
- **Warn:** the paste goes ahead. The status shows "Pasted. Note: <App> has secure input on" for a few seconds, without the error colour.

**The probe** (`SystemPasteGuardProbe`):
- Reads the subrole through the accessibility API, with a short messaging timeout (`AXUIElementSetMessagingTimeout` ≈ 0.25 s) so a hung app can't stall the paste.
- Reads the secure-input state and owner through `IsSecureEventInputEnabled()` and `CGSessionCopyCurrentDictionary()`.
- Runs on the main actor right before ⌘V.
- Is injected, so tests use a fake.

The guard runs **before** the "Honyaku in front" check. Honyaku's own Hugging Face token field is a `SecureField`, so text dictated into it is blocked rather than saved to History.

#### 1a. Terminals with Secure Keyboard Entry (needs confirmation)

Terminal and iTerm2 "Secure Keyboard Entry" turns secure input on whenever the terminal is active. Under decision Q27 as written ("secure input owned by the frontmost app → block"), anyone with that setting on could never dictate into their terminal.

**Proposed:** for apps in the Terminals category, secure input owned by the terminal is a **warn**, not a block. The terminal's own `AXSecureTextField` doesn't exist, so a `sudo` password prompt can't be detected either way. The Apps tab footer says so: "Terminals can't report password prompts. Don't dictate passwords."

This refines Q27 and is flagged for the user to confirm before implementation.

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
- **Lowercasing the first letter** leaves the first word alone when it is:
  - "I" or a contraction of it ("I'm", "I'll", "I'd", "I've")
  - a word with another capital letter (acronyms, CamelCase: "API", "iOS", "GitHub")
  - a custom-vocabulary term
- **Words are never added, removed or reordered.** A unit test checks that the words in the output (case-insensitive, punctuation stripped) equal the words in the input.
- **The rules are a final `TextStage`.** It runs after cleanup and filler removal, using the *paste-time* target app (decision Q14). Rewrite output passes through the same stage when Rewrite lands (Q28). The terminal one-line rule is just `lineBreaks: .join`.
- **What History stores:** the text as pasted, after the rules, plus `appBundleID`.
- **History-only apps:** the text is formatted the same way. The status reads "Saved to History. <App> is set not to paste".

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

1. **First-run test or discard:** unchanged (the groundwork's `destination`).
2. **Password guard:** block → drop.
3. **Honyaku in front:** History only, as today.
4. **Profile with `paste == false`:** History only, with the app-specific status.
5. **Otherwise:** paste. A warn shows its notice.

The guard and the target app are read once, together, right before step 2, so the decision and the formatting use the same app.

### 5. Store

- **`AppProfilesStore(directory: URL)`:**
  - Reads and writes `app-profiles.json` in Honyaku's Application Support folder.
  - Atomic writes, mode 0600, excluded from backup, the same treatment as `history.json`.
  - Tests pass a temp directory and never touch the user's real files.
- **What's stored:** only categories changed from their defaults, plus the overrides. This lets the built-in defaults improve later without a migration.
  - Contents: `{ version: 1, categories: { "terminals": FormattingRules, … }, apps: [{ bundleID, displayName, rules }] }`.
- **Unreadable or unknown version:** use the defaults, log (with no content), and don't overwrite the file until the user changes something.
- **Live updates:** the store is `@Observable` and owned by `AppCoordinator`. The pipeline reads a snapshot at paste time, so changes apply to the next dictation without a relaunch.

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
- History-only entries show "Not pasted".

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
  - Terminal with Secure Keyboard Entry on: a paste with a notice
  - Slack: paste, fail open
  - checking whether the push-to-talk listener still fires while secure input is on

## Risks / Trade-offs

- **Electron and some web fields fail open:** a password field in Slack or VS Code may not be detected. Browsers turn secure input on for their own password fields, which rule 2 catches.
- **The accessibility call could hang** on an unresponsive app. Mitigated by the 0.25 s messaging timeout.
- **Lowercasing the first letter can be wrong** for proper nouns not in the vocabulary. It's off by default in every category.
- **A full stop before a closing quote** (`said "done."`) is left alone, because the rule only drops a full stop that is the last character.
