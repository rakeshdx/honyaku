import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var status: AppStatus = .idle
    var lastError: String?
    /// Background model downloads in progress: model ID → 0…1.
    var modelDownloads: [String: Double] = [:]

    /// Where settings are saved: `.standard` in the app, a private suite in tests.
    @ObservationIgnored private let defaults: UserDefaults

    // Feature toggles, saved to `defaults`.
    // Read with object(forKey:) so a missing key returns nil and the ?? default applies correctly.
    // UserDefaults.bool(forKey:) always returns false for missing keys, ignoring register(defaults:)
    // when AppState is initialized before AppCoordinator.init() calls register().
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") }
    }
    var diarizationEnabled: Bool {
        didSet { defaults.set(diarizationEnabled, forKey: "diarizationEnabled") }
    }

    // Selected model IDs — retired models are migrated to their replacement on first read
    var selectedSpeechModelID: String {
        didSet { defaults.set(selectedSpeechModelID, forKey: "selectedSpeechModelID") }
    }
    var selectedCleanupModelID: String {
        didSet { defaults.set(selectedCleanupModelID, forKey: "selectedCleanupModelID") }
    }

    /// Cleanup system prompt. Resetting to the default removes the stored copy, so future default
    /// improvements reach the user.
    var cleanupPrompt: String {
        didSet {
            if cleanupPrompt == CleanupService.defaultPrompt {
                defaults.removeObject(forKey: "cleanupPrompt")
            } else {
                defaults.set(cleanupPrompt, forKey: "cleanupPrompt")
            }
        }
    }

    // Setup state
    var setupComplete: Bool {
        didSet { defaults.set(setupComplete, forKey: "setupComplete") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cleanupEnabled = (defaults.object(forKey: "cleanupEnabled") as? Bool) ?? true
        diarizationEnabled = (defaults.object(forKey: "diarizationEnabled") as? Bool) ?? false
        let speech = AppState.resolvedSelection(
            key: "selectedSpeechModelID", fallback: ModelRegistry.defaultSpeechModelID, defaults: defaults)
        let cleanup = AppState.resolvedSelection(
            key: "selectedCleanupModelID", fallback: ModelRegistry.defaultCleanupModelID, defaults: defaults)
        selectedSpeechModelID = speech.id
        selectedCleanupModelID = cleanup.id
        migratedSelectionKeys = Set([speech.migrated ? "selectedSpeechModelID" : nil,
                                     cleanup.migrated ? "selectedCleanupModelID" : nil].compactMap { $0 })
        cleanupPrompt = defaults.string(forKey: "cleanupPrompt") ?? CleanupService.defaultPrompt
        setupComplete = defaults.bool(forKey: "setupComplete")
    }

    /// Reads a saved model selection, migrating a retired ID and writing the result back so services
    /// that read UserDefaults directly (CleanupService) see the same model.
    nonisolated static func resolvedSelection(key: String, fallback: String,
                                              defaults: UserDefaults) -> (id: String, migrated: Bool) {
        let saved = defaults.string(forKey: key)
        let resolved = ModelRegistry.resolvedID(saved, fallback: fallback)
        guard saved != nil, saved != resolved else { return (resolved, false) }
        defaults.set(resolved, forKey: key)
        return (resolved, true)
    }

    /// Selections this state migrated from a retired model when it loaded, so the pipeline can fetch the
    /// new models straight away.
    @ObservationIgnored let migratedSelectionKeys: Set<String>

    // Live recording feedback for the keycap and capsule
    /// 0–1 input level while recording, updated at most ~30 times a second.
    var inputLevel: Double = 0
    var recordingStartedAt: Date?
    /// The template of the rewrite being recorded or generated; nil while dictating.
    var rewriteTemplate: RewriteTemplateID?

    // First run's "Try it" step: the dictation result is shown in the window instead of pasted.
    // Each test gets its own number, so a dictation started in a test that has since ended is discarded.
    private(set) var firstRunTestSession: Int?
    var firstRunTestTranscript: String?
    private var lastFirstRunTestSession = 0

    var firstRunTestActive: Bool { firstRunTestSession != nil }

    func beginFirstRunTest() {
        lastFirstRunTestSession += 1
        firstRunTestSession = lastFirstRunTestSession
        firstRunTestTranscript = nil
    }

    func endFirstRunTest() {
        firstRunTestSession = nil
        firstRunTestTranscript = nil
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
