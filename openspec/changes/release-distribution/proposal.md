## Why

Honyaku v1.0.0 can't ship to users yet. Distributing a macOS app outside the App Store requires a Developer ID signature and Apple notarisation; otherwise Gatekeeper blocks the app, and every update resets the user's Accessibility and Microphone grants. These tasks were split out of `honyaku-macos-app` §14 so that change could be archived. They're blocked on enrolling in the paid Apple Developer Program.

A draft release pipeline already exists, uncommitted, in the `release/distribution-pipeline` worktree (`../honyaku.release-distribution-pipeline`):
- `.github/workflows/release.yml` (sign, notarise, DMG, GitHub Release)
- `scripts/build-dmg.sh`
- a Release signing block in `project.yml`

## What Changes

- Release builds are signed with a Developer ID Application certificate.
- CI notarises and staples both the app and the DMG.
- A drag-to-Applications DMG is built.
- Tagged releases publish the DMG to GitHub Releases.

## Capabilities

### New Capabilities
- `distribution`: how release builds are signed, notarised, packaged and published.

### Modified Capabilities
<!-- none -->

## Impact

- **Build config:** `project.yml` Release signing. This will conflict slightly with the Debug xcconfig changes from PR #1.
- **CI:** a new `.github/workflows/release.yml`, and a new `scripts/build-dmg.sh`.
- **Secrets (GitHub):** `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`.
- **Prerequisite:** a paid Apple Developer Program membership.
