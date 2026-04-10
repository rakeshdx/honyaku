import XCTest
@testable import Honyaku

final class TranscriptionIntegrationTests: IntegrationTestBase {

    func testFillerHeavyFixtureProducesNonEmptyTranscript() async throws {
        let audioURL = try fixtureURL(named: "filler_heavy.wav")
        let service = TranscriptionService()
        let result = try await service.transcribe(audioURL: audioURL, modelID: ModelRegistry.defaultSpeechModelID)
        XCTAssertFalse(result.rawText.trimmingCharacters(in: .whitespaces).isEmpty,
                       "Transcription of filler_heavy.wav should produce non-empty text")
        let fillers = ["um", "uh", "like you know"]
        let hasFillers = fillers.contains { result.rawText.lowercased().contains($0) }
        XCTAssertTrue(hasFillers, "Raw transcript of filler_heavy.wav should contain at least one filler word")
    }

    func testCleanupRemovesFillersFromFillerHeavyFixture() async throws {
        let audioURL = try fixtureURL(named: "filler_heavy.wav")
        let transcriptionService = TranscriptionService()
        let cleanupService = CleanupService()

        let result = try await transcriptionService.transcribe(audioURL: audioURL, modelID: ModelRegistry.defaultSpeechModelID)
        let cleaned = try await cleanupService.clean(result.rawText, prompt: CleanupService.defaultPrompt)

        let fillers = ["um,", "uh,", " um ", " uh "]
        let hasFillers = fillers.contains { cleaned.lowercased().contains($0) }
        XCTAssertFalse(hasFillers, "Cleaned text should not contain filler words: \(cleaned)")
    }

    func testCleanMonologueNotCorrupted() async throws {
        let audioURL = try fixtureURL(named: "clean_monologue.wav")
        let transcriptionService = TranscriptionService()
        let cleanupService = CleanupService()

        let result = try await transcriptionService.transcribe(audioURL: audioURL, modelID: ModelRegistry.defaultSpeechModelID)
        let cleaned = try await cleanupService.clean(result.rawText, prompt: CleanupService.defaultPrompt)

        XCTAssertFalse(cleaned.isEmpty, "Clean monologue should produce non-empty cleaned output")
        // The word count should not drop dramatically (< 50% of original is suspicious)
        let rawWords = result.rawText.split(separator: " ").count
        let cleanWords = cleaned.split(separator: " ").count
        if rawWords > 0 {
            XCTAssertGreaterThan(Double(cleanWords) / Double(rawWords), 0.5,
                                 "Cleaned output should not lose more than half the words of clean input")
        }
    }

    func testSilenceFixtureProducesNoTranscriptAndNoOutput() async throws {
        let audioURL = try fixtureURL(named: "silence.wav")
        let service = TranscriptionService()
        do {
            let result = try await service.transcribe(audioURL: audioURL, modelID: ModelRegistry.defaultSpeechModelID)
            XCTAssertTrue(result.rawText.trimmingCharacters(in: .whitespaces).isEmpty,
                          "Silence fixture should produce empty transcript")
        } catch TranscriptionError.emptyResult {
            // Also acceptable — empty result throws
        }
        // Verify no text was left on the pasteboard
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }
}
