import Foundation

/// Curated catalog of supported models with sizes, HF paths, and SHA-256 checksums.
/// Checksums are placeholders — populate with actual values before release.
enum ModelRegistry {

    // MARK: - Speech models

    static let speechModels: [ModelInfo] = [
        ModelInfo(
            id: "parakeet-tdt-v2",
            type: .speech,
            engine: .parakeet,
            displayName: "Parakeet (English)",
            hfRepoPath: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
            fileNames: [],  // FluidAudio fetches the Core ML bundles and vocabulary itself
            sizeMB: 464,
            tier: "recommended",
            notes: "Most accurate and fastest for English, adds punctuation",
            sha256Checksums: [:]
        ),
        ModelInfo(
            id: "whisper-large-v3-turbo",
            type: .speech,
            engine: .whisperKit,
            displayName: "Whisper Large v3 Turbo (Multilingual)",
            hfRepoPath: "argmaxinc/whisperkit-coreml",
            fileNames: [],
            sizeMB: 627,
            tier: "multilingual",
            notes: "99 languages",
            sha256Checksums: [:],
            whisperVariant: "openai_whisper-large-v3-v20240930_626MB"
        ),
    ]

    // MARK: - Cleanup models (MLX format — Apple Silicon only)
    // fileNames is empty: ModelDownloader fetches the full repo file list via the HuggingFace API.

    static let cleanupModels: [ModelInfo] = [
        ModelInfo(
            id: "qwen3-1.7b",
            type: .cleanup,
            engine: .mlx,
            displayName: "Qwen3 1.7B (Faster)",
            hfRepoPath: "mlx-community/Qwen3-1.7B-4bit",
            fileNames: [],
            sizeMB: 968,
            tier: "fast",
            notes: "Faster, lighter on memory",
            sha256Checksums: [:],
            disablesThinking: true
        ),
        ModelInfo(
            id: "qwen3-4b-2507",
            type: .cleanup,
            engine: .mlx,
            displayName: "Qwen3 4B (More accurate)",
            hfRepoPath: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            fileNames: [],
            sizeMB: 2260,
            tier: "best",
            notes: "More accurate, needs 16 GB of memory",
            sha256Checksums: [:]
        ),
    ]

    // MARK: - Diarization models

    static let diarizationModels: [ModelInfo] = [
        ModelInfo(
            id: "speakerkit-coreml",
            type: .diarization,
            engine: .speakerKit,
            displayName: "SpeakerKit CoreML",
            hfRepoPath: "argmaxinc/speakerkit-coreml",
            fileNames: [],  // SpeakerKit manages its own download via PyannoteConfig
            sizeMB: 10,
            tier: "standard",
            notes: "~122× real-time on M1; downloaded on first use",
            sha256Checksums: [:]
        ),
    ]

    // MARK: - Lookup helpers

    static func model(id: String) -> ModelInfo? {
        (speechModels + cleanupModels + diarizationModels).first { $0.id == id }
    }

    /// Default models for a Mac with this much physical memory (bytes).
    static func recommended(forPhysicalMemory bytes: UInt64) -> (speech: String, cleanup: String) {
        // A "16 GB" Mac reports exactly 16 GiB; the margin keeps rounding from pushing it below
        let sixteenGB: UInt64 = 16 * 1024 * 1024 * 1024
        let cleanup = bytes >= sixteenGB - 512 * 1024 * 1024 ? "qwen3-4b-2507" : "qwen3-1.7b"
        return ("parakeet-tdt-v2", cleanup)
    }

    /// The model that replaces a retired one, so saved selections survive the lineup change. A cleanup
    /// replacement is never larger than the recommendation for the Mac's memory (8 GB Macs get the 1.7B).
    static func migratedID(_ id: String,
                           physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String? {
        switch id {
        case "whisper-tiny-en", "whisper-small-en":            return "parakeet-tdt-v2"
        case "whisper-small-multilingual":                     return "whisper-large-v3-turbo"
        case "qwen-1.5b-mlx":                                  return "qwen3-1.7b"
        case "qwen-3b-mlx", "qwen-7b-mlx", "qwen-0.8b":        return recommended(forPhysicalMemory: physicalMemory).cleanup
        default:                                               return nil
        }
    }

    /// A saved selection resolved to a current model: retired IDs are migrated, unknown ones fall back.
    static func resolvedID(_ saved: String?, fallback: String,
                           physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        guard let saved else { return fallback }
        if model(id: saved) != nil { return saved }
        return migratedID(saved, physicalMemory: physicalMemory) ?? fallback
    }

    static var defaultSpeechModelID: String {
        recommended(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory).speech
    }
    static var defaultCleanupModelID: String {
        recommended(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory).cleanup
    }
    static let defaultDiarizationModelID = "speakerkit-coreml"
}
