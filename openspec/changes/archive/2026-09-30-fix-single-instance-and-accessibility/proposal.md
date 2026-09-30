## Why

Two bugs block day-to-day development and can reach users:

1. **Duplicate instances.** Building and running from Xcode while another copy is running (started by "Quit & Relaunch", by the login item, or by an earlier launch outside Xcode) leaves two Honyaku processes alive. Each installs its own CGEventTap on the Control key, which risks double recordings and double pastes.
2. **The Accessibility grant is never recognised.** Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`). macOS ties the Accessibility grant to that exact binary hash, so every rebuild looks like a brand-new app. The existing "Honyaku" entry in System Settings belongs to an earlier build, so the onboarding screen keeps showing Accessibility as missing, even after a grant and relaunch.

A buggy relaunch helper makes both worse. `NSApplication.relaunch()` runs `open <bundlePath>` while the app is still running, so it can just bring the dying process to the front instead of starting a fresh one. Separately, the login item registers whatever build is running, including the Debug build in DerivedData.

## What Changes

- Only one copy of Honyaku runs at a time. When a new copy launches, it gracefully terminates any older copies ("newest wins").
- "Quit & Relaunch" waits for the current process to exit, then starts a fresh copy. This leaves exactly one instance running, and it re-reads the permission state.
- Debug builds are signed with a stable Apple Development identity (Automatic signing, the developer's team). The Accessibility grant then survives rebuilds.
- Debug builds do not register themselves as a login item. Release builds keep the existing launch-at-login-by-default behaviour.
- The checked-in `Honyaku.xcodeproj` is regenerated from `project.yml` so it matches.

Out of scope: the uncommitted v1.0.0 release work (Release signing config, `.github/workflows/release.yml`, `scripts/build-dmg.sh`, and the task ticks for `honyaku-macos-app` §14).

## Capabilities

### New Capabilities
- `development-builds`: how Debug builds are signed and how they behave, so the Accessibility grant lasts across rebuilds and Debug builds don't install a login item.

### Modified Capabilities
- `menu-bar-app`: adds single-instance enforcement and a correct "Quit & Relaunch". These are written as ADDED requirements, because the `menu-bar-app` base spec only exists in the unarchived `honyaku-macos-app` change. That change should be archived first.

## Impact

- **Code:** `Sources/Honyaku/App/HonyakuApp.swift` (single-instance check at launch; login item skipped in Debug), `Sources/Honyaku/Views/OnboardingView.swift` (the `NSApplication.relaunch()` extension).
- **Build config:** `project.yml` Debug signing settings, plus the regenerated `Honyaku.xcodeproj/project.pbxproj`.
- **Developer prerequisite:** an Apple ID added in Xcode → Settings → Accounts (a free personal team is enough) so that an Apple Development certificate exists. No signing identities are installed on the dev Mac today.
- **One-time migration:** after the first stably signed build, the old Honyaku entry in Accessibility must be removed (or `tccutil reset Accessibility com.honyaku.app`) and the grant given again.
- **Dependencies:** none added.
