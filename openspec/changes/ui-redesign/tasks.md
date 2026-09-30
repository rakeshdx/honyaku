## 1. Foundations

- [x] 1.1 `Theme.swift`: `ai` and `live` dynamic colours, type helpers (serif transcript, rounded keycap), corner radii; set the app tint
- [x] 1.2 `KeycapView(state:level:)` with idle, recording, transcribing and error states, and the Reduce Motion variant
- [x] 1.3 `AudioCaptureService` RMS level (throttled to 30 Hz) → `AppState.inputLevel`; `AppState.recordingStartedAt`
- [x] 1.4 Settings and first run bind to `AppState` (speech model, cleanup on/off, speaker labels, prompt) instead of `@AppStorage`; no service changes

## 2. Popover

- [x] 2.1 Rebuild `MenuBarPopoverView`: keycap header, model line, serif rows with "2m ago", hover and context-menu Copy and Delete, empty state, error text; remove one-click delete-all
- [x] 2.2 Unit-test the relative-time formatter and single-entry delete in `TranscriptStore`

## 3. Recording capsule

- [x] 3.1 `RecordingCapsuleController` (non-activating `NSPanel`) and `RecordingCapsuleView` (keycap, 12-bar meter, elapsed time, "Transcribing…", short error); 250 ms show delay; fades off under Reduce Motion
- [x] 3.2 Wire it to `AppState.status` from `HonyakuApp`; skip it when hosting tests

## 4. First run

- [x] 4.1 `FirstRunView` with the three-step header; Permissions step (existing logic, restyled)
- [x] 4.2 Models step: recommended block (from the registry defaults until `model-upgrade` lands), "Choose models myself", download progress per model
- [x] 4.3 Try it step: `AppState.firstRunTestActive` routes the result to the window instead of paste and history; "Start using Honyaku"
- [x] 4.4 Replace the `onboarding` and `setup` windows with `first-run`; resume at the first incomplete step

## 5. Settings

- [x] 5.1 `Settings` scene with General, Models, Dictation, History and Privacy tabs; the popover button opens it
- [x] 5.2 Models tab: state per row, "Use" only when downloaded, Delete with the size freed
- [x] 5.3 History tab: `.searchable`, per-row copy and delete, "Delete all history…" with confirmation; unit-test the search filter
- [x] 5.4 Dictation and Privacy tabs, with Advanced disclosures for the prompt and the token

## 6. Verification

- [x] 6.1 Offscreen renders of every screen in light and dark (temporary test, not committed), reviewed against this design
- [ ] 6.2 Unit tests pass; XCUITest smoke test: the popover opens and Settings opens on General
- [ ] 6.3 Developer: dictate into three apps and watch the capsule (levels, "Transcribing…", fade, never steals focus); full-screen app; Reduce Motion on
- [ ] 6.7 Developer: click Settings twice with it open (and press ⌘,); only one Settings window, brought to front; the same for the first-run window
- [ ] 6.4 Developer: fresh first run end to end (reset `setupComplete`), including the live test
- [ ] 6.5 Rebase onto `model-upgrade` once it merges: swap in `ModelInstaller` and `ModelRegistry.recommended(forPhysicalMemory:)`
