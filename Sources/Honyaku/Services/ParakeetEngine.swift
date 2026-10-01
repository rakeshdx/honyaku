import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v2 via FluidAudio: the default English engine. It punctuates and
/// capitalises on its own.
struct ParakeetEngine: SpeechEngine {
    private let manager: AsrManager

    /// Loads the compiled models from `folder` with no network access.
    static func load(from folder: URL) async throws -> ParakeetEngine {
        let models = try AsrModels.loadLocal(from: folder, version: .v2)
        return ParakeetEngine(manager: AsrManager(config: .default, models: models))
    }

    private init(manager: AsrManager) {
        self.manager = manager
    }

    func transcribe(audioURL: URL, samples16k: [Float]?, hints: SpeechHints) async throws -> TranscriptionResult {
        // An empty array means the capture-side conversion failed; decode the file instead
        let samples = try samples16k.flatMap { $0.isEmpty ? nil : $0 } ?? AudioConverter().resampleAudioFile(audioURL)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(ParakeetEngine.padded(samples), decoderState: &state)

        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            SpokenWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        let text = TranscriptionService.stripNonSpeech(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let isSilence = ParakeetEngine.isSilence(text: text, confidence: result.confidence, wordCount: words.count)
        return TranscriptionResult(
            rawText: isSilence ? "" : text,
            language: "en",
            durationSeconds: Double(samples.count) / ParakeetEngine.sampleRate,
            timedSegments: isSilence ? [] : ParakeetEngine.segments(from: words)
        )
    }

    // MARK: - Helpers (static so they can be unit-tested without the model)

    static let sampleRate = 16_000.0
    /// FluidAudio rejects anything shorter than 0.3 s.
    static let minimumSamples = 4_800

    /// Pads a clip shorter than FluidAudio's minimum with trailing silence.
    static func padded(_ samples: [Float]) -> [Float] {
        samples.count >= minimumSamples ? samples : samples + Array(repeating: 0, count: minimumSamples - samples.count)
    }

    /// FluidAudio has no no-speech flag: silence comes back as empty text, or with its floor confidence
    /// (0.1) and no token timings.
    static func isSilence(text: String, confidence: Float, wordCount: Int) -> Bool {
        text.isEmpty || (confidence <= 0.1 && wordCount == 0)
    }

    /// Groups words into segments for speaker assignment, breaking after a pause of more than 0.6 s or
    /// after sentence-final punctuation.
    static func segments(from words: [SpokenWord]) -> [TimedSegment] {
        var segments: [TimedSegment] = []
        var current: [SpokenWord] = []

        func flush() {
            defer { current = [] }
            guard let first = current.first, let last = current.last else { return }
            // Same annotation filter as the full text, so speaker-labelled output can't reintroduce one
            let text = TranscriptionService.stripNonSpeech(current.map(\.text).joined(separator: " "))
            guard !text.isEmpty else { return }
            segments.append(TimedSegment(startSeconds: first.start, endSeconds: last.end, text: text))
        }

        for word in words {
            if let previous = current.last, word.start - previous.end > 0.6 { flush() }
            current.append(word)
            if let end = word.text.last, ".?!".contains(end) { flush() }
        }
        flush()
        return segments
    }
}

/// One recognised word with its time span, independent of FluidAudio's types.
struct SpokenWord: Equatable {
    let text: String
    let start: Double
    let end: Double
}
