import FluidAudio
import Foundation
import os
import WhisperKit

enum InstallState: Equatable {
    case notInstalled
    case incomplete         // files present but a download was interrupted
    case installed(bytes: Int64)
}

/// The one place that knows how each engine checks, installs and deletes its model files.
actor ModelInstaller {
    static let shared = ModelInstaller()
    private static let log = Logger(subsystem: "com.honyaku.app", category: "models")

    // MARK: - State

    func state(of model: ModelInfo) -> InstallState {
        ModelInstaller.state(of: model)
    }

    /// Synchronous so views and `ModelStore.isDownloaded` can ask without awaiting.
    nonisolated static func state(of model: ModelInfo) -> InstallState {
        switch model.engine {
        case .speakerKit:
            // SpeakerKit fetches its own ~10 MB bundle on first use
            return .installed(bytes: 0)
        case .parakeet:
            let folder = parakeetFolder()
            return folderState(folder, complete: isParakeetComplete(at: folder))
        case .whisperKit:
            guard let variant = model.whisperVariant else { return .notInstalled }
            let folder = TranscriptionService.localModelFolder(repo: model.hfRepoPath, variant: variant)
            let complete = TranscriptionService.isModelDownloaded(at: folder)
                && TranscriptionService.isTokenizerDownloaded(variant: variant)
            return folderState(folder, complete: complete)
        case .mlx:
            let folder = ModelStore.shared.modelDirectory(for: model)
            return folderState(folder, complete: isMLXComplete(at: folder))
        }
    }

    nonisolated static func isInstalled(_ model: ModelInfo) -> Bool {
        if case .installed = state(of: model) { return true }
        return false
    }

    // MARK: - Install

    /// Downloads a model and loads it once, so any Neural Engine compile happens now rather than on the
    /// first dictation. `progress` reports 0…1 on an arbitrary thread.
    func install(_ model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        switch model.engine {
        case .speakerKit:
            progress(1)
        case .parakeet:
            let folder = ModelInstaller.parakeetFolder()
            // FluidAudio returns early on a partial folder unless forced
            let force = ModelInstaller.state(of: model) == .incomplete
            try await AsrModels.download(to: folder, force: force, version: .v2) { p in
                progress(p.fractionCompleted)
            }
        case .whisperKit:
            guard let variant = model.whisperVariant else { throw TranscriptionError.modelNotLoaded }
            let token = KeychainService.load(key: KeychainService.hfTokenKey)
            _ = try await WhisperKit.download(variant: variant, from: model.hfRepoPath, token: token) { p in
                progress(p.fractionCompleted * 0.95)
            }
            // The first load compiles for the Neural Engine and fetches the small tokenizer
            let folder = TranscriptionService.localModelFolder(repo: model.hfRepoPath, variant: variant)
            _ = try await WhisperKit(WhisperKitConfig(
                model: variant, modelRepo: model.hfRepoPath, modelFolder: folder.path, download: false
            ))
            progress(1)
        case .mlx:
            try await ModelDownloader().download(model: model, progress: progress)
        }
        guard ModelInstaller.isInstalled(model) else {
            ModelInstaller.log.error("Model \(model.id, privacy: .public) incomplete after install")
            throw ModelDownloadError.fileSystemError(CocoaError(.fileReadCorruptFile))
        }
    }

    // MARK: - Delete

    func delete(_ model: ModelInfo) throws {
        let fm = FileManager.default
        switch model.engine {
        case .speakerKit:
            return
        case .parakeet:
            let folder = ModelInstaller.parakeetFolder()
            if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        case .whisperKit:
            guard let variant = model.whisperVariant else { return }
            let folder = TranscriptionService.localModelFolder(repo: model.hfRepoPath, variant: variant)
            if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        case .mlx:
            try ModelStore.shared.delete(model)
        }
    }

    // MARK: - Locations and completeness

    /// FluidAudio requires the folder to be named after its repo.
    nonisolated static func parakeetFolder(base: URL = ModelStore.shared.baseDirectory) -> URL {
        base.appending(path: "speech/parakeet-tdt-0.6b-v2-coreml", directoryHint: .isDirectory)
    }

    /// Every Core ML bundle FluidAudio loads for v2 must be whole; an interrupted download can leave a
    /// bundle without its weights, or `*.partial` files behind.
    nonisolated static func isParakeetComplete(at folder: URL) -> Bool {
        let fm = FileManager.default
        let bundles = ["Preprocessor", "Encoder", "Decoder", "JointDecision"]
        let parts = ["coremldata.bin", "model.mil", "metadata.json", "weights/weight.bin"]
        let required = bundles.flatMap { bundle in parts.map { "\(bundle).mlmodelc/\($0)" } } + ["parakeet_vocab.json"]
        guard required.allSatisfy({ fm.fileExists(atPath: folder.appending(path: $0).path) }) else { return false }
        return !containsPartialFiles(folder)
    }

    /// An MLX model is whole when `config.json` exists and every weight shard the index names is present.
    nonisolated static func isMLXComplete(at folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appending(path: "config.json").path) else { return false }
        let index = folder.appending(path: "model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = json["weight_map"] as? [String: String] {
            return Set(weightMap.values).allSatisfy { fm.fileExists(atPath: folder.appending(path: $0).path) }
        }
        // Single-file models have no index
        return fm.fileExists(atPath: folder.appending(path: "model.safetensors").path)
    }

    private nonisolated static func folderState(_ folder: URL, complete: Bool) -> InstallState {
        if complete { return .installed(bytes: sizeOnDisk(folder)) }
        return FileManager.default.fileExists(atPath: folder.path) ? .incomplete : .notInstalled
    }

    private nonisolated static func containsPartialFiles(_ folder: URL) -> Bool {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return false }
        return files.contains { ($0 as? URL)?.pathExtension == "partial" }
    }

    nonisolated static func sizeOnDisk(_ folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(into: Int64(0)) { total, item in
            guard let url = item as? URL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            total += Int64(size)
        }
    }
}
