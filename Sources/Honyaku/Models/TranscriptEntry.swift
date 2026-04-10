import Foundation

struct TranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let rawText: String
    let cleanedText: String
    let timestamp: Date
    let modelTier: String
    let durationSeconds: Double
    let hasSpeakerLabels: Bool

    init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String,
        timestamp: Date = Date(),
        modelTier: String,
        durationSeconds: Double,
        hasSpeakerLabels: Bool = false
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.timestamp = timestamp
        self.modelTier = modelTier
        self.durationSeconds = durationSeconds
        self.hasSpeakerLabels = hasSpeakerLabels
    }
}
