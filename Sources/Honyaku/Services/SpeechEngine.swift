import Foundation

/// A loaded speech model. `TranscriptionService` owns loading, the timeout and temp-file cleanup;
/// an engine only turns one dictation's audio into text.
protocol SpeechEngine: Sendable {
    /// `samples16k` is the dictation as 16 kHz mono floats when the caller already has it;
    /// engines that need it read `audioURL` otherwise.
    func transcribe(audioURL: URL, samples16k: [Float]?) async throws -> TranscriptionResult
}
