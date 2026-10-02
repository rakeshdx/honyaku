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
    /// The process of the element with keyboard focus, where ⌘V goes; nil when it can't be read.
    var focusedPID: pid_t?
    /// That process's category, so a terminal's own secure input is still ignored.
    var focusedCategory: AppCategory?

    init(focusedSubrole: String?, secureInputOn: Bool, secureInputOwnerPID: pid_t?, focusedPID: pid_t? = nil,
         focusedCategory: AppCategory? = nil) {
        self.focusedSubrole = focusedSubrole
        self.secureInputOn = secureInputOn
        self.secureInputOwnerPID = secureInputOwnerPID
        self.focusedPID = focusedPID
        self.focusedCategory = focusedCategory
    }
}

enum PasteGuard {
    static let secureTextFieldSubrole = "AXSecureTextField"

    /// The guard's decision (design Decision 1). Fails open: an unreadable field is pasted into.
    /// The owner of secure input counts as the receiving app when it's the app in front or the app whose
    /// element has keyboard focus (a dialog from another process, say), since that's where ⌘V goes.
    static func decide(focusedSubrole: String?, secureInputOwnerPID: pid_t?, secureInputOn: Bool,
                       frontmostPID: pid_t?, frontmostCategory: AppCategory?,
                       focusedPID: pid_t? = nil, focusedCategory: AppCategory? = nil) -> PasteGuardDecision {
        if focusedSubrole == secureTextFieldSubrole { return .block }
        guard secureInputOn || secureInputOwnerPID != nil else { return .allow }
        if let owner = secureInputOwnerPID {
            // Terminal and iTerm2 "Secure Keyboard Entry" keeps secure input on whenever the terminal is in
            // front; it doesn't mean a password field (decision Q35)
            if let frontmostPID, owner == frontmostPID { return frontmostCategory == .terminal ? .allow : .block }
            if let focusedPID, owner == focusedPID { return focusedCategory == .terminal ? .allow : .block }
        }
        return .warn(ownerPID: secureInputOwnerPID)
    }

    static func decide(_ reading: PasteGuardReading, frontmost: TargetApp?) -> PasteGuardDecision {
        decide(focusedSubrole: reading.focusedSubrole, secureInputOwnerPID: reading.secureInputOwnerPID,
               secureInputOn: reading.secureInputOn, frontmostPID: frontmost?.pid,
               frontmostCategory: frontmost?.category, focusedPID: reading.focusedPID,
               focusedCategory: reading.focusedCategory)
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
    /// All of the probe's accessibility calls share this budget, so a hung app can't stall the paste (or the
    /// main thread it runs on) for longer than about this.
    static let budget: Double = 0.25
    /// Below this, the second call isn't worth starting; the subrole reads as unknown (fail open).
    static let minimumCallTime: Double = 0.02

    func read() -> PasteGuardReading {
        // The owner is only looked up while secure input is on, so an ordinary paste skips the lookup
        let secureInputOn = IsSecureEventInputEnabled()
        let owner = secureInputOn ? Self.secureInputOwnerPID() : nil
        let focused = Self.focusedElement(budget: Self.budget)
        let category = focused.pid
            .flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            .map(AppCategory.category(forBundleID:))
        return PasteGuardReading(focusedSubrole: focused.subrole, secureInputOn: secureInputOn,
                                 secureInputOwnerPID: owner, focusedPID: focused.pid, focusedCategory: category)
    }

    func appName(pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// The subrole and process of the element with keyboard focus, read through the system-wide element so
    /// a dialog from another process counts. Never sets `AXManualAccessibility` or anything else on other
    /// apps: a field that isn't exposed reads as nil.
    ///
    /// On the system-wide element a messaging timeout applies to the whole process, so it's set to the
    /// budget for this one call and reset to the default (0) straight after. The second call uses the
    /// element's own timeout with whatever is left.
    static func focusedElement(budget: Double) -> (subrole: String?, pid: pid_t?) {
        let started = Date()
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Float(budget))
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        AXUIElementSetMessagingTimeout(systemWide, 0)
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (nil, nil) }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        let focusedPID: pid_t? = AXUIElementGetPid(element, &pid) == .success && pid > 0 ? pid : nil
        let remaining = budget - Date().timeIntervalSince(started)
        guard remaining >= minimumCallTime else { return (nil, focusedPID) }
        AXUIElementSetMessagingTimeout(element, Float(remaining))
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else {
            return (nil, focusedPID)
        }
        return (subrole as? String, focusedPID)
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
