import XCTest
@testable import Honyaku

// Verifies that speaker labels from diarization are preserved in cleanup input

final class PipelineOrderingTests: XCTestCase {

    func testSpeakerLabelsArePresentInMergedText() {
        let timedSegments = [
            TimedSegment(startSeconds: 0, endSeconds: 2, text: "Hello how are you"),
            TimedSegment(startSeconds: 2, endSeconds: 4, text: "doing"),
        ]
        let diarized = [
            DiarizedSegment(startSeconds: 0, endSeconds: 2, speakerID: "Speaker 1", text: ""),
            DiarizedSegment(startSeconds: 2, endSeconds: 4, speakerID: "Speaker 2", text: ""),
        ]
        let merged = DiarizationService.mergeWithTranscript(
            rawText: "Hello how are you doing",
            timedSegments: timedSegments,
            diarizedSegments: diarized
        )
        XCTAssertTrue(merged.contains("[Speaker 1]"), "Merged text must contain Speaker 1 label")
        XCTAssertTrue(merged.contains("[Speaker 2]"), "Merged text must contain Speaker 2 label")
        XCTAssertTrue(merged.contains("Hello how are you"), "Merged text must contain transcribed words")
    }

    func testEmptyDiarizedSegmentsReturnsRawText() {
        let rawText = "Hello world"
        let merged = DiarizationService.mergeWithTranscript(
            rawText: rawText,
            timedSegments: [TimedSegment(startSeconds: 0, endSeconds: 2, text: rawText)],
            diarizedSegments: []
        )
        XCTAssertEqual(merged, rawText, "Empty diarized segments should return raw text unchanged")
        XCTAssertFalse(merged.contains("[Speaker"), "No speaker labels when diarized segments is empty")
    }

    func testConsecutiveSameSpeakerMerged() {
        let timedSegments = [
            TimedSegment(startSeconds: 0, endSeconds: 1, text: "Hello"),
            TimedSegment(startSeconds: 1, endSeconds: 2, text: "world"),
            TimedSegment(startSeconds: 2, endSeconds: 3, text: "Hi"),
        ]
        let diarized = [
            DiarizedSegment(startSeconds: 0, endSeconds: 2, speakerID: "Speaker 1", text: ""),
            DiarizedSegment(startSeconds: 2, endSeconds: 3, speakerID: "Speaker 2", text: ""),
        ]
        let merged = DiarizationService.mergeWithTranscript(
            rawText: "Hello world Hi",
            timedSegments: timedSegments,
            diarizedSegments: diarized
        )
        XCTAssertTrue(merged.contains("Hello") && merged.contains("world"))
        XCTAssertEqual(merged.components(separatedBy: "[Speaker 1]").count - 1, 1,
                       "Consecutive same-speaker segments should produce one label block")
    }
}
