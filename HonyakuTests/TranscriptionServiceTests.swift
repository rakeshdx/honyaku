import XCTest
@testable import Honyaku
import WhisperKit

final class TranscriptionDecodeOptionsTests: XCTestCase {

    func testSubSecondClipGetsTrimJustUnderItsLength() {
        // Default 1 s trim would skip this clip without decoding it
        XCTAssertEqual(TranscriptionService.decodeOptions(forDurationSeconds: 0.5).windowClipTime, 0.4, accuracy: 0.001)
    }

    func testVeryShortClipNeverGetsNegativeTrim() {
        XCTAssertEqual(TranscriptionService.decodeOptions(forDurationSeconds: 0.05).windowClipTime, 0, accuracy: 0.001)
    }

    func testClipsFromOnePointOneSecondsKeepTheDefaultTrim() {
        let defaultTrim = DecodingOptions().windowClipTime
        for duration in [1.1, 29.9, 45] {
            XCTAssertEqual(TranscriptionService.decodeOptions(forDurationSeconds: duration).windowClipTime, defaultTrim)
        }
        XCTAssertEqual(TranscriptionService.decodeOptions(forDurationSeconds: nil).windowClipTime, defaultTrim)
    }

    func testChosenLanguageIsPassedAndNotDetected() {
        let options = TranscriptionService.decodeOptions(forDurationSeconds: 2, language: "it")
        XCTAssertEqual(options.language, "it")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertEqual(options.task, .transcribe)
    }

    func testLanguageListHasOneEntryPerCodeSortedByName() {
        let languages = TranscriptionService.dictationLanguages
        XCTAssertEqual(Set(languages.map(\.code)).count, languages.count)
        XCTAssertEqual(languages.map(\.name), languages.map(\.name).sorted())
        XCTAssertTrue(languages.contains { $0.name == "Italian" && $0.code == "it" })
        XCTAssertTrue(languages.contains { $0.name == "Japanese" && $0.code == "ja" })
    }

    func testOnlyMultilingualWhisperSupportsDictationLanguage() throws {
        XCTAssertTrue(try XCTUnwrap(ModelRegistry.model(id: "whisper-large-v3-turbo")).supportsDictationLanguage)
        XCTAssertFalse(try XCTUnwrap(ModelRegistry.model(id: "parakeet-tdt-v2")).supportsDictationLanguage)
    }

    func testLanguageIsDetectedWhenNoneIsChosen() {
        // WhisperKit's default forces <|en|>, which makes the multilingual model translate into English
        XCTAssertFalse(DecodingOptions().detectLanguage, "Precondition: WhisperKit's default doesn't detect")
        for duration in [0.5, 3, nil] as [Double?] {
            let options = TranscriptionService.decodeOptions(forDurationSeconds: duration)
            XCTAssertTrue(options.detectLanguage)
            XCTAssertNil(options.language)
            XCTAssertEqual(options.task, .transcribe)
        }
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

    func testAsteriskSoundDescriptionIsRemoved() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("*thud*"), "")
        XCTAssertEqual(TranscriptionService.assembleText(windowTexts: [" *laughs* Send it now."],
                                                         segmentTexts: [" *laughs*", " Send it now."]),
                       "Send it now.")
    }

    func testAsterisksInSpeechAreKept() {
        XCTAssertEqual(TranscriptionService.stripNonSpeech("I *really* mean it"), "I *really* mean it")
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

    func testTokenizerNameDropsSizeSuffixAndDateStamp() {
        XCTAssertEqual(TranscriptionService.tokenizerName(forVariant: "openai_whisper-tiny.en"), "openai/whisper-tiny.en")
        XCTAssertEqual(TranscriptionService.tokenizerName(forVariant: "openai_whisper-large-v3-v20240930_626MB"),
                       "openai/whisper-large-v3")
        XCTAssertEqual(TranscriptionService.tokenizerName(forVariant: "openai_whisper-large-v3_turbo_954MB"),
                       "openai/whisper-large-v3")
        XCTAssertNil(TranscriptionService.tokenizerName(forVariant: "distil-whisper_distil-large-v3"))
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
