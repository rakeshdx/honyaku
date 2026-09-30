import XCTest
@testable import Honyaku

final class ParakeetEngineTests: XCTestCase {

    func testShortClipIsPaddedToMinimum() {
        let padded = ParakeetEngine.padded(Array(repeating: 0.5, count: 1_000))
        XCTAssertEqual(padded.count, ParakeetEngine.minimumSamples)
        XCTAssertEqual(padded.first, 0.5)
        XCTAssertEqual(padded.last, 0, "Padding is trailing silence")
    }

    func testLongClipIsUntouched() {
        XCTAssertEqual(ParakeetEngine.padded(Array(repeating: 0.1, count: 16_000)).count, 16_000)
    }

    func testSilenceRule() {
        XCTAssertTrue(ParakeetEngine.isSilence(text: "", confidence: 0.9, wordCount: 3))
        XCTAssertTrue(ParakeetEngine.isSilence(text: "Uh", confidence: 0.1, wordCount: 0))
        XCTAssertFalse(ParakeetEngine.isSilence(text: "Hello.", confidence: 0.1, wordCount: 1))
        XCTAssertFalse(ParakeetEngine.isSilence(text: "Hello.", confidence: 0.8, wordCount: 1))
    }

    func testSegmentsBreakOnPausesAndSentenceEnds() {
        let words = [
            SpokenWord(text: "Send", start: 0.0, end: 0.3),
            SpokenWord(text: "it.", start: 0.35, end: 0.6),
            SpokenWord(text: "Then", start: 0.7, end: 0.9),
            SpokenWord(text: "call", start: 1.0, end: 1.2),
            SpokenWord(text: "her", start: 2.0, end: 2.2),  // 0.8 s pause before
        ]
        let segments = ParakeetEngine.segments(from: words)
        XCTAssertEqual(segments.map(\.text), ["Send it.", "Then call", "her"])
        XCTAssertEqual(segments[0].startSeconds, 0.0)
        XCTAssertEqual(segments[0].endSeconds, 0.6)
        XCTAssertEqual(segments[2].startSeconds, 2.0)
    }

    func testNoWordsGivesNoSegments() {
        XCTAssertTrue(ParakeetEngine.segments(from: []).isEmpty)
    }
}
