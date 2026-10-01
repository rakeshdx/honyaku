import Foundation
import Observation
import os

/// One app's own rules, which beat its category's.
struct AppOverride: Codable, Equatable, Identifiable, Sendable {
    var bundleID: String
    var displayName: String
    var rules: FormattingRules

    var id: String { bundleID.lowercased() }
}

/// The user's per-app formatting: categories changed from their defaults, plus apps with their own rules.
struct AppProfiles: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = AppProfiles.currentVersion
    /// Only categories that differ from their defaults, keyed by `AppCategory.rawValue`, so better
    /// built-in defaults reach the user later without a migration.
    var categories: [String: FormattingRules] = [:]
    var apps: [AppOverride] = []

    init(categories: [String: FormattingRules] = [:], apps: [AppOverride] = []) {
        self.categories = categories
        self.apps = apps
    }

    func rules(for category: AppCategory) -> FormattingRules {
        categories[category.rawValue] ?? FormattingRules.defaults(for: category)
    }

    /// The app's own rules if it has an override, else its category's. An app with no bundle ID counts as
    /// Everything else.
    func rules(forBundleID bundleID: String?, category: AppCategory) -> FormattingRules {
        guard let bundleID else { return rules(for: .other) }
        return override(forBundleID: bundleID)?.rules ?? rules(for: category)
    }

    func override(forBundleID bundleID: String) -> AppOverride? {
        apps.first { $0.id == bundleID.lowercased() }
    }

    func isChanged(_ category: AppCategory) -> Bool { categories[category.rawValue] != nil }

    mutating func setRules(_ rules: FormattingRules, for category: AppCategory) {
        categories[category.rawValue] = rules == FormattingRules.defaults(for: category) ? nil : rules
    }

    /// Adds an app with a copy of its category's rules; an app already listed keeps its rules.
    mutating func addApp(bundleID: String, displayName: String) {
        guard override(forBundleID: bundleID) == nil else { return }
        apps.append(AppOverride(bundleID: bundleID, displayName: displayName,
                                rules: rules(for: AppCategory.category(forBundleID: bundleID))))
    }

    mutating func setRules(_ rules: FormattingRules, forApp bundleID: String) {
        guard let index = apps.firstIndex(where: { $0.id == bundleID.lowercased() }) else { return }
        apps[index].rules = rules
    }

    mutating func removeApp(bundleID: String) {
        apps.removeAll { $0.id == bundleID.lowercased() }
    }
}

/// `app-profiles.json`: read once, written only when the user changes a rule. A damaged file is moved aside
/// (`app-profiles.damaged-<date>.json`) and the Apps tab says so; one that can't be moved, or comes from a
/// newer version, is never saved over. Shared by the pipeline's formatting stage and the Apps tab.
@Observable
@MainActor
final class AppProfilesStore: FeatureStore {
    static let fileName = "app-profiles.json"

    /// Setting this saves the file, unless saving is blocked (see `savesToDisk`).
    var profiles: AppProfiles {
        didSet { save() }
    }

    /// Shown in the Apps tab when the file couldn't be used; nil when all is well or once dismissed.
    var fileNotice: String?
    /// False when an unreadable file is still in place (it couldn't be moved aside, or it's from a newer
    /// version): changes then apply until Honyaku quits, and the file is left alone.
    @ObservationIgnored private(set) var savesToDisk = true

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.honyaku.app", category: "AppProfiles")

    convenience init(environment: FeatureEnvironment) {
        self.init(directory: environment.directory)
    }

    /// `fileManager` is injectable so tests can make moving the damaged file fail.
    init(directory: URL, fileManager: FileManager = .default) {
        fileURL = directory.appendingPathComponent(Self.fileName)
        switch Self.load(from: fileURL) {
        case .missing:
            profiles = AppProfiles()
        case .loaded(let loaded):
            profiles = loaded
        case .newerVersion:
            profiles = AppProfiles()
            savesToDisk = false
            fileNotice = "Your app rules were saved by a newer version of Honyaku. Honyaku is using the default rules, and changes here won\u{2019}t be saved."
            log.error("app-profiles.json is from a newer version; using the default rules")
        case .unreadable:
            profiles = AppProfiles()
            setAsideDamagedFile(using: fileManager)
        }
    }

    enum LoadResult: Equatable {
        case missing, loaded(AppProfiles), newerVersion, unreadable
    }

    nonisolated static func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let version = try? JSONDecoder().decode(VersionOnly.self, from: data).version else { return .unreadable }
        guard version <= AppProfiles.currentVersion else { return .newerVersion }
        guard version == AppProfiles.currentVersion,
              let decoded = try? JSONDecoder().decode(AppProfiles.self, from: data) else { return .unreadable }
        return .loaded(decoded)
    }

    private struct VersionOnly: Decodable { var version: Int }

    /// Keeps the unreadable file for the user and starts from the default rules. If it can't be moved, it
    /// stays where it is and is never saved over.
    private func setAsideDamagedFile(using fileManager: FileManager) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "app-profiles.damaged-\(stamp).json"
        do {
            try fileManager.moveItem(at: fileURL, to: fileURL.deletingLastPathComponent().appendingPathComponent(name))
            fileNotice = "Your app rules couldn\u{2019}t be read. They were saved as \(name), and Honyaku is using the default rules."
            log.error("app-profiles.json couldn't be read; moved aside and using the default rules")
        } catch {
            savesToDisk = false
            fileNotice = "Your app rules couldn\u{2019}t be read, and Honyaku couldn\u{2019}t move the file aside. Honyaku is using the default rules, and changes here won\u{2019}t be saved until app-profiles.json is fixed or removed."
            log.error("app-profiles.json couldn't be read or moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard savesToDisk else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = fileURL
            try url.setResourceValues(values)
        } catch {
            // Operational metadata only, never content
            log.error("Couldn't save app-profiles.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
