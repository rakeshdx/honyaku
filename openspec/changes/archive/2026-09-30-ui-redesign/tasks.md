## 1. Foundations

- [x] 1.1 `Theme.swift`: `ai` and `live` dynamic colours, type helpers (serif transcript, rounded keycap), corner radii; set the app tint
- [x] 1.2 `KeycapView(state:level:)` with idle, recording, transcribing and error states, and the Reduce Motion variant
- [x] 1.3 `AudioCaptureService` RMS level (throttled to 30 Hz) → `AppState.inputLevel`; `AppState.recordingStartedAt`
- [x] 1.4 Settings and first run bind to `AppState` (speech model, cleanup on/off, speaker labels, prompt) instead of `@AppStorage`; no service changes

## 2. Popover (removed in section 7)

- [x] 2.1 Rebuild `MenuBarPopoverView`: keycap header, model line, serif rows with "2m ago", hover and context-menu Copy and Delete, empty state, error text; remove one-click delete-all
- [x] 2.2 Unit-test the relative-time formatter (removed with the popover in 7.5) and single-entry delete in `TranscriptStore`

## 3. Recording capsule

- [x] 3.1 `RecordingCapsuleController` (non-activating `NSPanel`) and `RecordingCapsuleView` (keycap, 12-bar meter, elapsed time, "Transcribing…", short error); 250 ms show delay; fades off under Reduce Motion
- [x] 3.2 Wire it to `AppState.status` (from `HonyakuApp`, now `AppCoordinator`); skip it when hosting tests

## 4. First run

- [x] 4.1 `FirstRunView` with the three-step header; Permissions step (existing logic, restyled)
- [x] 4.2 Models step: recommended block (from the registry defaults until `model-upgrade` lands), "Choose models myself", download progress per model
- [x] 4.3 Try it step: `AppState.firstRunTestActive` routes the result to the window instead of paste and history; "Start using Honyaku"
- [x] 4.4 Replace the `onboarding` and `setup` windows with `first-run`; resume at the first incomplete step

## 5. Settings

- [x] 5.1 General, Models, Dictation, History and Privacy tabs (first as a SwiftUI `Settings` scene; an AppKit window since 7.3)
- [x] 5.2 Models tab: state per row, "Use" only when downloaded, Delete with the size freed
- [x] 5.3 History tab: a search field (not `.searchable`, see design notes), per-row copy and delete, "Delete all history…" with confirmation; unit-test the search filter
- [x] 5.4 Dictation and Privacy tabs, with Advanced disclosures for the prompt and the token

## 6. Verification

- [x] 6.1 Offscreen renders of every screen in light and dark (temporary test, not committed), reviewed against this design
- [x] 6.2 Unit tests pass; XCUITest smoke tests (HonyakuUITests scheme): icon exists, click opens Settings on General, second click keeps one window, right-click shows Quit
- [x] 6.3 Developer: dictate into three apps and watch the capsule (levels, "Transcribing…", fade, never steals focus); full-screen app; Reduce Motion on (full-screen and Reduce Motion not separately confirmed)
- [x] 6.7 Developer: click Settings twice with it open; only one Settings window, brought to front; the same for the first-run window
- [x] 6.4 Developer: fresh first run end to end (reset `setupComplete`), including the live test
- [x] 6.5 Rebase onto `model-upgrade` once it merges: swap in `ModelInstaller` and `ModelRegistry.recommended(forPhysicalMemory:)`; Language picker in the Dictation tab; background download progress (in the popover then, the General tab since 7.4); "Older models" with Move to Trash (design Decision 10)
- [x] 6.8 Unit-test `RetiredModelFiles.onDisk` against a temporary folder (known folders only; missing ones skipped)

## 7. Icon opens Settings (no popover)

- [x] 7.1 `AppCoordinator` via `NSApplicationDelegateAdaptor`: move app state, pipeline, hotkey, capsule and single-instance wiring out of the `App` struct; launch work in `applicationDidFinishLaunching`
- [x] 7.2 `StatusItemController`: state symbol; left click opens Settings (or first run when needed); right-click menu with Settings… and Quit Honyaku
- [x] 7.3 `SettingsWindowController` and `FirstRunWindowController`: single AppKit windows hosting the SwiftUI views; reopening brings the same window forward
- [x] 7.4 General tab status card (keycap, state or full error, model line, background downloads); Models tab shows background download progress
- [x] 7.5 Remove `MenuBarPopoverView` and its tests; renders of the General tab (idle, recording, error, downloading) reviewed
- [x] 7.6 Unit tests pass; developer: left click, right-click menu, Quit, first run while incomplete, one window only, launch-time listener still active

## 8. Review fixes (design Decision 12)

- [x] 8.1 Try it routing: the test session is captured at recording start; ended on Skip, Start, `onDisappear` and window close; a stale test dictation is discarded; unit tests for `TranscriptionPipeline.destination`
- [x] 8.2 Paste guard: save to history without ⌘V when Honyaku is in front, with "Saved to History — Honyaku was in front"; unit test
- [x] 8.3 Status item: right-click only opens the menu; accessibility value names the state; unit tests (including `.processing`)
- [x] 8.4 `firstIncompleteStep`/`isNeeded` pure overloads; Permissions whenever the microphone or Accessibility is missing; unit tests
- [x] 8.5 A click on the icon clears only the listener error it set; `launch()` and `observeState` apply state once
- [x] 8.6 Capsule: cancel a fade when recording starts, re-centre on width changes, `sharingType = .none`
- [x] 8.7 Minimised Settings and first-run windows are restored, not rebuilt
- [x] 8.8 Contrast: `aiFill` for prominent buttons and the step number; busy glyph colour; darker level fill; dark `live`
- [x] 8.9 Models tab: `ModelInstallStates` cache; Older models computed on appear and after Move to Trash; failures shown
- [x] 8.10 `ModelInstaller` fans progress out to joiners; unit test
- [x] 8.11 History rows: visible Copy and Delete buttons; model choice rows carry the selected trait
- [x] 8.12 Copy: "Set up Honyaku", "Open System Settings", "In use", the 16 GB note, actionable errors, the Older models footer, Save token failure; token hidden on disappear
- [x] 8.13 Theme: 15 pt semibold step titles, 1.3 transcript line height, `controlRadius` removed
- [x] 8.14 UI tests: `-HonyakuUITestSetupComplete` (Debug only); fail when the icon is missing; exactly one window
- [x] 8.15 Gates: `xcodegen generate`, clean build with no warnings, unit tests, `HonyakuUITests`, `openspec validate ui-redesign --strict`
- [x] 8.16 Developer: Try it and then close the window mid-dictation (nothing pasted or saved); dictate, then click the icon before the text arrives (saved to History, not pasted into Settings); Control-click the icon (no menu); re-press Control during the capsule's fade; minimise Settings and click the icon; dark-mode buttons
