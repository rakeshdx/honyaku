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

    typealias InstallStep = @Sendable (_ model: ModelInfo, _ force: Bool,
                                       _ progress: @escaping @Sendable (Double) -> Void) async throws -> Void
    private let installStep: InstallStep
    /// In-flight installs by model ID, so a second request waits for the first rather than racing it
    /// (a forced Parakeet download deletes the folder another download is writing to). Each caller's
    /// progress handler is on the install's fan-out.
    private var installing: [String: (task: Task<Void, Error>, progress: ProgressFanOut)] = [:]

    /// `installStep` is for tests; the default downloads, compiles and verifies the real model.
    init(installStep: InstallStep? = nil) {
        self.installStep = installStep ?? { model, force, progress in
            try await ModelInstaller.download(model, force: force, progress: progress)
        }
    }

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
    /// first dictation. `progress` reports 0…1 on an arbitrary thread. A concurrent install of the same
    /// model waits for the one already running, and its `progress` follows that install from then on.
    /// `force` re-downloads files that are present but won't load.
    func install(_ model: ModelInfo, force: Bool = false,
                 progress: @escaping @Sendable (Double) -> Void) async throws {
        if let running = installing[model.id] {
            running.progress.add(progress)
            return try await running.task.value
        }
        // Decided once, by the install that actually runs
        let force = force || ModelInstaller.state(of: model) == .incomplete
        let step = installStep
        let fanOut = ProgressFanOut(progress)
        let task = Task { try await step(model, force) { fanOut.send($0) } }
        installing[model.id] = (task, fanOut)
        defer { installing[model.id] = nil }
        try await task.value
    }

    private static func download(_ model: ModelInfo, force: Bool,
                                 progress: @escaping @Sendable (Double) -> Void) async throws {
        switch model.engine {
        case .speakerKit:
            progress(1)
        case .parakeet:
            let folder = ModelInstaller.parakeetFolder()
            // FluidAudio returns early on a partial or unloadable folder unless forced
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
        guard let folder = try Self.deletionFolder(for: model) else { return }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// The folder deleting `model` removes, or nil when there's nothing of its own to remove (SpeakerKit).
    /// Throws for a name that could reach outside the model's own folder. Pure, so tests pass temporary bases.
    nonisolated static func deletionFolder(
        for model: ModelInfo, modelsBase: URL = ModelStore.shared.baseDirectory,
        documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) throws -> URL? {
        switch model.engine {
        case .speakerKit:
            return nil
        case .parakeet:
            return parakeetFolder(base: modelsBase)
        case .whisperKit:
            guard let variant = model.whisperVariant, isSafePathPart(variant), isSafePathPart(model.hfRepoPath) else {
                throw ModelDownloadError.fileSystemError(CocoaError(.fileWriteInvalidFileName))
            }
            return TranscriptionService.localModelFolder(repo: model.hfRepoPath, variant: variant, documents: documents)
        case .mlx:
            guard isSafePathPart(model.id) else {
                throw ModelDownloadError.fileSystemError(CocoaError(.fileWriteInvalidFileName))
            }
            // Same folder as ModelStore.modelDirectory(for:)
            return modelsBase.appendingPathComponent("\(model.type.rawValue)/\(model.id)", isDirectory: true)
        }
    }

    /// Delete must only ever remove the model's own folder: an empty value would name the parent folder,
    /// and ".." could walk out of it.
    nonisolated static func isSafePathPart(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !value.isEmpty && !value.hasPrefix("/") && !parts.contains { $0.isEmpty || $0 == ".." || $0 == "." }
    }

    // MARK: - Locations and completeness

    /// FluidAudio requires the folder to be named after its repo.
    nonisolated static func parakeetFolder(base: URL = ModelStore.shared.baseDirectory) -> URL {
        // FluidAudio writes into <parent>/<its own folder name> whatever last component it's given,
        // so take the name from FluidAudio rather than hard-coding it
        base.appending(path: "speech", directoryHint: .isDirectory)
            .appending(path: Repo.parakeetV2.folderName, directoryHint: .isDirectory)
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

    /// An MLX model is whole when `config.json` and `tokenizer.json` exist and every weight shard the index
    /// names is present.
    nonisolated static func isMLXComplete(at folder: URL) -> Bool {
        let fm = FileManager.default
        guard ["config.json", "tokenizer.json"].allSatisfy({ fm.fileExists(atPath: folder.appending(path: $0).path) })
        else { return false }
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

/// Sends one install's progress to every caller waiting on it. Progress arrives on arbitrary threads.
final class ProgressFanOut: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable (Double) -> Void]
    private var latest: Double?

    init(_ first: @escaping @Sendable (Double) -> Void) {
        handlers = [first]
    }

    /// A late joiner hears the latest value straight away, so its bar doesn't start from zero.
    func add(_ handler: @escaping @Sendable (Double) -> Void) {
        let current = lock.withLock { () -> Double? in
            handlers.append(handler)
            return latest
        }
        if let current { handler(current) }
    }

    func send(_ fraction: Double) {
        let targets = lock.withLock { () -> [@Sendable (Double) -> Void] in
            latest = fraction
            return handlers
        }
        for handler in targets { handler(fraction) }
    }
}
