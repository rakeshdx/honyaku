## 1. Single-instance enforcement

- [x] 1.1 Add a `RunningInstanceProviding` protocol to `ServiceProtocols.swift` that lists other running instances by bundle ID and exposes terminate / force-terminate / isTerminated
- [x] 1.2 Implement `SingleInstanceService` in `Sources/Honyaku/Services/SingleInstanceService.swift`: exclude the current PID, gracefully terminate older instances, poll for up to 3 s, force-terminate any that remain
- [x] 1.3 Run the single-instance check at launch and make `startPipelineIfReady()` await it before calling `hotkeyService.start()`, returning immediately when no other instance exists
- [x] 1.4 Add `HonyakuTests/SingleInstanceServiceTests.swift`: no other instances (no-op), older instances terminated gracefully, force-terminate after timeout, current PID never terminated

## 2. Relaunch

- [x] 2.1 Rewrite `NSApplication.relaunch()` in `OnboardingView.swift` to start a detached `/bin/sh` that waits for the current PID to exit, then runs `/usr/bin/open -n` on the bundle path (PID and path passed as positional args), then call `terminate(nil)`

## 3. Login item

- [x] 3.1 Skip `registerLoginItemIfNeeded()` under `#if DEBUG` in `HonyakuApp.swift`; leave the Settings "Launch at Login" toggle unchanged

## 4. Debug signing

- [x] 4.1 Add `Config/Debug.xcconfig` (ad-hoc defaults + `#include? "Local.xcconfig"`) and `Config/Local.xcconfig.example` (Automatic, Apple Development, `DEVELOPMENT_TEAM = <TEAMID>`)
- [x] 4.2 Add `Config/Local.xcconfig` to `.gitignore`
- [x] 4.3 In `project.yml`, attach `Config/Debug.xcconfig` to the Debug configuration and remove the signing keys from the Honyaku target's `settings.base` that would override it, leaving the Release config block untouched
- [x] 4.4 Regenerate `Honyaku.xcodeproj` with `xcodegen generate` (sequenced with the uncommitted release work per design Open Questions) and confirm the Debug config references the xcconfig

## 5. Documentation

- [x] 5.1 Add a "Development signing" section to `README.md`: add an Apple ID in Xcode, create `Config/Local.xcconfig`, the one-time `tccutil reset Accessibility com.honyaku.app`, and removing stale Debug login items

## 6. Verification (developer, in Xcode)

- [x] 6.1 Developer builds and runs the tests in Xcode; all pass
- [x] 6.2 With `Local.xcconfig` in place, `codesign -dv` on the Debug app shows an Apple Development authority and a team ID
- [x] 6.3 Grant Accessibility, rebuild, run: onboarding shows Accessibility granted without re-granting
- [x] 6.4 With one instance running, Build & Run again: `pgrep -fl Honyaku` shows exactly one process
- [x] 6.5 Click "Quit & Relaunch": exactly one fresh process is running afterwards

## 7. Test gate repairs (found while running the gate; pre-existing on main)

- [x] 7.1 Define `Honyaku`, `HonyakuTests` and `HonyakuIntegrationTests` schemes in `project.yml` (the README referenced schemes that didn't exist); coverage off because instrumented builds fail to link the `yyjson` package
- [x] 7.2 Set `GENERATE_INFOPLIST_FILE: YES` on `HonyakuUITests`, which had no Info.plist and failed to sign
- [x] 7.3 Update `DiarizationIntegrationTests` to the `diarize(audioArray:)` API
