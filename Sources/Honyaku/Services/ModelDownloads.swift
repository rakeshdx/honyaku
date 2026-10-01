import Foundation

/// Background model downloads the user can see: a migrated model at launch, or a missing model a dictation
/// needed. Progress is published on `AppState.modelDownloads`; a dictation never waits for one.
@MainActor
final class ModelDownloads: ModelAvailability {
    private let appState: AppState
    private let installer: ModelInstaller
    private var running: Set<String> = []

    init(appState: AppState, installer: ModelInstaller = .shared) {
        self.appState = appState
        self.installer = installer
    }

    func isRunning(_ model: ModelInfo) -> Bool { running.contains(model.id) }

    /// Starts downloading `model` unless it's installed or already downloading.
    func start(_ model: ModelInfo) {
        guard !ModelInstaller.isInstalled(model), running.insert(model.id).inserted else { return }
        appState.modelDownloads[model.id] = 0
        let installer = installer
        let appState = appState
        Task { [weak self] in
            do {
                try await installer.install(model) { fraction in
                    Task { @MainActor in
                        // Progress can arrive after completion; never resurrect a finished entry
                        guard appState.modelDownloads[model.id] != nil else { return }
                        appState.modelDownloads[model.id] = fraction
                    }
                }
                self?.finish(model, error: nil)
            } catch {
                self?.finish(model, error: error)
            }
        }
    }

    func isInstalled(_ model: ModelInfo) -> Bool { ModelInstaller.isInstalled(model) }

    func startDownload(_ model: ModelInfo) { start(model) }

    func downloadMessage(for model: ModelInfo) -> String { message(for: model) }

    /// "Downloading Parakeet TDT 0.6B v2, 42%"
    func message(for model: ModelInfo) -> String {
        let percent = Int(((appState.modelDownloads[model.id] ?? 0) * 100).rounded())
        return "Downloading \(model.displayName), \(percent)%. Dictation works once it finishes."
    }

    private func finish(_ model: ModelInfo, error: Error?) {
        running.remove(model.id)
        appState.modelDownloads[model.id] = nil
        if let error {
            appState.setError("Couldn't download \(model.displayName): \(error.localizedDescription) Check your connection; the download starts again with your next dictation, or from Settings > Models.")
        }
    }
}
