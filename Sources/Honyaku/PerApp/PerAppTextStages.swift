import Foundation

/// Right before routing: blocks the paste when a password field has focus (the groundwork routes
/// `isSecureField` to `.blocked`), or adds a warning when another app has secure input on.
@MainActor
struct PasteGuardStage: TextStage {
    let probe: any PasteGuardProbe

    func apply(_ text: String, context: inout DictationContext) -> String {
        switch PasteGuard.decide(probe.read(), frontmost: context.appAtPaste) {
        case .allow:
            break
        case .block:
            context.isSecureField = true
        case .warn(let ownerPID):
            context.notices.append(PasteGuard.warningNotice(ownerName: ownerPID.flatMap(probe.appName(pid:))))
        }
        return text
    }
}

/// Formats the text for the app it's going to (the app in front at paste time), and turns the paste off
/// for apps set to History only.
@MainActor
struct FormattingStage: TextStage {
    let store: AppProfilesStore

    func apply(_ text: String, context: inout DictationContext) -> String {
        // Honyaku's own window isn't where the text was headed; routing saves it as is
        guard !context.honyakuIsFrontmost else { return text }
        let app = context.appAtPaste
        let profiles = store.profiles
        let rules = profiles.rules(forBundleID: app?.bundleID, category: app?.category ?? .other)
        if !rules.paste {
            context.pasteAllowed = false
            context.pasteOffNotice = "Saved to History. \(Self.name(of: app, in: profiles)) is set not to paste"
        }
        return rules.apply(to: text, protectedTerms: context.speechHints.glossary)
    }

    static func name(of app: TargetApp?, in profiles: AppProfiles) -> String {
        if let bundleID = app?.bundleID, let named = profiles.override(forBundleID: bundleID)?.displayName {
            return named
        }
        return app?.name ?? app?.bundleID ?? "This app"
    }
}
