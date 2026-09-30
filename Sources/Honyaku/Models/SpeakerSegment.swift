import Foundation

/// Our app-level diarization segment. Named DiarizedSegment to avoid collision with
/// SpeakerKit.SpeakerSegment from the WhisperKit SPM package.
struct DiarizedSegment: Equatable {
    let startSeconds: Double
    let endSeconds: Double
    let speakerID: String   // e.g. "Speaker 1", "Speaker 2"
    let text: String
}

/// A single timed chunk of transcribed text from WhisperKit.
struct TimedSegment: Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}

struct TranscriptionResult: Sendable {
    let rawText: String
    let language: String
    let durationSeconds: Double
    let timedSegments: [TimedSegment]  // per-segment timing from the speech engine — used for speaker assignment
}
