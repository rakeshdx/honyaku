import AVFoundation
import WhisperKit
import XCTest
@testable import Honyaku

/// Measures every installed speech and cleanup model on this Mac, so defaults come from numbers.
/// Requires INTEGRATION_TESTS=1 (pass TEST_RUNNER_INTEGRATION_TESTS=1 to xcodebuild) and the models on
/// disk; models that aren't installed are skipped. Prints a table; fails only on the spec's limits.
final class ModelBenchmarkTests: IntegrationTestBase {

    /// 1–8 s of speech each. Rendered with `say`, so this compares engines against each other on clean
    /// audio rather than giving a real-microphone WER.
    private static let sentences = [
        "Yes.",
        "Send it now.",
        "Can you call me back tomorrow morning?",
        "The meeting moved to three thirty on Thursday.",
        "Please add milk, eggs and coffee to the shopping list.",
        "I think we should ship the release on Friday, not Monday.",
        "Remind me to renew the passport before the end of October.",
        "The quarterly numbers look better than we expected, especially in Europe.",
        "Could you forward the invoice to the finance team and copy me on it?",
        "Let's schedule a short review once the designs are ready next week.",
        "My flight lands at seven forty, so I'll be at the office around nine.",
        "We need to decide whether the new onboarding flow replaces the old one or runs alongside it.",
    ]

    // MARK: - Speech

    func testSpeechEngines() async throws {
        let clips = try Self.sentences.enumerated().map { try Self.renderSpeech($0.element, name: "clip\($0.offset)") }
        var report = ["| Speech model | WER | Median time | Slowest |", "|---|---|---|---|"]
        var measuredAny = false

        for model in ModelRegistry.speechModels where ModelInstaller.isInstalled(model) {
            measuredAny = true
            let service = TranscriptionService()
            // Warm-up call so load and compile time aren't counted
            _ = try await transcribe(clips[0], with: service, model: model)

            var errors = 0, words = 0
            var times: [Double] = []
            for (clip, reference) in zip(clips, Self.sentences) {
                let start = ContinuousClock.now
                let text = try await transcribe(clip, with: service, model: model)
                times.append((ContinuousClock.now - start).seconds)
                let (e, n) = Self.wordErrors(reference: reference, hypothesis: text)
                errors += e; words += n
            }
            let wer = Double(errors) / Double(words)
            report.append("| \(model.id) | \(Self.percent(wer)) | \(Self.ms(Self.median(times))) | \(Self.ms(times.max() ?? 0)) |")
            XCTAssertLessThan(wer, 0.3, "\(model.id) is far off on clean TTS audio — the engine is likely broken")

            // Silence must come back empty so the pipeline discards it
            let silence = try Self.renderSilence(seconds: 2)
            let silent = try await transcribe(silence, with: service, model: model)
            XCTAssertEqual(silent, "", "\(model.id) produced text for silence")
        }
        try XCTSkipUnless(measuredAny, "No speech model is installed")
        print(report.joined(separator: "\n"))
    }

    // MARK: - Cleanup

    /// Held-out dictations (no words shared with the prompt's examples beyond function words) plus the
    /// speech sentences with fillers added.
    private static let cleanupInputs = [
        "I guess we could um probably try it again",
        "honestly I don't know if it works",
        "please uh call the dentist and book an appointment",
        "the invoice goes out on Friday",
        "so the printer on floor two is broken again",
        "the parking garage was, like, completely full today",
        "um can you call me back tomorrow morning",
        "remind me to uh renew the passport before the end of October",
    ]

    func testCleanupTiers() async throws {
        var report = ["| Cleanup model | Faithful | Cold (first) | Median | 90th pct |", "|---|---|---|---|---|"]
        var measuredAny = false

        for model in ModelRegistry.cleanupModels where ModelInstaller.isInstalled(model) {
            measuredAny = true
            let service = CleanupService(modelID: model.id)
            let prompt = CleanupService.defaultPrompt

            let coldStart = ContinuousClock.now
            _ = try await service.modelOutput(for: "hello there", prompt: prompt)
            let cold = (ContinuousClock.now - coldStart).seconds

            var faithful = 0
            var times: [Double] = []
            for raw in Self.cleanupInputs {
                let start = ContinuousClock.now
                let output = try await service.modelOutput(for: raw, prompt: prompt)
                times.append((ContinuousClock.now - start).seconds)
                if CleanupService.isFaithful(raw: raw, cleaned: output) { faithful += 1 }
            }
            let median = Self.median(times)
            report.append("| \(model.id) | \(faithful)/\(Self.cleanupInputs.count) | \(Self.ms(cold)) | \(Self.ms(median)) | \(Self.ms(Self.percentile(times, 0.9))) |")
            if model.tier == "fast" {
                XCTAssertLessThan(median, 0.5, "Spec: the Fast tier's median cleanup time must be under 0.5 s")
            }
        }
        try XCTSkipUnless(measuredAny, "No cleanup model is installed")
        print(report.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private func transcribe(_ clip: URL, with service: TranscriptionService, model: Honyaku.ModelInfo) async throws -> String {
        // The service deletes its input, so hand it a copy named like a real dictation
        let copy = FileManager.default.temporaryDirectory.appending(path: "honyaku_bench_\(UUID()).wav")
        try FileManager.default.copyItem(at: clip, to: copy)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: clip.path)
        return try await service.transcribe(audioURL: copy, samples16k: samples, modelID: model.id).rawText
    }

    private static let workDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appending(path: "honyaku-benchmark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Speaks `text` with the system voice into a 16 kHz mono WAV.
    private static func renderSpeech(_ text: String, name: String) throws -> URL {
        let aiff = workDir.appending(path: "\(name).aiff")
        let wav = workDir.appending(path: "\(name).wav")
        try run("/usr/bin/say", ["-o", aiff.path, text])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        return wav
    }

    private static func renderSilence(seconds: Double) throws -> URL {
        let url = workDir.appending(path: "silence.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames  // zero-filled
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) failed")
    }

    /// Word-level edit distance after lowercasing and dropping punctuation; returns (errors, reference words).
    static func wordErrors(reference: String, hypothesis: String) -> (Int, Int) {
        func words(_ s: String) -> [String] {
            s.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
        }
        let r = words(reference), h = words(hypothesis)
        var row = Array(0...h.count)
        for i in 1...max(r.count, 1) where !r.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: h.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (r[i - 1] == h[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return (r.isEmpty ? h.count : row[h.count], r.count)
    }

    private static func median(_ values: [Double]) -> Double { percentile(values, 0.5) }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    private static func ms(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }
    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
