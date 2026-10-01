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
    func testStagesApplyInListOrder() {
        let stages: [any TextStage] = [SuffixStage(suffix: "1"), SuffixStage(suffix: "2")]
        XCTAssertEqual(PipelineStages.apply(stages, to: "x", context: DictationContext()), "x12")
        XCTAssertEqual(PipelineStages.apply([], to: "x", context: DictationContext()), "x")
    }

    func testTheAppStartsWithNoStages() {
        let live = PipelineStages.live
        XCTAssertTrue(live.preparers.isEmpty)
        XCTAssertTrue(live.afterTranscription.isEmpty)
        XCTAssertTrue(live.final.isEmpty)
    }
}
