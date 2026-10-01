import XCTest
@testable import Honyaku

final class VocabularyMatcherTests: XCTestCase {
    private func corrected(_ text: String, _ terms: [VocabularyTerm]) -> String {
        VocabularyMatcher(terms: terms).apply(text)
    }

    func testMisheardProductName() {
        let terms = [VocabularyTerm(term: "Paramount+", heardAs: ["paramount plus"])]
        XCTAssertEqual(corrected("I'm testing paramount plus today.", terms), "I'm testing Paramount+ today.")
    }

    func testCaseFixedWithNoHeardAsSpelling() {
        XCTAssertEqual(corrected("file a jira, then ping me", [VocabularyTerm(term: "Jira")]), "file a Jira, then ping me")
    }

    func testPartOfALongerWordIsLeftAlone() {
        let terms = [VocabularyTerm(term: "Jira")]
        XCTAssertEqual(corrected("jiras are piling up", terms), "jiras are piling up")
        XCTAssertEqual(corrected("ajira and jira2", terms), "ajira and jira2")
    }

    func testPossessiveIsKept() {
        let terms = [VocabularyTerm(term: "Pluto TV", heardAs: ["pluto tv"])]
        XCTAssertEqual(corrected("pluto tv's guide", terms), "Pluto TV's guide")
        XCTAssertEqual(corrected("pluto tv\u{2019}s guide", terms), "Pluto TV\u{2019}s guide")
    }

    func testCurlyAndStraightApostrophesMatchAlike() {
        let terms = [VocabularyTerm(term: "O'Neil", heardAs: ["o neil"])]
        XCTAssertEqual(corrected("ask o\u{2019}neil", terms), "ask O'Neil")
    }

    func testLongestMatchWins() {
        let terms = [VocabularyTerm(term: "Paramount"), VocabularyTerm(term: "Paramount+", heardAs: ["paramount plus"])]
        XCTAssertEqual(corrected("paramount plus launched", terms), "Paramount+ launched")
        XCTAssertEqual(corrected("paramount launched", terms), "Paramount launched")
    }

    func testTieGoesToTheTermHigherInTheList() {
        // Two different terms can't share a spelling through the store; the matcher still breaks a tie by order
        let terms = [VocabularyTerm(term: "Kubernetes", heardAs: ["kube"]), VocabularyTerm(term: "Kube", heardAs: [])]
        XCTAssertEqual(corrected("kube cluster", terms), "Kubernetes cluster")
    }

    func testSpacesMatchAnyRunOfWhitespace() {
        let terms = [VocabularyTerm(term: "Pluto TV", heardAs: ["pluto tv"])]
        XCTAssertEqual(corrected("the pluto   tv app", terms), "the Pluto TV app")
        XCTAssertEqual(corrected("the pluto\ntv app", terms), "the Pluto TV app")
    }

    func testPunctuationNextToAMatchIsKept() {
        let terms = [VocabularyTerm(term: "Jira")]
        XCTAssertEqual(corrected("(jira), jira. \"jira\"", terms), "(Jira), Jira. \"Jira\"")
    }

    func testOnePassReplacedTextIsNotMatchedAgain() {
        // Scanning the replacement "Jira Cloud" again would turn it into "Atlassian Jira Cloud"
        let terms = [VocabularyTerm(term: "Jira Cloud", heardAs: ["jira"]),
                     VocabularyTerm(term: "Atlassian Jira Cloud", heardAs: ["jira cloud"])]
        XCTAssertEqual(corrected("open jira now", terms), "open Jira Cloud now")
    }

    func testDisabledTermsAreIgnored() {
        let terms = [VocabularyTerm(term: "Jira", enabled: false)]
        XCTAssertEqual(corrected("file a jira", terms), "file a jira")
    }

    func testSpeakerLabelsAreNeverAltered() {
        let terms = [VocabularyTerm(term: "SPEAKER", heardAs: ["speaker"])]
        let text = "[Speaker 1] the speaker said hi [Speaker 2] ok"
        XCTAssertEqual(corrected(text, terms), "[Speaker 1] the SPEAKER said hi [Speaker 2] ok")
    }

    func testEmptyVocabularyPassesTextThrough() {
        XCTAssertEqual(corrected("anything at all", []), "anything at all")
        XCTAssertTrue(VocabularyMatcher(terms: []).isEmpty)
    }

    func testNonASCIIAndPlusSigns() {
        let terms = [VocabularyTerm(term: "Café Müller"), VocabularyTerm(term: "C++", heardAs: ["c plus plus"])]
        XCTAssertEqual(corrected("at café müller we write c plus plus", terms), "at Café Müller we write C++")
    }

    func testFiveHundredTermsOnAOneMinuteTranscriptIsFast() {
        let terms = (0..<500).map { VocabularyTerm(term: "Term\($0)", heardAs: ["term number \($0)"]) }
        let transcript = String(repeating: "we shipped term number 42 and talked about jira and pluto tv today, ", count: 14)
        let matcher = VocabularyMatcher(terms: terms)
        let start = ContinuousClock.now
        let output = matcher.apply(transcript)
        let elapsed = ContinuousClock.now - start
        XCTAssertTrue(output.contains("Term42"))
        // The design's 5 ms is for a release build; Debug test builds are several times slower
        XCTAssertLessThan(elapsed, .milliseconds(50), "Correcting took \(elapsed)")
        print("Vocabulary matcher, 500 terms, \(transcript.count) characters: \(elapsed)")
    }
}
