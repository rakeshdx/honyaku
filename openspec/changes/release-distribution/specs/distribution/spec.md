## ADDED Requirements

### Requirement: Release builds are signed and notarised
Release builds SHALL be signed with a Developer ID Application certificate, with hardened runtime enabled, and SHALL be notarised by Apple with the notarisation ticket stapled to the app, so that Gatekeeper opens them without warnings.

#### Scenario: User opens a downloaded release
- **WHEN** a user downloads the release DMG and opens Honyaku from Applications
- **THEN** macOS opens it without a Gatekeeper warning

#### Scenario: Permissions survive an update
- **GIVEN** a user has granted Accessibility and Microphone to a previous release
- **WHEN** they install a newer release signed with the same Developer ID
- **THEN** both grants still apply without being granted again

---

### Requirement: Releases are published as a notarised DMG
Pushing a `v*` tag SHALL build a drag-to-Applications DMG, notarise and staple it, and publish it to GitHub Releases, using that version's CHANGELOG section as the release notes.

#### Scenario: Tagging a release
- **WHEN** a maintainer pushes the tag `v1.0.0`
- **THEN** a GitHub Release named "Honyaku v1.0.0" appears, with `Honyaku-v1.0.0.dmg` attached
