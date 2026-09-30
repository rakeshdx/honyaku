## Why

Honyaku's job is invisible: hold Control, talk, and the text appears where you're typing. The UI's job is to give you confidence: that it's listening, what it heard, and where the text went. Today's UI doesn't do that:
- **Popover:**
  - It hides the Control hint once history exists.
  - Its only recording feedback is a pulsing menu bar icon.
  - It deletes all history in one click with no confirmation.
  - Its timestamps read "2 hr, 43 min".
- **Setup:** a wall of nine options in identical grey cards, with stale timing copy and no recommendation for the user's Mac.
- **Onboarding:** a separate window from setup, although it's the same sequence.
- **Settings:**
  - A custom window with seven thin sections.
  - The system prompt is exposed up front.
  - "Use" appears for models that aren't downloaded.
  - Model changes don't reach the running app until relaunch.

The visual language is the stock SwiftUI card kit, competent but anonymous.

## What Changes

- **A new visual identity**, native first: system materials and controls, one indigo accent (藍, *ai*), transcripts set in the New York serif, and the Control keycap as the single signature element.
- **No popover:** clicking the menu bar icon opens Settings (or first run while it's needed); right-clicking shows "Settings…" and "Quit Honyaku". The popover was built first and then dropped after trying it, because its history duplicated Settings > History (design Decision 11).
- **New floating recording capsule:** a non-activating panel at the bottom centre of the screen, shown only while dictating. It has live input levels and elapsed time, then "Transcribing…", then fades after the paste. It respects Reduce Motion and never takes focus.
- **First run in one window, three steps:**
  1. Permissions.
  2. Models: one recommended set for the Mac's memory, with "Choose models myself" to see every option.
  3. A live test: hold Control and say something.
- **One native Settings window** with toolbar tabs:
  - **General:** a status card (the keycap, the state or the full error, the active models, background downloads), launch at login, microphone, permissions.
  - **Models:** download state, disk used, delete.
  - **Dictation:** cleanup, speaker labels, the dictation language, the prompt under Advanced.
  - **History:** search, copy and delete per row, delete all with confirmation.
  - **Privacy:** the offline guarantees, and the Hugging Face token under Advanced.
- **Fixes:**
  - Settings changes to models, cleanup and speaker labels apply straight away, without relaunching.
  - "Use" only appears for downloaded models.
  - From the branch review (design Decision 12):
    - A Try it dictation can't leak into a paste after first run closes.
    - Honyaku never pastes into itself.
    - Control-click no longer opens the menu.
    - Clicking the icon no longer clears errors.
    - The capsule survives a quick re-press.
    - A minimised window is restored as it was.
    - Dark-mode contrast and VoiceOver fixes.
    - The Models tab no longer walks the disk while drawing.

## Capabilities

### New Capabilities
<!-- none: every change lands in an existing capability -->

### Modified Capabilities
- `menu-bar-app`:
  - The icon opens Settings (the popover requirement is renamed and rewritten).
  - Settings is a single window (renamed from "accessible from the popover").
  - Onboarding is merged into first run, with the Try it rules.
  - History deletion moves behind a confirmation.
  - The icon's states and VoiceOver value.
  - `MenuBarExtra` is no longer named.
- `push-to-talk`: the visual recording indicator becomes the floating capsule, with levels and elapsed time. The listener retry and the Accessibility warning move from the popover to the icon.
- `text-cleanup`: the paste is skipped (saved to history instead) when Honyaku is in front; errors show on the icon and in Settings rather than the popover.
- `speech-transcription`: the microphone-disconnect notice moves from the popover to the icon, capsule and Settings.
- `testing`: the XCUITests cover the icon, the one Settings window and the right-click menu, and set up their own state.
- `model-management`:
  - ADDED requirements for the recommended first-run preset, model changes applying without relaunch, and removing retired model files.
  - MODIFIED `model-upgrade`'s migration requirement so its download progress shows in Settings, not the popover. Archive `model-upgrade` first.

## Impact

- **Views:** new `Sources/Honyaku/Views/` for first run (replacing the separate `OnboardingView` and `SetupWizardView` windows), the Settings tabs and a recording capsule panel. There's also a small theme file for colours and type. `MenuBarPopoverView` is removed.
- **App:** an `AppCoordinator` (through `NSApplicationDelegateAdaptor`) owns the state and wiring, an `NSStatusItem`, and single AppKit windows for Settings and first run.
- **Services:**
  - `AudioCaptureService` publishes an input level while recording, computed on the audio thread and throttled to about 30 Hz on the main thread.
  - `AppState` gains the level and the elapsed time.
- **Parallel work:** `model-upgrade` (in a separate worktree) moves model downloading into a `ModelInstaller` service. This change keeps its download calls thin, and adopts `ModelInstaller` when it rebases after `model-upgrade` merges.
- **Tests:**
  - Unit tests for the recommended-preset logic, history search, retired model files, the Try it and paste routing, the first-run step logic, and installer progress fan-out.
  - The XCUITest target (`HonyakuUITests` scheme) gets menu bar icon and Settings smoke tests.

## Out of scope / follow-ups

- Share the download, progress and error code that `ModelsStep` and `ModelSettingsRow` each have.
- Split `FirstRunView.swift` and `SettingsView.swift`, and move `ModelCopy`, `NSApplication.relaunch()` and `RetiredModelFiles` into their own files.
- A way back into Settings when macOS hides the menu bar icon (for example, a crowded menu bar or a menu bar manager): reopening the app from Finder or Spotlight could open Settings.
- UI tests still to write, from the testing spec: the "Delete all history…" confirmation, Launch at Login persisting, and first run when Accessibility is missing.
