import XCTest
@testable import Honyaku

final class AppCategoryTests: XCTestCase {
    func testKnownAppsHaveTheirCategory() {
        XCTAssertEqual(AppCategory.category(forBundleID: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.mitchellh.ghostty"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "io.alacritty"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "org.alacritty"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.VSCode"), .codeEditor)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.todesktop.230313mzl4w4u92"), .codeEditor)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.teams2"), .chat)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.Outlook"), .email)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.apple.mail"), .email)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(AppCategory.category(forBundleID: "company.thebrowser.Browser"), .browser)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.VSCodeInsiders"), .codeEditor)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.apple.MobileSMS"), .chat)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.hnc.Discord"), .chat)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.edgemac"), .browser)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.brave.Browser"), .browser)
    }

    func testLookupIgnoresCase() {
        XCTAssertEqual(AppCategory.category(forBundleID: "COM.APPLE.TERMINAL"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.apple.safari"), .browser)
    }

    func testUnknownOrMissingAppsAreOther() {
        XCTAssertEqual(AppCategory.category(forBundleID: "com.example.notes"), .other)
        XCTAssertEqual(AppCategory.category(forBundleID: nil), .other)
        XCTAssertEqual(AppCategory.category(forBundleID: ""), .other)
    }

    func testTargetAppTakesItsCategoryFromTheBundleID() {
        XCTAssertEqual(TargetApp(bundleID: "dev.zed.Zed", pid: 1).category, .codeEditor)
        XCTAssertEqual(TargetApp(bundleID: "com.example.notes", pid: 1, category: .chat).category, .chat)
    }

    func testModeIDs() {
        XCTAssertEqual(DictationMode.dictate.id, "dictate")
    }
}

@MainActor
final class PipelineStagesTests: XCTestCase {
    private var folder: URL!
    private var suiteName: String!
    private var environment: FeatureEnvironment!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "HonyakuFeatureTests-\(UUID().uuidString)")
        suiteName = "HonyakuFeatureTests.\(UUID().uuidString)"
        environment = FeatureEnvironment(directory: folder, defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testStagesApplyInListOrder() {
        let stages: [any TextStage] = [SuffixStage(suffix: "1"), SuffixStage(suffix: "2")]
        var context = DictationContext()
        XCTAssertEqual(PipelineStages.apply(stages, to: "x", context: &context), "x12")
        XCTAssertEqual(PipelineStages.apply([], to: "x", context: &context), "x")
    }

    func testStagesCanChangeTheContext() {
        var context = DictationContext()
        _ = PipelineStages.apply([HistoryOnlyStage(notice: "paste is off")], to: "x", context: &context)
        XCTAssertFalse(context.pasteAllowed)
        XCTAssertEqual(context.pasteOffNotice, "paste is off")
    }

    func testTheAppStartsWithNoStages() {
        let live = PipelineStages.live(environment)
        XCTAssertTrue(live.preparers.isEmpty)
        XCTAssertTrue(live.afterTranscription.isEmpty)
        XCTAssertTrue(live.final.isEmpty)
    }

    func testCombinedKeepsEachFeaturesOrder() {
        let first = PipelineStages(final: [SuffixStage(suffix: "a")])
        let second = PipelineStages(afterTranscription: [SuffixStage(suffix: "b")], final: [SuffixStage(suffix: "c")])
        let combined = PipelineStages.combined([first, second])
        var context = DictationContext()
        XCTAssertEqual(PipelineStages.apply(combined.final, to: "", context: &context), "ac")
        XCTAssertEqual(combined.afterTranscription.count, 1)
    }

    func testEachStoreTypeIsSharedWithinAnEnvironment() {
        let first = environment.store(CountingStore.self)
        let second = environment.store(CountingStore.self)
        XCTAssertTrue(first === second, "A feature's stages and its Settings tab must see one store")
        XCTAssertEqual(first.directory, folder)
        let other = FeatureEnvironment(directory: folder, defaults: environment.defaults)
        XCTAssertFalse(other.store(CountingStore.self) === first)
    }

    func testLiveEnvironmentUsesTheHistoryFolder() {
        XCTAssertEqual(FeatureEnvironment.live().directory, TranscriptStore.defaultFileURL.deletingLastPathComponent())
    }
}

@MainActor
private final class CountingStore: FeatureStore {
    let directory: URL
    init(environment: FeatureEnvironment) { directory = environment.directory }
}

/// Turns off the paste, the way an app set to History only will.
@MainActor
struct HistoryOnlyStage: TextStage {
    var notice: String? = nil
    func apply(_ text: String, context: inout DictationContext) -> String {
        context.pasteAllowed = false
        context.pasteOffNotice = notice
        return text
    }
}
