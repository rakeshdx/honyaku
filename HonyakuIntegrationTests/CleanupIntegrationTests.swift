import XCTest
@testable import Honyaku

/// Runs the selected on-disk cleanup model. Requires INTEGRATION_TESTS=1 (pass TEST_RUNNER_INTEGRATION_TESTS=1
/// to xcodebuild) and a downloaded model. Asserts on the model's own output, so the faithfulness fallback
/// can't hide a model that drops or adds words.
final class CleanupIntegrationTests: IntegrationTestBase {
    private let service = CleanupService()

    func testQuestionKeepsEveryWord() async throws {
        try await assertFaithful("Are you working or not?")
    }

    func testFillersAreRemoved() async throws {
        let output = try await assertFaithful("um I think we should uh ship it")
        let words = output.lowercased().split { !$0.isLetter }
        XCTAssertFalse(words.contains("um") || words.contains("uh"), "Got: \(output)")
    }

    /// Share no words with the prompt's examples, so a pass isn't the model copying them
    func testHeldOutSentencesStayFaithful() async throws {
        for raw in [
            "I guess we could um probably try it again",
            "honestly I don't know if it works",
            "please uh call the dentist and book an appointment",
            "the invoice goes out on Friday",
        ] {
            try await assertFaithful(raw)
        }
    }

    @discardableResult
    private func assertFaithful(_ raw: String, file: StaticString = #filePath, line: UInt = #line) async throws -> String {
        let output: String
        do {
            output = try await service.modelOutput(for: raw, prompt: CleanupService.defaultPrompt)
        } catch CleanupError.modelNotLoaded {
            throw XCTSkip("Selected cleanup model is not downloaded")
        }
        XCTAssertTrue(CleanupService.isFaithful(raw: raw, cleaned: output), "\(raw) -> \(output)", file: file, line: line)
        return output
    }
}
