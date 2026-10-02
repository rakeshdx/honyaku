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
    }

    func testNonASCIIAndPlusSigns() {
        let terms = [VocabularyTerm(term: "Café Müller"), VocabularyTerm(term: "C++", heardAs: ["c plus plus"])]
        XCTAssertEqual(corrected("at café müller we write c plus plus", terms), "at Café Müller we write C++")
    }

    func testFiveHundredTermsOnAOneMinuteTranscript() {
        let terms = (0..<500).map { VocabularyTerm(term: "Term\($0)", heardAs: ["term number \($0)"]) }
        let transcript = String(repeating: "we shipped term number 42 and talked about jira and pluto tv today, ", count: 14)
        let matcher = VocabularyMatcher(terms: terms)
        XCTAssertTrue(matcher.apply(transcript).contains("Term42"))
        // Timed with measure {}: a wall-clock assertion fails on a busy machine (the design's 5 ms is a
        // release-build figure)
        measure { _ = matcher.apply(transcript) }
    }

    // MARK: - Review fixes

    func testContractionsAreLeftAlone() {
        let terms = [VocabularyTerm(term: "Don"), VocabularyTerm(term: "Won"), VocabularyTerm(term: "Jira")]
        XCTAssertEqual(corrected("I don't know, ask don", terms), "I don't know, ask Don")
        XCTAssertEqual(corrected("it won\u{2019}t matter, won said", terms), "it won\u{2019}t matter, Won said")
        XCTAssertEqual(corrected("jira's board and jira\u{2019}s queue", terms), "Jira's board and Jira\u{2019}s queue")
        XCTAssertEqual(corrected("don's car", terms), "Don's car", "A possessive ending the word")
        XCTAssertEqual(corrected("don'sy", terms), "don'sy")
    }

    func testLinksEmailsPathsAndIdentifiersAreLeftAlone() {
        let terms = [VocabularyTerm(term: "GitHub"), VocabularyTerm(term: "Jira")]
        XCTAssertEqual(corrected("see github.com/acme and jira_client, then email a@jira.com about github", terms),
                       "see github.com/acme and jira_client, then email a@jira.com about GitHub")
        XCTAssertEqual(corrected("open https://jira.example/browse/X-1 in jira.", terms),
                       "open https://jira.example/browse/X-1 in Jira.")
        XCTAssertEqual(corrected("edit ~/src/jira/main.swift", terms), "edit ~/src/jira/main.swift")
    }

    func testAWholeLinkLikeTokenMayStillBeATerm() {
        let terms = [VocabularyTerm(term: "Node.js")]
        XCTAssertEqual(corrected("we use node.js, mostly", terms), "we use Node.js, mostly")
    }

    func testUnspacedScriptsAndScriptChangesAreBoundaries() {
        let terms = [VocabularyTerm(term: "GitHub"), VocabularyTerm(term: "東京", heardAs: ["とうきょう"])]
        XCTAssertEqual(corrected("githubを使う", terms), "GitHubを使う")
        XCTAssertEqual(corrected("私はとうきょうに行く", terms), "私は東京に行く")
        XCTAssertEqual(corrected("githubтест", terms), "GitHubтест", "Latin then Cyrillic")
        XCTAssertEqual(corrected("githubs", terms), "githubs", "Still part of a longer Latin word")
    }
}
