import AppKit
import ApplicationServices
import Carbon

enum PasteGuardDecision: Equatable, Sendable {
    case allow
    /// Paste, then say which app has secure input on.
    case warn(ownerPID: pid_t?)
    /// Not pasted, not saved, nothing written to the pasteboard.
    case block
}

/// What the system says about the focused field and secure input, right before a paste.
struct PasteGuardReading: Equatable, Sendable {
    /// The focused element's accessibility subrole; nil when it can't be read.
    var focusedSubrole: String?
    var secureInputOn: Bool
    /// The app that turned secure input on; nil when it's off or the owner is unknown.
    var secureInputOwnerPID: pid_t?
}

enum PasteGuard {
    static let secureTextFieldSubrole = "AXSecureTextField"

    /// The guard's decision (design Decision 1). Fails open: an unreadable field is pasted into.
    static func decide(focusedSubrole: String?, secureInputOwnerPID: pid_t?, secureInputOn: Bool,
                       frontmostPID: pid_t?, frontmostCategory: AppCategory?) -> PasteGuardDecision {
        if focusedSubrole == secureTextFieldSubrole { return .block }
        guard secureInputOn || secureInputOwnerPID != nil else { return .allow }
        if let owner = secureInputOwnerPID, let frontmostPID, owner == frontmostPID {
            // Terminal and iTerm2 "Secure Keyboard Entry" keeps secure input on whenever the terminal is in
            // front; it doesn't mean a password field (decision Q35)
            return frontmostCategory == .terminal ? .allow : .block
        }
        return .warn(ownerPID: secureInputOwnerPID)
    }

    static func decide(_ reading: PasteGuardReading, frontmost: TargetApp?) -> PasteGuardDecision {
        decide(focusedSubrole: reading.focusedSubrole, secureInputOwnerPID: reading.secureInputOwnerPID,
               secureInputOn: reading.secureInputOn, frontmostPID: frontmost?.pid,
               frontmostCategory: frontmost?.category)
    }

    static func warningNotice(ownerName: String?) -> String {
        "Pasted. Note: \(ownerName ?? "another app") has secure input on"
    }
}

/// Reads the focused field and secure-input state. Tests use a fake; only the app reads the system.
@MainActor
protocol PasteGuardProbe {
    func read() -> PasteGuardReading
    /// The name of the app with this PID, for the warning.
    func appName(pid: pid_t) -> String?
}

@MainActor
struct SystemPasteGuardProbe: PasteGuardProbe {
    /// A hung app can't stall the paste for longer than this.
    static let messagingTimeout: Float = 0.25

    func read() -> PasteGuardReading {
        let owner = Self.secureInputOwnerPID()
        return PasteGuardReading(focusedSubrole: Self.focusedSubrole(),
                                 secureInputOn: IsSecureEventInputEnabled() || owner != nil,
                                 secureInputOwnerPID: owner)
    }

    func appName(pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// The subrole of the focused element, read through the system-wide element. Never sets
    /// `AXManualAccessibility` or anything else on other apps: a field that isn't exposed reads as nil.
    static func focusedSubrole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else {
            return nil
        }
        return subrole as? String
    }

    static let secureInputPIDKey = "kCGSSessionSecureInputPID"

    /// The app that turned secure input on: the session dictionary, else IOConsoleUsers in the IORegistry.
    static func secureInputOwnerPID() -> pid_t? {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let pid = (session[secureInputPIDKey] as? NSNumber)?.int32Value, pid > 0 {
            return pid
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        for user in users {
            if let pid = (user[secureInputPIDKey] as? NSNumber)?.int32Value, pid > 0 { return pid }
        }
        return nil
    }
}
