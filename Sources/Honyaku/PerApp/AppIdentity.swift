import AppKit
import SwiftUI

/// An installed app's name and icon, looked up by bundle ID. An app that's no longer installed shows its
/// bundle ID and a generic icon.
@MainActor
struct AppIdentity {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isInstalled: Bool

    private static var cache: [String: AppIdentity] = [:]

    static func of(bundleID: String) -> AppIdentity {
        if let cached = cache[bundleID] { return cached }
        let identity: AppIdentity
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            identity = AppIdentity(bundleID: bundleID, name: displayName(of: url),
                                   icon: NSWorkspace.shared.icon(forFile: url.path), isInstalled: true)
        } else {
            identity = AppIdentity(bundleID: bundleID, name: bundleID,
                                   icon: NSWorkspace.shared.icon(for: .application), isInstalled: false)
        }
        cache[bundleID] = identity
        return identity
    }

    static func displayName(of appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// The app a History entry went to, and whether it was pasted. Nothing for older entries.
struct HistoryAppLabel: View {
    let entry: TranscriptEntry

    var body: some View {
        if entry.appBundleID != nil || entry.pasted == false {
            VStack(alignment: .trailing, spacing: 2) {
                if let bundleID = entry.appBundleID {
                    let app = AppIdentity.of(bundleID: bundleID)
                    HStack(spacing: 4) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text(app.name)
                            .lineLimit(1)
                    }
                }
                if entry.pasted == false {
                    Text("Not pasted")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        let name = entry.appBundleID.map { AppIdentity.of(bundleID: $0).name }
        switch (name, entry.pasted == false) {
        case (let name?, true): return "Saved for \(name), not pasted"
        case (let name?, false): return "Pasted into \(name)"
        case (nil, _): return "Not pasted"
        }
    }
}
