## Context

The UI is four SwiftUI views (about 950 lines) in three `WindowGroup`s plus a `MenuBarExtra(.window)`. They are:
- `MenuBarPopoverView`
- `OnboardingView`
- `SetupWizardView`
- `SettingsView` (a `NavigationSplitView` with seven sections)

Settings writes `@AppStorage` directly, while the pipeline reads `AppState`, which is why model changes need a relaunch. There's no asset catalog, so colours are in code. The audit came from offscreen renders of each view (via `NSHostingView.cacheDisplay`, in a temporary test that isn't committed).

`model-upgrade` is developed in parallel in another worktree. It owns the model registry, services, dependencies and `ModelInstaller`. This change owns the views, scenes, the capsule and the level metering.

## Goals / Non-Goals

**Goals:**
- A distinct but native identity.
- The Control keycap as the one memorable element.
- A recording capsule that shows it's listening without stealing focus.
- First run as one flow that ends in a real dictation.
- A native Settings window.
- Settings that apply live.

**Non-Goals:**
- Changing the push-to-talk gesture or the pipeline stages.
- The model lineup (that's `model-upgrade`).
- An app icon redesign.
- Localisation.

## Decisions

### 1. Design tokens

**Colour:** system backgrounds and materials throughout (`.regularMaterial` in the popover and capsule; standard window backgrounds elsewhere), plus two named colours defined as dynamic `NSColor`s in `Theme.swift`:

| Token | Light | Dark | Used for |
|---|---|---|---|
| `ai` (indigo accent) | `#2E4A7D` | `#8FA8D8` | the app's `.tint`, the selected state, the keycap face while idle |
| `live` | `#E0484F` | `#FF6B6B` | the keycap and level meter while recording, and nothing else |

Text, dividers and fills use the system `.primary`, `.secondary`, `.tertiary` and `.separator`, so contrast follows the system, including Increase Contrast.

**Type:**
- **SF Pro** (system) for all interface text, at macOS sizes: body 13, callout 12, caption 11, title 15 semibold.
- **New York** (`.system(design: .serif)`), 14 pt with 1.3 line spacing, for transcript text only, in the popover rows, the History tab and the live-test result.
- **SF Pro Rounded**, medium, for the ⌃ glyph on the keycap.
- Sentence case everywhere: no all-caps labels, no eyebrows.

**Shape:** 10 pt corners for panels, 6 pt for controls, and the capsule is fully rounded. There are no drop shadows except the capsule's system panel shadow.

### 2. The keycap component (the signature)

`KeycapView(state:level:)` is a 34 × 34 pt rounded square drawn like a physical key: a face, a 1 pt lighter top edge and a 2 pt darker bottom lip.

| State | Appearance |
|---|---|
| Idle | an `ai` glyph on a quiet face |
| Recording | pressed: the face moves down 1 pt and the lip shrinks; tinted `live`; a level fill rises from the bottom of the face |
| Transcribing | the glyph dims, with a small indeterminate ring |
| Error | a system-orange edge |

It's used in the popover header, the capsule, first run (the live test) and Settings > General. The only animation is the press or release (0.12 s spring) and the level fill (driven by the level, not a timer). With Reduce Motion, the press is a colour change only.

### 3. Popover layout (340 pt wide)

```
┌──────────────────────────────────────┐
│ ╭───╮  Hold Control to talk          │  keycap + state line (callout, primary)
│ │ ⌃ │  Parakeet, cleanup on          │  model line (caption, secondary)
│ ╰───╯                                │
├──────────────────────────────────────┤
│ So I think we should call them.      │  serif 14, up to 3 lines
│                               2m ago │  caption, tertiary, right-aligned
│ It was, like, really fast.    5m ago │
│ …                         (scrolls)  │  up to 20 rows, max height 300
├──────────────────────────────────────┤
│ Settings…                       Quit │
└──────────────────────────────────────┘
```

- **Row behaviour:** hovering shows copy and delete icons; the context menu offers Copy and Delete; clicking a row copies it, and the time label briefly reads "Copied".
- **Alignment:** everything left-aligned apart from the times.
- **Empty state:** the keycap plus the line "Hold Control, speak, then let go. The text appears where you're typing."
- **Errors** replace the state line with the full message, wrapping.
- Delete-all moves to Settings > History.

### 4. Recording capsule

`RecordingCapsuleController` owns an `NSPanel`, with:
- styles `[.nonactivatingPanel, .borderless]`, `level = .statusBar`
- `ignoresMouseEvents = true`, `hidesOnDeactivate = false`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- `becomesKeyOnlyIfNeeded`, and it never calls `makeKey`

It hosts `RecordingCapsuleView` and is positioned 80 pt above the bottom of the screen that has the mouse pointer, centred horizontally.

```
╭────────────────────────────────╮
│ ╭───╮  ▁▃▆▇▅▂▁▃▅   0:04        │   recording: keycap + 12-bar level meter + elapsed time
│ ╰───╯                          │
╰────────────────────────────────╯
╭────────────────────────────────╮
│ ╭───╮  Transcribing…           │
╰────────────────────────────────╯
```

The controller observes `AppState.status`:
- `.recording` shows the capsule, with a 0.15 s fade-in.
- `.transcribing` and `.processing` switch it to "Transcribing…".
- `.idle` fades it out over 0.25 s.
- `.error` shows a one-line error for 1.5 s, then hides it.
- A quick tap never shows it: the capsule appears only after the recording has run for 250 ms.
- With Reduce Motion there are no fades.

### 5. Input level

- The `AudioCaptureService` tap computes the RMS of each buffer on the audio thread and converts it to a 0–1 level (−50 to 0 dBFS, clamped).
- It publishes at most 30 Hz via `DispatchQueue.main.async` into `AppState.inputLevel`.
- `AppState.recordingStartedAt` drives the elapsed time (`TimelineView(.periodic(from:by: 0.1))` in the capsule).
- No audio data leaves the tap except this single number.

### 6. First run: one window, three steps

A single `WindowGroup(id: "first-run")` replaces `onboarding` and `setup`.
- **Layout:** a 520 × 560 window. A step header shows the three steps with the current one highlighted; it's a real sequence, so the step numbers are allowed. Primary actions sit bottom-right, Back bottom-left.
- **Permissions:** the existing permission logic, restyled.
- **Models:**
  - A "Recommended for this Mac (36 GB)" block naming the speech and cleanup models, their total size and one line each.
  - "Choose models myself" reveals the full lists as selectable rows, with the selection shown by the `ai` tint and a checkmark.
  - A single Download button, then per-model progress ("Downloading Parakeet, 214 of 600 MB").
- **Try it:**
  - It sets `AppState.firstRunTestActive = true`. The pipeline then skips paste and history, and writes the result to `AppState.firstRunTestTranscript`, which is shown in serif.
  - The step shows the keycap, which reacts live.
  - "Start using Honyaku" finishes setup and closes the window.

`MenuBarPopoverView.showRequiredWindowIfNeeded` opens `first-run` at the first incomplete step.

### 7. Settings

The `Settings { SettingsView() }` scene is a `TabView` with the five tabs. The Settings button calls `SettingsLink` (macOS 14), or `openSettings` where available. Each tab is a `Form(.grouped)` sized to its content, about 500 pt wide.
- **Models tab:** rows show the name, one plain line, size, and state: Active, Use, Download (with size), Downloading (progress) or Delete. Model state comes from `ModelInstaller` after rebase; until then, from the existing `ModelStore`/`ModelDownloader` calls, kept thin.
- **History tab:** a search field over `cleanedText`, case- and diacritic-insensitive (see Implementation notes); per-row copy and delete; "Delete all history…" with a confirmation dialog.

### 8. Settings apply live

Settings writes `@AppStorage` behind `AppState`'s back, while the pipeline reads `AppState`'s in-memory copies of the speech model, cleanup on/off and speaker labels. So those only change after a relaunch. The cleanup model and prompt are already read from `UserDefaults` on every dictation, so they already apply live.

The fix: the Settings views and first run bind to `AppState` (`@Bindable`) instead of `@AppStorage`. `AppState`'s existing `didSet`s persist each value, and the prompt gets the same property and persistence. The pipeline and the model services are untouched, which keeps `model-upgrade`'s rewrite of `CleanupService` and `TranscriptionService` free of conflicts.

### 9. Working alongside `model-upgrade`

- This change doesn't touch `ModelRegistry`, the model services or `project.yml` dependencies.
- It uses `ModelRegistry.default*ModelID` for the recommendation until `model-upgrade` lands `ModelRegistry.recommended(forPhysicalMemory:)`. Rebasing then swaps one call.
- The download calls stay in the views as they are today, thin, and move to `ModelInstaller` on rebase.

## Implementation notes (decisions made while building)

- **Keycap:**
  - At 48 pt and above (the Try it step), the keycap also shows a "control" legend, as on a real Mac key. At small sizes the ⌃ glyph alone read as a chevron in the renders.
  - The busy state is only a dimmed glyph. A spinner on the key's corner duplicated the "Transcribing…" text beside it and cluttered the key.
- **Popover rows:** show copy and delete icons on hover, without a hover tint (removed on review as the one accessory too many).
- **History search:** a plain search field above the list, not `.searchable`. A macOS Settings tab has no toolbar for `.searchable` to attach to.
- **Models tab:** until `ModelInstaller` lands, disk usage and Delete are shown for cleanup models only. Speech models live in WhisperKit's own folder, not Honyaku's store, so `ModelStore` can't size or delete them.
- **Accessibility permission:** macOS picks up the grant while the app is running, so first run no longer claims a restart is required. After the user has been sent to System Settings, the row offers Relaunch alongside Open Settings, for when the grant still isn't detected.
- **Opening first run:** the menu bar label, which renders at launch, opens the first-run `Window` when a permission is missing or setup is incomplete. The popover still does this too.
- **Order of steps:** the Models step sets `setupComplete` after downloading, so the pipeline and Control listener start before the Try it step. This goes through the label's `onChange(of: setupComplete)`, because the popover's handler only runs while it's open.
- **Test data:** `TranscriptStore(inMemory:)` gives a store that never reads or writes `history.json`, used by the new tests and the design renders.

## Risks / Trade-offs

- **[Risk] `NSPanel` over a full-screen app, or in Stage Manager.** → `fullScreenAuxiliary` plus `canJoinAllSpaces`. Verify by hand in a full-screen app.
- **[Risk] Level updates on the main thread every ~33 ms, during recording only.** → Throttled, one `Double`, no allocations.
- **[Risk] Rebasing onto `model-upgrade` conflicts in `SetupWizardView`/`SettingsView`.** → This change replaces those views wholesale, so on conflict take this version and re-apply `ModelInstaller` calls.
- **[Trade-off] Serif transcripts may look unexpected in a utility app.** → Deliberate: it separates the user's words from the chrome. Easy to revert in `Theme.swift` if it tests poorly.
