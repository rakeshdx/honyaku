import XCTest
@testable import Honyaku

/// Runs real rewrites with Qwen3-4B (or, without it, another installed cleanup model) on fixed transcripts.
/// Requires INTEGRATION_TESTS=1 (pass TEST_RUNNER_INTEGRATION_TESTS=1 to xcodebuild). Reads the models
/// folder, never writes to it.
final class RewriteIntegrationTests: IntegrationTestBase {

    func testJiraTicketHasItsSectionsAndInventsNothing() async throws {
        let transcript = "the export button on the reports page does nothing when you click it, it should download a CSV"
        let output = try await rewrite(transcript, as: .jiraTicket)
        let lower = output.lowercased()
        XCTAssertTrue(lower.hasPrefix("summary:"), "Starts with the Summary section: \(output)")
        XCTAssertTrue(lower.contains("acceptance criteria:"), output)
        XCTAssertFalse(lower.contains("steps to reproduce"), "No steps were described: \(output)")
        assertInventsNothing(output, transcript: transcript)
        XCTAssertFalse(output.contains("**") || output.contains("#"), "Plain text, not Markdown: \(output)")
    }

    func testChatMessageIsShortAndInventsNothing() async throws {
        let transcript = "um can you take a look at the login bug when you get a chance, no rush"
        let output = try await rewrite(transcript, as: .chatMessage)
        XCTAssertFalse(output.isEmpty)
        XCTAssertFalse(output.lowercased().contains("summary:"), "A chat message has no sections: \(output)")
        XCTAssertFalse(output.lowercased().hasPrefix("rewrit"), "No echoed heading: \(output)")
        let sentences = output.split { ".!?".contains($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertLessThanOrEqual(sentences.count, 3, output)
        assertInventsNothing(output, transcript: transcript)
    }

    /// `fix-rewrite-grounding`: the user's vocabulary (in memory, never their real file) and a short agent
    /// prompt mentioning only P+. The rewrite step, with the real model, must never end up pasting Paramount+
    /// or POPS: the prompt names only P+, and the invention check catches the model adding the others.
    @MainActor
    func testAShortAgentPromptNeverAddsUnsaidVocabularyTerms() async throws {
        let installed = ModelRegistry.cleanupModels.filter(ModelInstaller.isInstalled)
        try XCTSkipIf(installed.isEmpty, "No cleanup model is downloaded")
        let model = installed.first { $0.id == "qwen3-4b-2507" } ?? installed[0]
        let terms = [
            VocabularyTerm(term: "Paramount+", heardAs: ["Paramount plus", "para mount plus"]),
            VocabularyTerm(term: "P+", heardAs: ["P Plus"]),
            VocabularyTerm(term: "POPS"),
        ]
        let snapshot = VocabularySnapshot()
        snapshot.matcher = VocabularyMatcher(terms: terms)
        var context = DictationContext(mode: .rewrite)
        context.vocabularyMatcher = snapshot.matcher
        let transcript = VocabularyCorrectionStage(snapshot: snapshot)
            .apply("check that the p plus login works on staging", context: &context)
        XCTAssertEqual(transcript, "check that the P+ login works on staging")
        XCTAssertEqual(context.cleanupRules, ["Write these terms exactly as listed: P+."])

        let plan = RewritePlan(template: .agentPrompt)
        let result = await RewriteStep.run(transcript, plan: plan, installed: true, context: &context,
                                           cleanup: CleanupService(modelID: model.id))
        print("Rewrite with \(model.id), mode afterwards \(context.mode), notices \(context.notices):\n\(result)")
        XCTAssertFalse(result.contains("POPS"), result)
        XCTAssertFalse(result.contains("Paramount+"), result)
        XCTAssertTrue(result.contains("P+"), "The term that was said is kept: \(result)")
    }

    // MARK: - Helpers

    private func rewrite(_ transcript: String, as template: RewriteTemplateID) async throws -> String {
        let installed = ModelRegistry.cleanupModels.filter(ModelInstaller.isInstalled)
        try XCTSkipIf(installed.isEmpty, "No cleanup model is downloaded")
        let model = installed.first { $0.id == "qwen3-4b-2507" } ?? installed[0]
        let service = CleanupService(modelID: model.id)
        let plan = RewritePlan(template: template)
        let request = plan.request(for: transcript, extraRules: [], englishFillers: true)
        let output = RewritePrompt.stripEchoes(try await service.clean(transcript, request: request), plan: plan)
        // Shown with any failure, so a weak result can be told apart from a weak model
        print("Rewrite with \(model.id) as \(template.rawValue):\n\(output)")
        return output
    }

    /// No numbers, ticket IDs, links or addresses the speaker didn't say (these transcripts have none).
    private func assertInventsNothing(_ output: String, transcript: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(output.rangeOfCharacter(from: .decimalDigits), "Invented a number: \(output)", file: file, line: line)
        XCTAssertNil(output.range(of: #"\b[A-Z]{2,}-\d+\b"#, options: .regularExpression),
                     "Invented a ticket ID: \(output)", file: file, line: line)
        XCTAssertFalse(output.lowercased().contains("http") || output.contains("www."),
                       "Invented a link: \(output)", file: file, line: line)
        XCTAssertFalse(output.contains("@"), "Invented an address or mention: \(output)", file: file, line: line)
    }
}
