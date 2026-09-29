import XCTest
@testable import Honyaku

final class CleanupServiceTests: XCTestCase {

    // MARK: keepsContent

    func testDroppedContentWordFailsCheck() {
        XCTAssertFalse(CleanupService.keepsContent(raw: "Are you working or not?", cleaned: "Are you working?"))
    }

    func testFillerRemovalPassesCheck() {
        XCTAssertTrue(CleanupService.keepsContent(raw: "um I think we should uh ship it",
                                                  cleaned: "I think we should ship it."))
    }

    func testFillerPhraseRemovalPassesCheck() {
        XCTAssertTrue(CleanupService.keepsContent(raw: "it's, you know, sort of done", cleaned: "It's done."))
    }

    func testPunctuationAndCaseChangesPassCheck() {
        XCTAssertTrue(CleanupService.keepsContent(raw: "hello world how are you", cleaned: "Hello, world. How are you?"))
    }

    func testDroppedSpeakerLabelFailsCheck() {
        XCTAssertFalse(CleanupService.keepsContent(raw: "[Speaker 1] hi [Speaker 2] hello",
                                                   cleaned: "[Speaker 1] Hi. Hello."))
    }

    func testRepeatedWordMustSurviveEachTime() {
        XCTAssertFalse(CleanupService.keepsContent(raw: "no no no", cleaned: "No."))
    }

    // MARK: removeUnambiguousFillers

    func testFallbackRemovesOnlyUnambiguousFillers() {
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("um are you working or not"), "are you working or not")
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("Hmm, I like it, uh, a lot"), "I like it, a lot")
    }

    // MARK: stripDelimiters

    func testEchoedDelimitersAreRemoved() {
        XCTAssertEqual(CleanupService.stripDelimiters("\"\"\"\nAre you working or not?\n\"\"\""), "Are you working or not?")
        XCTAssertEqual(CleanupService.stripDelimiters("\"Hello.\""), "Hello.")
        XCTAssertEqual(CleanupService.stripDelimiters("Transcript to clean: Hello."), "Hello.")
    }
}
