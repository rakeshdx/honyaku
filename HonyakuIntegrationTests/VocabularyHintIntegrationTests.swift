import WhisperKit
import XCTest
@testable import Honyaku

/// Whisper with the vocabulary glossary as its prompt, on clips rendered with `say`.
/// Requires INTEGRATION_TESTS=1 (pass TEST_RUNNER_INTEGRATION_TESTS=1 to xcodebuild) and Whisper on disk.
/// Reads the models folder; never writes it, the user's settings or the vocabulary.
final class VocabularyHintIntegrationTests: IntegrationTestBase {
    /// Most important last, as the pipeline sends it. "Paramount+" is never spoken.
    private let glossary = ["Paramount+", "Jira", "Pluto TV"]

    func testWhisperSpellsListedTermsAndDoesntEchoTheGlossary() async throws {
        let model = try XCTUnwrap(ModelRegistry.speechModels.first { $0.engine == .whisperKit })
        try XCTSkipUnless(ModelInstaller.isInstalled(model), "Whisper isn't installed")
        let service = TranscriptionService()
        let sentence = try Self.renderSpeech("Please file a Jira ticket for the Pluto TV launch.", name: "vocab-sentence")
        let short = try Self.renderSpeech("Yes.", name: "vocab-short")

        // Warm-up, so load time isn't counted
        _ = try await transcribe(sentence, with: service, model: model, glossary: [])

        let (plain, plainTime) = try await timed { try await self.transcribe(sentence, with: service, model: model, glossary: []) }
        let (hinted, hintedTime) = try await timed { try await self.transcribe(sentence, with: service, model: model, glossary: self.glossary) }
        print("Vocabulary hint, without: \(plain) (\(plainTime))")
        print("Vocabulary hint, with:    \(hinted) (\(hintedTime))")

        XCTAssertTrue(hinted.contains("Pluto TV"), "Listed term spelled as listed: \(hinted)")
        XCTAssertTrue(hinted.contains("Jira"), "Listed term spelled as listed: \(hinted)")
        XCTAssertFalse(hinted.lowercased().contains("paramount"), "Glossary text that wasn't said: \(hinted)")

        let shortHinted = try await transcribe(short, with: service, model: model, glossary: glossary)
        print("Vocabulary hint, short clip: \(shortHinted)")
        for term in glossary {
            XCTAssertFalse(shortHinted.lowercased().contains(term.lowercased()), "Echoed \(term) into \"\(shortHinted)\"")
        }
    }

    private func transcribe(_ clip: URL, with service: TranscriptionService, model: Honyaku.ModelInfo,
                            glossary: [String]) async throws -> String {
        // The service deletes its input, so hand it a copy named like a real dictation
        let copy = FileManager.default.temporaryDirectory.appending(path: "honyaku_vocab_\(UUID()).wav")
        try FileManager.default.copyItem(at: clip, to: copy)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: clip.path)
        return try await service.transcribe(audioURL: copy, samples16k: samples, modelID: model.id,
                                            hints: SpeechHints(language: "en", glossary: glossary)).rawText
    }

    private func timed(_ work: () async throws -> String) async throws -> (String, Duration) {
        let start = ContinuousClock.now
        let text = try await work()
        return (text, ContinuousClock.now - start)
    }

    private static let workDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appending(path: "honyaku-vocabulary-integration")
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

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) failed")
    }
}
