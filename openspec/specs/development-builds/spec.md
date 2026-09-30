# development-builds Specification

## Purpose
TBD - created by archiving change fix-single-instance-and-accessibility. Update Purpose after archive.
## Requirements
### Requirement: Debug builds use a stable code signature
When the developer has configured a development team in the local, untracked signing configuration, Debug builds SHALL be code-signed with that team's Apple Development identity and SHALL NOT be ad-hoc signed. The code signature's designated requirement SHALL then identify the app by bundle identifier and signing certificate rather than by binary hash, so that macOS privacy grants (TCC) persist across rebuilds. When no team is configured, Debug builds SHALL fall back to ad-hoc signing so the project still builds for contributors without an Apple ID. The README SHALL document the setup and the consequence of the fallback.

#### Scenario: Accessibility grant survives a rebuild
- **GIVEN** a Debug build has been granted Accessibility in System Settings
- **WHEN** the developer changes code, rebuilds, and runs the new Debug build
- **THEN** `AXIsProcessTrusted()` returns true in the new build without re-granting Accessibility

#### Scenario: Debug build signature is not ad-hoc
- **GIVEN** a development team is configured locally
- **WHEN** the developer inspects a Debug build with `codesign -dv`
- **THEN** the signature reports an Apple Development authority and a team identifier, not `Signature=adhoc`

#### Scenario: No development team configured
- **GIVEN** no development team is configured locally
- **WHEN** the developer builds the Debug configuration
- **THEN** the build succeeds with an ad-hoc signature

---

### Requirement: Debug builds do not register a login item
Debug builds SHALL NOT automatically register the app as a login item via `SMAppService` on first launch, so that development copies in DerivedData never launch at login unless the developer turns it on themselves. Release builds SHALL keep the existing launch-at-login-by-default behaviour. The "Launch at Login" toggle in Settings SHALL keep working in both configurations.

#### Scenario: First launch of a Debug build
- **WHEN** a Debug build runs for the first time
- **THEN** no login item is registered for that build

#### Scenario: First launch of a Release build
- **WHEN** a Release build runs for the first time
- **THEN** launch-at-login is enabled via `SMAppService`, as before

