import AVFoundation
import Foundation
import WhisperKit

/// Whisper via WhisperKit: the multilingual engine.
final class WhisperKitEngine: SpeechEngine, @unchecked Sendable {
    // WhisperKit isn't Sendable; TranscriptionService runs one dictation at a time
    private let kit: WhisperKit

    init(kit: WhisperKit) {
        self.kit = kit
    }

    func transcribe(audioURL: URL, samples16k: [Float]?) async throws -> TranscriptionResult {
        let options = TranscriptionService.decodeOptions(forDurationSeconds: Self.duration(of: audioURL))
        let segments = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        guard !segments.isEmpty, let first = segments.first else {
            throw TranscriptionError.emptyResult
        }
        let whisperSegments = segments.flatMap { $0.segments }
        let duration = whisperSegments.last.map { Double($0.end) } ?? 0
        let timed = whisperSegments.map {
            TimedSegment(startSeconds: Double($0.start), endSeconds: Double($0.end),
                         text: TranscriptionService.stripNonSpeech(TranscriptionService.stripTokens($0.text)))
        }
        let fullText = TranscriptionService.assembleText(
            windowTexts: segments.map(\.text), segmentTexts: whisperSegments.map(\.text)
        )
        return TranscriptionResult(
            rawText: fullText,
            language: first.language,
            durationSeconds: duration,
            timedSegments: timed
        )
    }

    private static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
