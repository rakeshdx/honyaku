import Foundation

enum ModelType: String, Codable, CaseIterable {
    case speech
    case cleanup
    case diarization
}

/// Which runtime loads and installs a model.
enum ModelEngine: String, Codable {
    case whisperKit   // speech, via WhisperKit
    case parakeet     // speech, via FluidAudio
    case mlx          // cleanup LLMs, via mlx-swift-lm
    case speakerKit   // diarization; SpeakerKit manages its own files
}

struct ModelInfo: Codable, Identifiable, Equatable {
    let id: String          // unique slug, e.g. "parakeet-tdt-v2"
    let type: ModelType
    let engine: ModelEngine
    let displayName: String
    let hfRepoPath: String  // e.g. "argmaxinc/whisperkit-coreml"
    let fileNames: [String] // files to download within the repo (unused for speech models)
    let sizeMB: Int
    let tier: String        // "recommended" | "multilingual" | "fast" | "best" | "standard"
    let notes: String
    let sha256Checksums: [String: String] // filename → checksum
    /// WhisperKit variant name used with WhisperKit.download(variant:) — WhisperKit models only.
    let whisperVariant: String?
    /// Qwen3-style models reason before answering unless the chat template is told not to.
    let disablesThinking: Bool

    init(id: String, type: ModelType, engine: ModelEngine, displayName: String, hfRepoPath: String,
         fileNames: [String], sizeMB: Int, tier: String, notes: String,
         sha256Checksums: [String: String], whisperVariant: String? = nil, disablesThinking: Bool = false) {
        self.id = id; self.type = type; self.engine = engine; self.displayName = displayName
        self.hfRepoPath = hfRepoPath; self.fileNames = fileNames; self.sizeMB = sizeMB
        self.tier = tier; self.notes = notes; self.sha256Checksums = sha256Checksums
        self.whisperVariant = whisperVariant; self.disablesThinking = disablesThinking
    }
}

extension ModelInfo {
    /// Whether the dictation-language setting applies: multilingual Whisper models only.
    var supportsDictationLanguage: Bool {
        engine == .whisperKit && !(whisperVariant?.hasSuffix(".en") ?? false)
    }
}
