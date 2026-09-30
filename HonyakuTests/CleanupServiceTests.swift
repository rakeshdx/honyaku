import XCTest
@testable import Honyaku

final class CleanupServiceTests: XCTestCase {

    // MARK: isFaithful — spec scenarios

    func testDroppedContentWordIsRejected() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "Are you working or not?", cleaned: "Are you working?"))
    }

    func testFillerRemovalIsAccepted() {
        XCTAssertTrue(CleanupService.isFaithful(raw: "um I think we should uh ship it", cleaned: "I think we should ship it."))
    }

    func testWordThatOnlyLooksLikeFillerMustStay() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "I like it", cleaned: "I it."))
        XCTAssertFalse(CleanupService.isFaithful(raw: "turn right here", cleaned: "Turn here."))
        XCTAssertFalse(CleanupService.isFaithful(raw: "I think so", cleaned: "I think."))
        XCTAssertFalse(CleanupService.isFaithful(raw: "do you know him", cleaned: "Do him?"))
    }

    func testSetOffFillerMayBeRemoved() {
        XCTAssertTrue(CleanupService.isFaithful(raw: "I was, like, going home", cleaned: "I was going home."))
        XCTAssertTrue(CleanupService.isFaithful(raw: "So, we ship it", cleaned: "We ship it."))
        XCTAssertTrue(CleanupService.isFaithful(raw: "it's, you know, done", cleaned: "It's done."))
    }

    func testAddedWordsAreRejected() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "Are you working or not?",
                                                 cleaned: "Are you working or not? Yes, I am."))
        XCTAssertFalse(CleanupService.isFaithful(raw: "send it", cleaned: "Sure! Send it."))
    }

    func testConsecutiveSetOffFillersMayBeRemoved() {
        XCTAssertTrue(CleanupService.isFaithful(raw: "Right, so, we ship it", cleaned: "We ship it."))
        XCTAssertTrue(CleanupService.isFaithful(raw: "so, like, I think so", cleaned: "I think so."))
    }

    func testReorderedWordsAreRejected() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "I did not say it was done", cleaned: "I did say it was not done."))
    }

    func testIntroducedLineBreakOrShellCharacterIsRejected() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "list the files", cleaned: "List the files.\n"))
        XCTAssertFalse(CleanupService.isFaithful(raw: "list the files", cleaned: "List the files; `rm`"))
        XCTAssertFalse(CleanupService.isFaithful(raw: "list the files", cleaned: "List | the files."))
    }

    func testPromptExamplesPassTheCheck() {
        // Following the prompt's own worked examples must never trigger the fallback
        XCTAssertTrue(CleanupService.isFaithful(raw: "um so I think we should uh maybe ship it or not",
                                                cleaned: "So I think we should maybe ship it or not."))
        XCTAssertTrue(CleanupService.isFaithful(raw: "are you, like, coming tomorrow or not",
                                                cleaned: "Are you coming tomorrow or not?"))
        XCTAssertTrue(CleanupService.defaultPrompt.contains("Cleaned: So I think we should maybe ship it or not."))
        XCTAssertTrue(CleanupService.defaultPrompt.contains("Transcript: are you, like, coming tomorrow or not"))
    }

    // MARK: isFaithful — tokenisation

    func testPunctuationAndCaseChangesAreAccepted() {
        XCTAssertTrue(CleanupService.isFaithful(raw: "hello world how are you", cleaned: "Hello, world. How are you?"))
    }

    func testCurlyApostropheMatchesStraightOne() {
        XCTAssertTrue(CleanupService.isFaithful(raw: "I don't know", cleaned: "I don’t know."))
    }

    func testDroppedSpeakerLabelIsRejected() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "[Speaker 1] hi [Speaker 2] hello", cleaned: "[Speaker 1] Hi. Hello."))
    }

    func testRepeatedWordMustSurviveEachTime() {
        XCTAssertFalse(CleanupService.isFaithful(raw: "no no no", cleaned: "No."))
    }

    // MARK: removeUnambiguousFillers

    func testFallbackRemovesOnlyUnambiguousFillers() {
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("um are you working or not"), "are you working or not")
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("Hmm, I like it, uh, a lot"), "I like it, a lot")
    }

    func testFallbackKeepsHyphenatedWordsAndTidiesLeadingPunctuation() {
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("uh-huh, that works"), "uh-huh, that works")
        XCTAssertEqual(CleanupService.removeUnambiguousFillers("Um. So we go"), "So we go")
    }

    // MARK: stripDelimiters

    func testEchoedFramingIsRemoved() {
        XCTAssertEqual(CleanupService.stripDelimiters("\"\"\"\nAre you working or not?\n\"\"\""), "Are you working or not?")
        XCTAssertEqual(CleanupService.stripDelimiters("Transcript to clean: Hello."), "Hello.")
        XCTAssertEqual(CleanupService.stripDelimiters("Cleaned: I think we should ship it."), "I think we should ship it.")
    }

    func testWrappingQuotesRemovedButDictatedQuotesKept() {
        XCTAssertEqual(CleanupService.stripDelimiters("\"Hello.\""), "Hello.")
        XCTAssertEqual(CleanupService.stripDelimiters("\"Hi,\" she said \"bye.\""), "\"Hi,\" she said \"bye.\"")
    }
}
