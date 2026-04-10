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

    // Selected model IDs
    var selectedSpeechModelID: String = UserDefaults.standard.string(forKey: "selectedSpeechModelID") ?? "whisper-small-en" {
        didSet { UserDefaults.standard.set(selectedSpeechModelID, forKey: "selectedSpeechModelID") }
    }
    var selectedCleanupModelID: String = UserDefaults.standard.string(forKey: "selectedCleanupModelID") ?? "qwen-0.8b" {
        didSet { UserDefaults.standard.set(selectedCleanupModelID, forKey: "selectedCleanupModelID") }
    }

    // Setup state
    var setupComplete: Bool = UserDefaults.standard.bool(forKey: "setupComplete") {
        didSet { UserDefaults.standard.set(setupComplete, forKey: "setupComplete") }
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
