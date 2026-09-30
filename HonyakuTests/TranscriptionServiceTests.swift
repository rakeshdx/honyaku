import XCTest
@testable import Honyaku

final class TranscriptionDecodeOptionsTests: XCTestCase {

    func testSubSecondClipGetsTrimJustUnderItsLength() throws {
        // Default 1 s trim would skip this clip without decoding it
        let trim = try XCTUnwrap(TranscriptionService.decodeOptions(forDurationSeconds: 0.5)?.windowClipTime)
        XCTAssertEqual(trim, 0.4, accuracy: 0.001)
    }

    func testVeryShortClipNeverGetsNegativeTrim() throws {
        let trim = try XCTUnwrap(TranscriptionService.decodeOptions(forDurationSeconds: 0.05)?.windowClipTime)
        XCTAssertEqual(trim, 0, accuracy: 0.001)
    }

    func testClipsFromOnePointOneSecondsKeepWhisperKitDefaults() {
        XCTAssertNil(TranscriptionService.decodeOptions(forDurationSeconds: 1.1))
        XCTAssertNil(TranscriptionService.decodeOptions(forDurationSeconds: 29.9))
        XCTAssertNil(TranscriptionService.decodeOptions(forDurationSeconds: 45))
    }

    func testUnknownDurationKeepsWhisperKitDefaults() {
        XCTAssertNil(TranscriptionService.decodeOptions(forDurationSeconds: nil))
    }
}

final class NonSpeechAnnotationTests: XCTestCase {

    func testBlankAudioBecomesEmpty() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("[BLANK_AUDIO]"), "")
    }

    func testAnnotationAroundSpeechIsRemoved() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("[MUSIC] send the report"), "send the report")
    }

    func testBareParentheticalBecomesEmpty() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("(silence)"), "")
    }

    func testAnnotationOnlySegmentDropsOutOfAssembledText() {
        XCTAssertEqual(TranscriptionService.assembleText(windowTexts: [" (clears throat) Send the report."],
                                                         segmentTexts: [" (clears throat)", " Send the report."]),
                       "Send the report.")
        XCTAssertEqual(TranscriptionService.assembleText(windowTexts: ["<|0.00|> Hello<|1.00|> [BLANK_AUDIO]"],
                                                         segmentTexts: ["<|0.00|> Hello<|1.00|>", " [BLANK_AUDIO]"]),
                       "Hello")
    }

    func testScriptsWithoutSpacesKeepTheirSpacing() {
        XCTAssertEqual(TranscriptionService.assembleText(windowTexts: ["昨日は雨でした。今日は晴れです。"],
                                                         segmentTexts: ["昨日は雨でした。", "今日は晴れです。"]),
                       "昨日は雨でした。今日は晴れです。")
    }

    func testParenthesesInSpeechAreKept() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("call me (maybe) later"), "call me (maybe) later")
    }
}

final class LocalSpeechModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "honyaku-model-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFolderFollowsHubLayout() {
        let folder = TranscriptionService.localModelFolder(
            repo: "argmaxinc/whisperkit-coreml", variant: "openai_whisper-tiny.en", documents: root)
        XCTAssertEqual(folder.path,
                       root.appending(path: "huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny.en").path)
    }

    func testCompleteModelIsDownloaded() throws {
        try makeModel(["AudioEncoder", "TextDecoder", "MelSpectrogram"])
        XCTAssertTrue(TranscriptionService.isModelDownloaded(at: root))
    }

    func testMissingModelIsNotDownloaded() throws {
        try makeModel(["AudioEncoder", "TextDecoder"])
        XCTAssertFalse(TranscriptionService.isModelDownloaded(at: root))
    }

    func testTokenizerPathFollowsVariantName() throws {
        XCTAssertFalse(TranscriptionService.isTokenizerDownloaded(variant: "openai_whisper-tiny.en", documents: root))
        let dir = root.appending(path: "huggingface/models/openai/whisper-tiny.en")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appending(path: "tokenizer.json"))
        XCTAssertTrue(TranscriptionService.isTokenizerDownloaded(variant: "openai_whisper-tiny.en", documents: root))
        XCTAssertFalse(TranscriptionService.isTokenizerDownloaded(variant: "distil-whisper_large", documents: root))
    }

    func testInterruptedModelIsNotDownloaded() throws {
        try makeModel(["AudioEncoder", "TextDecoder"])
        // Folder exists but compiled data never landed
        try FileManager.default.createDirectory(at: root.appending(path: "MelSpectrogram.mlmodelc"),
                                                withIntermediateDirectories: true)
        XCTAssertFalse(TranscriptionService.isModelDownloaded(at: root))
    }

    private func makeModel(_ names: [String]) throws {
        for name in names {
            let dir = root.appending(path: "\(name).mlmodelc")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appending(path: "coremldata.bin"))
        }
    }
}
