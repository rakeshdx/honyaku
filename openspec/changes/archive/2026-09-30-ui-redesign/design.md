## Context

*This section describes the app before this change.*

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

**Colour:** system backgrounds and materials throughout (`.regularMaterial` in the capsule; standard window backgrounds elsewhere), plus two named colours defined as dynamic `NSColor`s in `Theme.swift`:

| Token | Light | Dark | Used for |
|---|---|---|---|
| `ai` (indigo accent) | `#2E4A7D` | `#8FA8D8` | the app's `.tint`, the selected state, the keycap glyph while idle |
| `aiFill` | `#2E4A7D` | `#3D5A96` | fills behind white text: prominent buttons, the current step number (Decision 12) |
| `live` | `#E0484F` | `#E5484D` | the keycap and level meter while recording, and nothing else (dark value darkened in Decision 12; was `#FF6B6B`) |

Text, dividers and fills use the system `.primary`, `.secondary`, `.tertiary` and `.separator`, so contrast follows the system, including Increase Contrast.

**Type:**
- **SF Pro** (system) for all interface text, at macOS sizes: body 13, callout 12, caption 11, title 15 semibold.
- **New York** (`.system(design: .serif)`), 14 pt with 1.3 line spacing, for transcript text only, in the History tab and the live-test result.
- **SF Pro Rounded**, medium, for the ⌃ glyph on the keycap.
- Sentence case everywhere: no all-caps labels, no eyebrows.

**Shape:** 10 pt corners for panels, and the capsule is fully rounded. Controls keep the system's own corner radius (the unused 6 pt `controlRadius` token was removed in Decision 12). There are no drop shadows except the capsule's system panel shadow.

### 2. The keycap component (the signature)

`KeycapView(state:level:)` is a 34 × 34 pt rounded square drawn like a physical key: a face, a 1 pt lighter top edge and a 2 pt darker bottom lip.

| State | Appearance |
|---|---|
| Idle | an `ai` glyph on a quiet face |
| Recording | pressed: the face moves down 1 pt and the lip shrinks; tinted `live`; a level fill rises from the bottom of the face |
| Transcribing | the glyph dims, with a small indeterminate ring |
| Error | a system-orange edge |

It's used in the capsule, first run (the live test) and Settings > General (the popover header too, until Decision 11). The only animation is the press or release (0.12 s spring) and the level fill (driven by the level, not a timer). With Reduce Motion, the press is a colour change only.

### 3. Popover layout (340 pt wide)

> **Superseded by Decision 11:** there is no popover; the icon opens Settings. Kept for the record.

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

> **Partly superseded:** the window is an AppKit `HostedWindow` (Decision 11), titled "Set up Honyaku"; the Try it flag works as in Decision 12.

A single first-run window replaces `onboarding` and `setup`.
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

The app opens first run at its first incomplete step: at launch when it's needed, and from the menu bar icon (Decision 11).

### 7. Settings

> **Superseded in part by Decision 11:** Settings is an AppKit window with toolbar tabs, not a SwiftUI `Settings` scene, and it opens from the menu bar icon rather than ⌘, or `SettingsLink`. The installed model shows "In use" (not "Active").

The `Settings { SettingsView() }` scene is a `TabView` with the five tabs. The Settings button calls `SettingsLink` (macOS 14), or `openSettings` where available. Each tab is a `Form(.grouped)` sized to its content, about 500 pt wide.
- **Models tab:** rows show the name, one plain line, size, and state: In use, Use, Download (with size), Downloading (progress) or Delete. Model state comes from `ModelInstaller` after rebase; until then, from the existing `ModelStore`/`ModelDownloader` calls, kept thin.
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
- **Popover rows** (removed with the popover in Decision 11): showed copy and delete icons on hover, without a hover tint.
- **History search:** a plain search field above the list, not `.searchable`. A macOS Settings tab has no toolbar for `.searchable` to attach to.
- **Models tab:** until `ModelInstaller` lands, disk usage and Delete are shown for cleanup models only. Speech models live in WhisperKit's own folder, not Honyaku's store, so `ModelStore` can't size or delete them.
- **Accessibility permission:** macOS picks up the grant while the app is running, so first run no longer claims a restart is required. After the user has been sent to System Settings, the row offers Relaunch alongside Open System Settings, for when the grant still isn't detected.
- **Opening first run** (before Decision 11): the menu bar label, which renders at launch, opened the first-run `Window` when a permission was missing or setup was incomplete.
- **Order of steps:** the Models step sets `setupComplete` after downloading, so the pipeline and Control listener start before the Try it step. Since Decision 11 this goes through `AppCoordinator`'s observation of `setupComplete`.
- **Test data:** `TranscriptStore(inMemory:)` gives a store that never reads or writes `history.json`, used by the new tests and the design renders.

### 10. After rebasing onto `model-upgrade` (task 6.5)

