import XCTest
@testable import Honyaku

final class WhisperHintTests: XCTestCase {
    /// One token per word or punctuation mark: easy to count by hand.
    private func fakeEncode(_ text: String) -> [Int] {
        let words = text.split(whereSeparator: { (character: Character) in character == " " || character == "," })
        let commas = text.filter { $0 == "," }.count
        return words.map { $0.count } + Array(repeating: 0, count: commas)
    }

    func testTermsKeepTheirOrderWithTheTopTermLast() throws {
        var encoded: [String] = []
        let tokens = WhisperHint.promptTokens(glossary: ["Pluto TV", "Jira"]) { encoded.append($0); return [1] }
        XCTAssertNotNil(tokens)
        XCTAssertEqual(encoded.last, " Pluto TV, Jira")
    }

    func testStopsBeforeTheCapWithoutCuttingATerm() throws {
        // 200 terms of 3 tokens each, plus a token per comma: only the whole terms that fit in 111 tokens
        let glossary = (0..<200).map { "word\($0) and more" }
        var lastText = ""
        let tokens = try XCTUnwrap(WhisperHint.promptTokens(glossary: glossary) { text in
            lastText = text
            return fakeEncode(text)
        })
        XCTAssertLessThanOrEqual(tokens.count, WhisperHint.maxTokens)
        // The end of the glossary (the top of the list) is what's kept
        XCTAssertTrue(lastText.hasSuffix("word199 and more"))
        // n terms cost 3n words plus n - 1 commas: 28 terms are exactly 111 tokens, 29 would be 115
        let kept = WhisperHint.text(for: Array(glossary.suffix(28)))
        XCTAssertEqual(tokens, fakeEncode(kept))
        XCTAssertEqual(tokens.count, 111)
    }

    func testNoTokensForAnEmptyGlossaryOrATermThatDoesntFit() {
        XCTAssertNil(WhisperHint.promptTokens(glossary: []) { _ in [1] })
        XCTAssertNil(WhisperHint.promptTokens(glossary: ["huge"]) { _ in Array(repeating: 1, count: 200) })
    }

    func testEstimateMarksTermsFromTheTop() {
        XCTAssertEqual(WhisperHint.estimatedTermCount(["Jira", "Pluto TV"]), 2)
        let many = (0..<100).map { "Term number \($0)" }  // ~4 + 1 tokens each
        let count = WhisperHint.estimatedTermCount(many)
        XCTAssertGreaterThan(count, 15)
        XCTAssertLessThan(count, 30)
    }
}
