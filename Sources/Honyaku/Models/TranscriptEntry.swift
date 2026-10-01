import Foundation

struct TranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let rawText: String
    let cleanedText: String
    let timestamp: Date
    let modelTier: String
    let durationSeconds: Double
    let hasSpeakerLabels: Bool
    /// `DictationMode.id` the entry was made in; nil for entries saved before modes existed.
    let mode: String?
    /// The app in front when the text was pasted or saved; nil for older entries.
    let appBundleID: String?

    init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String,
        timestamp: Date = Date(),
        modelTier: String,
        durationSeconds: Double,
        hasSpeakerLabels: Bool = false,
        mode: String? = nil,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.timestamp = timestamp
        self.modelTier = modelTier
        self.durationSeconds = durationSeconds
        self.hasSpeakerLabels = hasSpeakerLabels
        self.mode = mode
        self.appBundleID = appBundleID
    }
}