- **Downloads:** first run and the Settings Models tab install through `ModelInstaller`: one install per model at a time, a completeness check for every engine, and a compile at install time. Rows show the real size on disk for every model type, "Resume download" for an interrupted download, and Delete for any installed model that isn't in use.
- **Recommendation:** first run preselects `ModelRegistry.recommended(forPhysicalMemory:)`.
- **Language:** the Dictation tab has the Language picker (Auto-detect or a Whisper language), disabled with an explanation when the selected speech model is English-only.
- **Download progress:** background model downloads (`AppState.modelDownloads`, for example after a migration) show as one caption line each, with a slim progress bar in the `ai` tint: under the popover header at first, in the General tab's status card since Decision 11.
- **Older models:** `OlderModelsSection` lists only the known retired folders (Qwen 2.5, Whisper tiny.en, small.en and small), with size, and moves them to the Trash.

### 11. No popover: the icon opens Settings (user decision, after trying the popover)

The popover's history duplicated Settings > History, so the menu bar icon now opens Settings directly.
- **Why AppKit:** SwiftUI's `MenuBarExtra` can't run an action on click; it always shows its own content. On macOS 14, `showSettingsWindow:` through `sendAction` is blocked for SwiftUI `Settings` scenes: only `SettingsLink` or `openSettings` inside a SwiftUI view can open them.
- **`AppCoordinator`** (`@MainActor`, owned through `NSApplicationDelegateAdaptor`) holds what the `App` struct held before:
  - `AppState`, `PermissionManager`, `TranscriptStore`, the hotkey, the pipeline, the capsule and the single-instance service.
  - `applicationDidFinishLaunching` creates the status item, starts the pipeline if setup is ready, and creates the capsule. This replaces the `MenuBarExtra` label's launch hook.
- **`StatusItemController`:**
  - An `NSStatusItem` whose button shows the state symbol (the same `menuBarIcon` mapping, observed from `AppState`).
  - A left click opens Settings, or first run while `FirstRunView.isNeeded`.
  - A right-click pops up an `NSMenu` with "Settings…" and "Quit Honyaku". (Control-click was dropped in Decision 12.)
- **`SettingsWindowController`:** one `NSWindow` whose content is an `NSTabViewController` with `.toolbar` tabs (window `toolbarStyle = .preference`), one `NSHostingController` per tab with the environment injected. Showing it again calls `makeKeyAndOrderFront` and activates the app, so there's never a second window. The controller resizes the window to each tab's preferred size, keeping the title bar in place, and remembers the last tab (`settingsTab`).
- **First run:** hosted by a single `HostedWindow` (titled `FirstRunView.windowTitle`), which is rebuilt each time it's reopened after being closed, so it resumes at the first incomplete step. A minimised window is restored as it was, not rebuilt (Decision 12). It still opens by itself at launch when needed.
- **Scenes:** the SwiftUI `Settings` and `Window` scenes are removed. SwiftUI needs at least one scene, so the `App` body keeps a `MenuBarExtra` with `isInserted: .constant(false)`, which shows nothing. An empty `Settings { EmptyView() }` would add a blank ⌘, window, so it's not used. ⌘, is on the right-click menu's "Settings…" item.
- **Tests:** when the app hosts unit tests (`XCTestConfigurationFilePath`), `launch()` skips the status item, capsule and pipeline.
- **General tab status card:** `KeycapView` plus the state line (the full error text when there is one), the model line, and one line per background download. The slim bar is drawn in `ai`, because a system `ProgressView` turns gray whenever the window isn't key.
- **Models tab:** a row that's downloading in the background shows that progress too.
- **Removed:** `MenuBarPopoverView` and `TranscriptRowView`, and `TimeAgo` (the relative times, used only by the popover) along with its tests. The History tab keeps copy and delete per row, and shows the date and time.


### 12. Review fixes

These came out of the branch review.

