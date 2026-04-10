import Foundation

enum ModelType: String, Codable, CaseIterable {
    case speech
    case cleanup
    case diarization
}

struct ModelInfo: Codable, Identifiable, Equatable {
    let id: String          // unique slug, e.g. "whisper-small-en"
    let type: ModelType
    let displayName: String
    let hfRepoPath: String  // e.g. "argmaxinc/whisperkit-coreml"
    let fileNames: [String] // files to download within the repo (unused for speech models)
    let sizeMB: Int
    let tier: String        // "fast" | "balanced" | "quality" | "multilingual"
    let notes: String
    let sha256Checksums: [String: String] // filename → checksum
    /// WhisperKit variant name used with WhisperKit.download(variant:) — speech models only.
    let whisperVariant: String?

    init(id: String, type: ModelType, displayName: String, hfRepoPath: String,
         fileNames: [String], sizeMB: Int, tier: String, notes: String,
         sha256Checksums: [String: String], whisperVariant: String? = nil) {
        self.id = id; self.type = type; self.displayName = displayName
        self.hfRepoPath = hfRepoPath; self.fileNames = fileNames; self.sizeMB = sizeMB
        self.tier = tier; self.notes = notes; self.sha256Checksums = sha256Checksums
        self.whisperVariant = whisperVariant
    }
}
