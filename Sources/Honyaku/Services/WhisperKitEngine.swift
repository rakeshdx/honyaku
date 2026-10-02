import AVFoundation
import Foundation
import WhisperKit

/// Whisper via WhisperKit: the multilingual engine.
final class WhisperKitEngine: SpeechEngine, @unchecked Sendable {
    // WhisperKit isn't Sendable; TranscriptionService runs one dictation at a time
    private let kit: WhisperKit
    /// The last vocabulary glossary and its prompt tokens, so an unchanged list isn't re-encoded each time.
    private var hintCache: (glossary: [String], tokens: [Int]?)?
    private var hasPromptBlankFilter = false

    init(kit: WhisperKit) {
        self.kit = kit
    }

    func transcribe(audioURL: URL, samples16k: [Float]?, hints: SpeechHints) async throws -> TranscriptionResult {
        // The pipeline reads the setting on every dictation, so a change in Settings applies at once
        let language = hints.language
        var options = TranscriptionService.decodeOptions(forDurationSeconds: Self.duration(of: audioURL), language: language)
        if let tokens = promptTokens(for: hints.glossary) {
            options.promptTokens = tokens
            options.usePrefillPrompt = true
        }
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
            // With a language chosen WhisperKit reports its default ("en"), not the language it was given
            language: language ?? first.language,
            durationSeconds: duration,
            timedSegments: timed
        )
    }

    /// The vocabulary as Whisper's previous-context prompt (see `WhisperHint`); nil without a glossary.
    private func promptTokens(for glossary: [String]) -> [Int]? {
        guard !glossary.isEmpty, let tokenizer = kit.tokenizer else { return nil }
        if !hasPromptBlankFilter {
            // Without it, WhisperKit 0.18.0 ends a prompted window before its first word (see the filter)
            kit.textDecoder.logitsFilters = (kit.textDecoder.logitsFilters ?? [])
                + [WhisperPromptBlankFilter(specialTokens: tokenizer.specialTokens)]
            hasPromptBlankFilter = true
        }
        if let hintCache, hintCache.glossary == glossary { return hintCache.tokens }
        let specialBegin = tokenizer.specialTokens.specialTokenBegin
        let tokens = WhisperHint.promptTokens(glossary: glossary) { text in
            tokenizer.encode(text: text).filter { $0 < specialBegin }
        }
        hintCache = (glossary, tokens)
        return tokens
    }

    private static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