- **Try it routing:**
  - `AppState` keeps a first-run test session: `beginFirstRunTest()` starts a new one (with a new number), `endFirstRunTest()` ends it and clears the result.
  - `TranscriptionPipeline.startRecording()` records the session that was active when the recording started. When the text is ready, the pure `TranscriptionPipeline.destination(recordedInTest:currentTest:honyakuIsFrontmost:)` decides where it goes:
    - not started in a test → paste
    - started in the test that is still running → the first-run window
    - started in a test that has since ended or restarted → discarded
  - The test ends from the Try it step's Skip and Start buttons, from its `onDisappear`, and from the first-run window's `windowWillClose` (`HostedWindow`'s `onClose`), so closing the window with the red button can't leave the flag set.
  - Minimising the window doesn't end the test; the result waits in the window.
- **Paste guard:** the same decision returns "save only" when `NSApp.isActive` at paste time. The transcript goes to history, no ⌘V is sent, the clipboard isn't touched, and "Saved to History — Honyaku was in front" is shown the way errors are (icon, capsule, General tab), so it's seen wherever the user looks. The next dictation clears it.
- **Menu:** right-click only. Control is the dictation key, so a Control-click is treated as a left click.
- **First run steps:** `firstIncompleteStep` and `isNeeded` get pure overloads over plain booleans. Missing Accessibility or microphone access is always the Permissions step, even after setup was completed once.
- **Errors aren't cleared by a click:** `startPipelineIfReady` clears only the error it set itself (the Accessibility or listener error), once the listener installs. Other errors wait for the next dictation, as before.
- **Coordinator:**
  - `launch()` no longer calls `startPipelineIfReady()` a second time.
  - `observeState`'s change handler only re-registers, and re-registering applies the state once.
  - Status item, capsule and pipeline start are each applied once per change.
- **Capsule:**
  - Every fade-out carries a generation number. A recording that starts mid-fade bumps it and animates back to full opacity, and the stale fade's completion handler then doesn't `orderOut`.
  - The hosting view reports intrinsic-size changes, and the panel re-centres on the screen it opened on.
  - `sharingType = .none`.
- **Windows:** `NSWindow.bringForward()` deminiaturises before `makeKeyAndOrderFront`. `HostedWindow` rebuilds its content only after a real close (tracked through its window delegate), not when it's merely off screen.
- **Contrast:**
  - Prominent buttons and the current step's number sit on `aiFill`: white on `#2E4A7D` is 8.8:1 in light mode, and white on `#3D5A96` is 6.8:1 in dark mode (white on the old `#8FA8D8` was 2.4:1).
  - The keycap's busy glyph is its own grey-indigo (`#6B7A96` light, 4.3:1 on the white face; `#8A93A5` dark, 3.4:1 on `#3A3F4A`) instead of `ai` at 45% opacity (2.3:1).
  - The recording face's level fill darkens rather than lightens (black 18%), so the white glyph stays above 3:1 over it. `live` in dark mode is `#E5484D` (white on it: about 4:1; on `#FF6B6B` it was 2.8:1).
- **Models tab:**
  - `ModelInstallStates` (an `ObservableObject` owned by the tab) holds each model's `InstallState`, computed off the main thread.
  - It refreshes when the tab appears, after a row's download or delete, and when a background download starts or finishes (the set of `modelDownloads` keys changes). It never refreshes on a progress tick.
  - `OlderModelsSection` computes its list once on appear and again after each Move to Trash.
  - Rows show no buttons until their state is known.
- **Installer progress:** a joiner of an in-flight install adds its progress handler to that install's fan-out, so every caller's progress bar moves, not just the first caller's.
- **Accessibility:**
  - The status item's accessibility value names the state ("Ready", "Recording", "Transcribing", "Cleaning up", or "Error" followed by the message).
  - Model choice rows carry the selected trait.
  - History rows have visible Copy and Delete icon buttons with labels and help tags, and keep the context menu.
- **Copy:**
  - "Set up Honyaku" (sentence case).
  - "Open System Settings" for every button that opens System Settings.
  - "In use" for the active model.
  - The larger cleanup model reads "Most accurate, needs 16 GB of memory".
  - The unused `balanced` and `quality` tier copy is removed.
  - Errors say what to do next, and the Accessibility error no longer says to relaunch, because clicking the icon retries.
  - Move to Trash and Save token failures are shown instead of swallowed.
- **Privacy tab:** the token is hidden again when the tab disappears.
- **Type:** first-run step titles are 15 pt semibold (Decision 1). The transcript line spacing is computed from New York's own line height, so lines sit at 1.3 × 14 pt.
- **UI tests:**
  - Debug builds honour `-HonyakuUITestSetupComplete YES`: setup and permissions count as done for routing, and there's no single-instance takeover, Control listener, capsule or model load.
  - The UI tests use it. They fail when the icon is missing, and assert exactly one window after two clicks.
  - Nothing is written to the user's defaults, except the last Settings tab, which was already saved on every tab change.

## Risks / Trade-offs

- **[Risk] Moving scene state into an `AppCoordinator` touches start-up wiring.** → The pipeline, hotkey and capsule logic are moved as they are. The launch-time checks (listener installed, warm-up, migration downloads) are re-verified by hand.

- **[Risk] `NSPanel` over a full-screen app, or in Stage Manager.** → `fullScreenAuxiliary` plus `canJoinAllSpaces`. Verify by hand in a full-screen app.
- **[Risk] Level updates on the main thread every ~33 ms, during recording only.** → Throttled, one `Double`, no allocations.
- **[Risk] Rebasing onto `model-upgrade` conflicts in `SetupWizardView`/`SettingsView`.** → This change replaces those views wholesale, so on conflict take this version and re-apply `ModelInstaller` calls.
- **[Trade-off] Serif transcripts may look unexpected in a utility app.** → Deliberate: it separates the user's words from the chrome. Easy to revert in `Theme.swift` if it tests poorly.
