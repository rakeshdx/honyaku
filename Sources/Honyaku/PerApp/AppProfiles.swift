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

/// `app-profiles.json`: read once, written only when the user changes a rule, so a damaged file is left
/// alone until then. Shared by the pipeline's formatting stage and the Apps tab.
@Observable
@MainActor
final class AppProfilesStore: FeatureStore {
    static let fileName = "app-profiles.json"

    /// Setting this saves the file.
    var profiles: AppProfiles {
        didSet { save() }
    }

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.honyaku.app", category: "AppProfiles")

    convenience init(environment: FeatureEnvironment) {
        self.init(directory: environment.directory)
    }

    init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
        profiles = Self.load(from: fileURL)
    }

    /// The saved profiles, or the defaults when the file is missing, unreadable or from a newer version.
    nonisolated static func load(from url: URL) -> AppProfiles {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppProfiles() }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppProfiles.self, from: data),
              decoded.version == AppProfiles.currentVersion else {
            Logger(subsystem: "com.honyaku.app", category: "AppProfiles")
                .error("app-profiles.json couldn't be read; using the default rules")
            return AppProfiles()
        }
        return decoded
    }

    private func save() {
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
