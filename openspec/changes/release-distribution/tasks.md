## 1. Prerequisites

- [ ] 1.1 Enrol in the Apple Developer Program; create a Developer ID Application certificate
- [ ] 1.2 Add the GitHub secrets listed in the proposal

## 2. Pipeline (moved from honyaku-macos-app §14)

- [ ] 2.1 Configure code signing with the Developer ID Application certificate for Release (was 14.1)
- [ ] 2.2 Notarise the build via `notarytool` in CI (was 14.2)
- [ ] 2.3 Build the DMG installer with a drag-to-Applications layout (was 14.3)
- [ ] 2.4 Publish the first release on GitHub Releases with the DMG attached (was 14.4)
