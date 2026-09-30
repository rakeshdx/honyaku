import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var status: AppStatus = .idle
    var lastError: String?

    // Feature toggles (backed by UserDefaults via AppStorage in views,
    // mirrored here for pipeline access).
    // Use object(forKey:) so a missing key returns nil and the ?? default applies correctly.
    // UserDefaults.bool(forKey:) always returns false for missing keys, ignoring register(defaults:)
    // when AppState is initialized before HonyakuApp.init() calls register().
    var cleanupEnabled: Bool = (UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }
    var diarizationEnabled: Bool = (UserDefaults.standard.object(forKey: "diarizationEnabled") as? Bool) ?? false {
        didSet { UserDefaults.standard.set(diarizationEnabled, forKey: "diarizationEnabled") }
    }

    // Selected model IDs — retired models are migrated to their replacement on first read
    var selectedSpeechModelID: String = AppState.resolvedSelection(
        key: "selectedSpeechModelID", fallback: ModelRegistry.defaultSpeechModelID) {
        didSet { UserDefaults.standard.set(selectedSpeechModelID, forKey: "selectedSpeechModelID") }
    }
    var selectedCleanupModelID: String = AppState.resolvedSelection(
        key: "selectedCleanupModelID", fallback: ModelRegistry.defaultCleanupModelID) {
        didSet { UserDefaults.standard.set(selectedCleanupModelID, forKey: "selectedCleanupModelID") }
    }

    // Setup state
    var setupComplete: Bool = UserDefaults.standard.bool(forKey: "setupComplete") {
        didSet { UserDefaults.standard.set(setupComplete, forKey: "setupComplete") }
    }

    /// Reads a saved model selection, migrating a retired ID and writing the result back so services
    /// that read UserDefaults directly (CleanupService) see the same model.
    nonisolated static func resolvedSelection(key: String, fallback: String,
                                              defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: key)
        let resolved = ModelRegistry.resolvedID(saved, fallback: fallback)
        if saved != nil, saved != resolved { defaults.set(resolved, forKey: key) }
        return resolved
    }

    func setError(_ message: String) {
        status = .error(message)
        lastError = message
    }

    func clearError() {
        if case .error = status { status = .idle }
        lastError = nil
    }
}
