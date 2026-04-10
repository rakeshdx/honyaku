import Foundation

/// Curated catalog of supported models with sizes, HF paths, and SHA-256 checksums.
/// Checksums are placeholders — populate with actual values before release.
enum ModelRegistry {

    // MARK: - Speech models

    static let speechModels: [ModelInfo] = [
        ModelInfo(
            id: "whisper-tiny-en",
            type: .speech,
            displayName: "Whisper Tiny (English)",
            hfRepoPath: "argmaxinc/whisperkit-coreml",
            fileNames: [],
            sizeMB: 75,
            tier: "fast",
            notes: "Fastest, English only",
            sha256Checksums: [:],
            whisperVariant: "openai_whisper-tiny.en"
        ),
        ModelInfo(
            id: "whisper-small-en",
            type: .speech,
            displayName: "Whisper Small (English)",
            hfRepoPath: "argmaxinc/whisperkit-coreml",
            fileNames: [],
            sizeMB: 466,
            tier: "balanced",
            notes: "Best accuracy/speed balance, English only — default",
            sha256Checksums: [:],
            whisperVariant: "openai_whisper-small.en"
        ),
        ModelInfo(
            id: "whisper-small-multilingual",
            type: .speech,
            displayName: "Whisper Small (Multilingual)",
            hfRepoPath: "argmaxinc/whisperkit-coreml",
            fileNames: [],
            sizeMB: 466,
            tier: "multilingual",
            notes: "99 languages",
            sha256Checksums: [:],
            whisperVariant: "openai_whisper-small"
        ),
    ]

    // MARK: - Cleanup models (MLX format — Apple Silicon only)
    // fileNames is empty: ModelDownloader fetches the full repo file list via the HuggingFace API.

    static let cleanupModels: [ModelInfo] = [
        ModelInfo(
            id: "qwen-1.5b-mlx",
            type: .cleanup,
            displayName: "Qwen 2.5 1.5B (Fast)",
            hfRepoPath: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            fileNames: [],
            sizeMB: 950,
            tier: "fast",
            notes: "~2–3s on M1 — default",
            sha256Checksums: [:]
        ),
        ModelInfo(
            id: "qwen-3b-mlx",
            type: .cleanup,
            displayName: "Qwen 2.5 3B (Balanced)",
            hfRepoPath: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            fileNames: [],
            sizeMB: 1900,
            tier: "balanced",
            notes: "~5–6s on M1",
            sha256Checksums: [:]
        ),
        ModelInfo(
            id: "qwen-7b-mlx",
            type: .cleanup,
            displayName: "Qwen 2.5 7B (Best)",
            hfRepoPath: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            fileNames: [],
            sizeMB: 4300,
            tier: "best",
            notes: "~10–15s on M1, most accurate",
            sha256Checksums: [:]
        ),
    ]

    // MARK: - Diarization models

    static let diarizationModels: [ModelInfo] = [
        ModelInfo(
            id: "speakerkit-coreml",
            type: .diarization,
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

    static let defaultSpeechModelID = "whisper-small-en"
    static let defaultCleanupModelID = "qwen-1.5b-mlx"
    static let defaultDiarizationModelID = "speakerkit-coreml"
}
