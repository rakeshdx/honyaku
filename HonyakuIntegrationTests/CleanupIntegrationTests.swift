import XCTest
@testable import Honyaku

/// Runs the selected on-disk cleanup model. Requires INTEGRATION_TESTS=1 and a downloaded model.
final class CleanupIntegrationTests: IntegrationTestBase {
    private let service = CleanupService()

    func testQuestionKeepsEveryWord() async throws {
        let cleaned = try await clean("Are you working or not?")
        XCTAssertTrue(cleaned.lowercased().contains("or not"), "Got: \(cleaned)")
    }

    func testFillersAreRemoved() async throws {
        let cleaned = try await clean("um I think we should uh ship it")
        let words = cleaned.lowercased().split { !$0.isLetter }
        XCTAssertFalse(words.contains("um") || words.contains("uh"), "Got: \(cleaned)")
        XCTAssertTrue(cleaned.lowercased().contains("i think we should ship it"), "Got: \(cleaned)")
    }

    /// Phrasings that don't appear in the prompt's examples, so a pass isn't just the model copying them
    func testHeldOutSentencesKeepContent() async throws {
        let cases = [
            "can you uh send it today or maybe tomorrow",
            "I guess we could um probably try it again",
            "do you want to grab lunch or not",
            "honestly I don't know if it works",
        ]
        for raw in cases {
            let cleaned = try await clean(raw)
            XCTAssertTrue(CleanupService.keepsContent(raw: raw, cleaned: cleaned), "\(raw) -> \(cleaned)")
        }
    }

    private func clean(_ text: String) async throws -> String {
        do {
            return try await service.clean(text, prompt: CleanupService.defaultPrompt)
        } catch CleanupError.modelNotLoaded {
            throw XCTSkip("Selected cleanup model is not downloaded")
        }
    }
}
