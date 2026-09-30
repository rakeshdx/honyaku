import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var status: AppStatus = .idle
    var lastError: String?
    /// Background model downloads in progress: model ID → 0…1.
    var modelDownloads: [String: Double] = [:]

    // Feature toggles (backed by UserDefaults via AppStorage in views,
    // mirrored here for pipeline access).
    // Use object(forKey:) so a missing key returns nil and the ?? default applies correctly.
    // UserDefaults.bool(forKey:) always returns false for missing keys, ignoring register(defaults:)
    // when AppState is initialized before AppCoordinator.init() calls register().
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

    /// Cleanup system prompt. Resetting to the default removes the stored copy, so future default
    /// improvements reach the user.
    var cleanupPrompt: String = UserDefaults.standard.string(forKey: "cleanupPrompt") ?? CleanupService.defaultPrompt {
        didSet {
            if cleanupPrompt == CleanupService.defaultPrompt {
                UserDefaults.standard.removeObject(forKey: "cleanupPrompt")
            } else {
                UserDefaults.standard.set(cleanupPrompt, forKey: "cleanupPrompt")
            }
        }
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
        if saved != nil, saved != resolved {
            defaults.set(resolved, forKey: key)
            migratedSelectionKeys.insert(key)
        }
        return resolved
    }

    /// Selections migrated from a retired model this launch, so the pipeline can fetch the new models
    /// straight away. A static because property initialisers can't reach the instance.
    nonisolated(unsafe) static var migratedSelectionKeys: Set<String> = []

    // Live recording feedback for the keycap and capsule
    /// 0–1 input level while recording, updated at most ~30 times a second.
    var inputLevel: Double = 0
    var recordingStartedAt: Date?

    // First run's "Try it" step: the dictation result is shown in the window instead of pasted
    var firstRunTestActive = false
    var firstRunTestTranscript: String?

    func setError(_ message: String) {
        status = .error(message)
        lastError = message
    }

    func clearError() {
        if case .error = status { status = .idle }
        lastError = nil
    }
}
