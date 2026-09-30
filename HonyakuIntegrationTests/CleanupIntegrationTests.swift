import XCTest
@testable import Honyaku

/// Runs every installed cleanup model, pinned by ID so the user's saved selection doesn't decide what's
/// tested. Requires INTEGRATION_TESTS=1 (pass TEST_RUNNER_INTEGRATION_TESTS=1 to xcodebuild). Asserts on
/// each model's own output, so the faithfulness fallback can't hide a model that drops or adds words.
final class CleanupIntegrationTests: IntegrationTestBase {

    func testQuestionKeepsEveryWord() async throws {
        try await forEachModel { try await self.assertFaithful("Are you working or not?", with: $0) }
    }

    func testFillersAreRemoved() async throws {
        try await forEachModel { model in
            let output = try await self.assertFaithful("um I think we should uh ship it", with: model)
            self.assertFillersGone(output, model: model)
        }
    }

    /// Share no content words with the prompt's examples (only function words like "I", "we", "it"),
    /// so a pass isn't the model copying them
    func testHeldOutSentencesStayFaithful() async throws {
        try await forEachModel { model in
            for raw in [
                "I guess we could um probably try it again",
                "honestly I don't know if it works",
                "please uh call the dentist and book an appointment",
                "the invoice goes out on Friday",
            ] {
                let output = try await self.assertFaithful(raw, with: model)
                self.assertFillersGone(output, model: model)
            }
        }
    }

    /// A bare "so" / "like" is content to the check, so the model must keep it rather than trigger the fallback
    func testBareSoAndLikeAreKept() async throws {
        try await forEachModel { model in
            try await self.assertFaithful("so the printer on floor two is broken again", with: model)
            try await self.assertFaithful("I like the new layout for the dashboard", with: model)
        }
    }

    func testSetOffLikeMayBeRemoved() async throws {
        try await forEachModel { try await self.assertFaithful("the parking garage was, like, completely full today", with: $0) }
    }

    // MARK: - Helpers

    private func forEachModel(_ body: (ModelInfo) async throws -> Void) async throws {
        let installed = ModelRegistry.cleanupModels.filter(ModelInstaller.isInstalled)
        try XCTSkipIf(installed.isEmpty, "No cleanup model is downloaded")
        for model in installed { try await body(model) }
    }

    /// The best tier must drop fillers itself; the fast tier sometimes leaves one, which the app removes
    /// before pasting (spec: unambiguous fillers never reach the paste), so only the pasted text is checked.
    private func assertFillersGone(_ output: String, model: ModelInfo, file: StaticString = #filePath, line: UInt = #line) {
        let checked = model.tier == "best" ? output : CleanupService.removeUnambiguousFillers(output)
        let words = checked.lowercased().split { !$0.isLetter }
        XCTAssertTrue(Set(words).isDisjoint(with: ["um", "umm", "uh", "hmm"]),
                      "\(model.id) left fillers in: \(checked)", file: file, line: line)
    }

    @discardableResult
    private func assertFaithful(_ raw: String, with model: ModelInfo,
                                file: StaticString = #filePath, line: UInt = #line) async throws -> String {
        let output = try await CleanupService(modelID: model.id).modelOutput(for: raw, prompt: CleanupService.defaultPrompt)
        XCTAssertTrue(CleanupService.isFaithful(raw: raw, cleaned: output), "\(model.id): \(raw) -> \(output)",
                      file: file, line: line)
        return output
    }
}
