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
- **Popover:**
  - A keycap header that says how to dictate and shows state (pressed and live while recording).
  - The active speech model, and whether cleanup is on.
  - Serif transcript rows with "2m ago" times, with copy and delete on hover or right-click.
  - No one-click delete-all.
- **New floating recording capsule:** a non-activating panel at the bottom centre of the screen, shown only while dictating. It has live input levels and elapsed time, then "Transcribing…", then fades after the paste. It respects Reduce Motion and never takes focus.
- **First run in one window, three steps:**
  1. Permissions.
  2. Models: one recommended set for the Mac's memory, with "Choose models myself" to see every option.
  3. A live test: hold Control and say something.
- **Native Settings window** (⌘,) with five tabs:
  - **General:** launch at login, microphone, permissions.
  - **Models:** download state, disk used, delete.
  - **Dictation:** cleanup, speaker labels, the prompt under Advanced.
  - **History:** search, copy, delete all with confirmation.
  - **Privacy:** the offline guarantees, and the Hugging Face token under Advanced.
- **Fixes:**
  - Settings changes to models, cleanup and speaker labels apply straight away, without relaunching.
  - "Use" only appears for downloaded models.

## Capabilities

### New Capabilities
<!-- none: every change lands in an existing capability -->

### Modified Capabilities
- `menu-bar-app`: the popover's contents; the Settings window structure; onboarding merged into first run; history deletion moved behind a confirmation.
- `push-to-talk`: the visual recording indicator becomes the floating capsule, with levels and elapsed time.
- `model-management`: ADDED requirements only, for the recommended first-run preset and for model changes applying without relaunch. The tier and switching requirements belong to the parallel `model-upgrade` change.

## Impact

- **Views:** new `Sources/Honyaku/Views/` for the popover, first run (replacing the separate `OnboardingView` and `SetupWizardView` windows), Settings tabs, and a recording capsule panel. There's also a small theme file for colours and type.
- **App:** `HonyakuApp.swift` gets a `Settings` scene, a single first-run window, and the capsule panel controller.
- **Services:**
  - `AudioCaptureService` publishes an input level while recording, computed on the audio thread and throttled to about 30 Hz on the main thread.
  - `AppState` gains the level and the elapsed time.
- **Parallel work:** `model-upgrade` (in a separate worktree) moves model downloading into a `ModelInstaller` service. This change keeps its download calls thin, and adopts `ModelInstaller` when it rebases after `model-upgrade` merges.
- **Tests:**
  - Unit tests for the recommended-preset logic, relative-time formatting, history search, and settings propagation.
  - The existing XCUITest target gets popover and Settings smoke tests.
