import Foundation
import os

/// Background model downloads the user can see: a migrated model at launch, or a missing model a dictation
/// needed. Progress is published on `AppState.modelDownloads`; a dictation never waits for one.
@MainActor
final class ModelDownloads: ModelAvailability {
    private static let log = Logger(subsystem: "com.honyaku.app", category: "models")
    private let appState: AppState
    private let installer: ModelInstaller
    private let folder: (ModelInfo) -> URL
    private let installedCheck: (ModelInfo) -> Bool
    private var running: Set<String> = []
    /// Models whose repo has no chat template: told once, not retried until the next launch
    private var withoutTemplate: Set<String> = []
    private var onInstalled: [String: [@MainActor () -> Void]] = [:]

    /// `folder` and `installedCheck` are for tests; the defaults are the real models folder.
    init(appState: AppState, installer: ModelInstaller = .shared,
         folder: @escaping (ModelInfo) -> URL = { ModelStore.shared.modelDirectory(for: $0) },
         installedCheck: @escaping (ModelInfo) -> Bool = { ModelInstaller.isInstalled($0) }) {
        self.appState = appState
        self.installer = installer
        self.folder = folder
        self.installedCheck = installedCheck
    }

    func isRunning(_ model: ModelInfo) -> Bool { running.contains(model.id) }

    /// Starts downloading `model` unless it's installed or already downloading.
    func startDownload(_ model: ModelInfo) {
        guard !withoutTemplate.contains(model.id), !installedCheck(model),
              running.insert(model.id).inserted else { return }
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

    func isInstalled(_ model: ModelInfo) -> Bool { installedCheck(model) }

    /// A cleanup model installed before Honyaku fetched chat templates has its weights but no template:
    /// fetch just the template, visibly, like a migration download.
    func repairChatTemplateIfNeeded(_ model: ModelInfo, onRepaired: @escaping @MainActor () -> Void) {
        guard model.engine == .mlx, ModelInstaller.needsChatTemplateOnly(at: folder(model)) else { return }
        onInstalled[model.id, default: []].append(onRepaired)
        startDownload(model)
    }

    func cleanupSkippedNotice(for model: ModelInfo) -> String {
        withoutTemplate.contains(model.id)
            ? ModelDownloadError.noChatTemplate(model.displayName).localizedDescription
            : "Cleanup is off until \(model.displayName) finishes downloading."
    }

    /// "Downloading Parakeet TDT 0.6B v2, 42%"
    func downloadMessage(for model: ModelInfo) -> String {
        let percent = Int(((appState.modelDownloads[model.id] ?? 0) * 100).rounded())
        return "Downloading \(model.displayName), \(percent)%. Dictation works once it finishes."
    }

    private func finish(_ model: ModelInfo, error: Error?) {
        running.remove(model.id)
        appState.modelDownloads[model.id] = nil
        let callbacks = onInstalled.removeValue(forKey: model.id) ?? []
        switch error {
        case nil:
            callbacks.forEach { $0() }
        case ModelDownloadError.noChatTemplate?:
            withoutTemplate.insert(model.id)
            Self.log.error("\(model.id, privacy: .public) has no chat template; not retrying this launch")
            appState.setError(error!.localizedDescription)
        case let error?:
            appState.setError("Couldn't download \(model.displayName): \(error.localizedDescription) Check your connection; the download starts again with your next dictation, or from Settings > Models.")
        }
    }
}
