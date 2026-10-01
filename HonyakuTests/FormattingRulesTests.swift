import XCTest
@testable import Honyaku

final class FormattingRulesTests: XCTestCase {

    // MARK: - Each rule

    func testDropFinalFullStop() {
        let rules = FormattingRules(finalFullStop: .drop)
        XCTAssertEqual(rules.apply(to: "Ship it."), "Ship it")
        XCTAssertEqual(rules.apply(to: "Ship it.  "), "Ship it  ", "only the full stop goes; whitespace is another rule's job")
        XCTAssertEqual(rules.apply(to: "Wait..."), "Wait...")
        XCTAssertEqual(rules.apply(to: "Really?"), "Really?")
        XCTAssertEqual(rules.apply(to: "Go!"), "Go!")
        XCTAssertEqual(rules.apply(to: "She said \"done.\""), "She said \"done.\"", "a full stop before a closing quote stays")
        XCTAssertEqual(FormattingRules(finalFullStop: .keep).apply(to: "Ship it."), "Ship it.")
    }

    func testStraightQuotes() {
        let rules = FormattingRules(quotes: .straight)
        XCTAssertEqual(rules.apply(to: "Run \u{201C}make test\u{201D} and I\u{2019}ll check \u{2018}it\u{2019}"),
                       "Run \"make test\" and I'll check 'it'")
        XCTAssertEqual(rules.apply(to: "\u{201E}low\u{201F} \u{201A}x\u{201B}"), "\"low\" 'x'")
        XCTAssertEqual(FormattingRules().apply(to: "I\u{2019}ll"), "I\u{2019}ll")
    }

    func testJoinLines() {
        let rules = FormattingRules(lineBreaks: .join)
        XCTAssertEqual(rules.apply(to: "one\ntwo\n\nthree\n"), "one two three")
        XCTAssertEqual(rules.apply(to: "one  \n  two"), "one two")
        XCTAssertEqual(rules.apply(to: "\r\nstart\r\nend\r\n"), "start end")
        XCTAssertEqual(rules.apply(to: "no breaks here"), "no breaks here")
        XCTAssertEqual(FormattingRules(lineBreaks: .keep).apply(to: "a\nb\n"), "a\nb\n")
    }

    func testTrailingSpace() {
        let rules = FormattingRules(trailingSpace: true)
        XCTAssertEqual(rules.apply(to: "Hello."), "Hello. ")
        XCTAssertEqual(rules.apply(to: "Hello "), "Hello ", "no second space")
        XCTAssertEqual(rules.apply(to: ""), "")
    }

    func testLowercaseFirstLetter() {
        let rules = FormattingRules(firstLetter: .lowercase)
        XCTAssertEqual(rules.apply(to: "Deploy it"), "deploy it")
        XCTAssertEqual(rules.apply(to: "\u{201C}Quoted\u{201D} start"), "\u{201C}quoted\u{201D} start")
        XCTAssertEqual(rules.apply(to: "already lower"), "already lower")
    }

    func testFirstLetterExceptions() {
        let rules = FormattingRules(firstLetter: .lowercase)
        XCTAssertEqual(rules.apply(to: "I think so"), "I think so")
        XCTAssertEqual(rules.apply(to: "I'm in"), "I'm in")
        XCTAssertEqual(rules.apply(to: "I\u{2019}ll go"), "I\u{2019}ll go")
        XCTAssertEqual(rules.apply(to: "I've done it"), "I've done it")
        XCTAssertEqual(rules.apply(to: "API keys rotate tonight"), "API keys rotate tonight")
        XCTAssertEqual(rules.apply(to: "GitHub is down"), "GitHub is down")
        XCTAssertEqual(rules.apply(to: "It works"), "it works", "\"It\" isn't \"I\"")
        XCTAssertEqual(rules.apply(to: "Jira is slow", protectedTerms: ["Jira"]), "Jira is slow")
        XCTAssertEqual(rules.apply(to: "Jira's queue", protectedTerms: ["Jira"]), "Jira's queue")
        XCTAssertEqual(rules.apply(to: "[Speaker 1] Hello"), "[Speaker 1] Hello", "speaker labels are never altered")
    }

    // MARK: - Together

    func testTerminalDefaults() {
        let rules = FormattingRules.defaults(for: .terminal)
        XCTAssertEqual(rules.apply(to: "Run \u{201C}make test\u{201D} in the api folder."), "Run \"make test\" in the api folder")
        XCTAssertEqual(rules.apply(to: "first line\nsecond line\nthird line.\n"), "first line second line third line")
    }

    func testCodeEditorDefaultsKeepLineBreaks() {
        let rules = FormattingRules.defaults(for: .codeEditor)
        XCTAssertEqual(rules.apply(to: "Rename the function to fetchUser."), "Rename the function to fetchUser")
        XCTAssertEqual(rules.apply(to: "one\ntwo."), "one\ntwo")
    }

    func testOtherCategoriesKeepEverything() {
        for category in [AppCategory.chat, .email, .browser, .other] {
            XCTAssertEqual(FormattingRules.defaults(for: category), .asSpoken, category.rawValue)
            XCTAssertEqual(FormattingRules.defaults(for: category).apply(to: "Sounds good, I\u{2019}ll ship it today."),
                           "Sounds good, I\u{2019}ll ship it today.")
        }
        for category in AppCategory.allCases {
            XCTAssertFalse(FormattingRules.defaults(for: category).trailingSpace)
            XCTAssertTrue(FormattingRules.defaults(for: category).paste)
        }
    }

    func testOrderJoinsBeforeDroppingTheFullStop() {
        // The full stop is last only once the trailing line break is gone
        let rules = FormattingRules(finalFullStop: .drop, lineBreaks: .join, trailingSpace: true)
        XCTAssertEqual(rules.apply(to: "Done.\n"), "Done ")
    }

    /// The words never change: same words, same order, ignoring case and punctuation.
    func testRulesNeverChangeTheWords() {
        let samples = [
            "Run \u{201C}make test\u{201D} in the api folder.",
            "I\u{2019}ll ship it today.\nThen we\u{2019}ll see.\n",
            "API keys rotate tonight.",
            "[Speaker 1] Hello there.\n[Speaker 2] Hi.",
            "Wait... really?",
            "  Leading space and \u{2018}quotes\u{2019}. ",
            ".",
            "",
        ]
        for fullStop in FormattingRules.FullStop.allCases {
            for firstLetter in FormattingRules.FirstLetter.allCases {
                for quotes in FormattingRules.Quotes.allCases {
                    for lineBreaks in FormattingRules.LineBreaks.allCases {
                        for trailingSpace in [false, true] {
                            let rules = FormattingRules(finalFullStop: fullStop, firstLetter: firstLetter, quotes: quotes,
                                                        lineBreaks: lineBreaks, trailingSpace: trailingSpace)
                            for sample in samples {
                                XCTAssertEqual(Self.words(rules.apply(to: sample)), Self.words(sample),
                                               "\(rules) changed the words of \(sample.debugDescription)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Letters and digits, with apostrophes inside a word ("I'll"); quote marks around a word aren't part of it.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "[\u{2018}\u{2019}]", with: "'", options: .regularExpression)
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Saved files

    func testMissingFieldsDecodeAsSpoken() throws {
        let rules = try JSONDecoder().decode(FormattingRules.self, from: Data(#"{"finalFullStop":"drop"}"#.utf8))
        XCTAssertEqual(rules, FormattingRules(finalFullStop: .drop))
    }
}

final class AppProfilesTests: XCTestCase {
    func testOverrideBeatsCategoryWhichBeatsEverythingElse() {
        var profiles = AppProfiles()
        profiles.addApp(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty")
        var ghostty = profiles.override(forBundleID: "com.mitchellh.ghostty")!.rules
        XCTAssertEqual(ghostty, .defaults(for: .terminal), "a new app starts from its category's rules")
        ghostty.finalFullStop = .keep
        profiles.setRules(ghostty, forApp: "com.mitchellh.ghostty")

        XCTAssertEqual(profiles.rules(forBundleID: "com.mitchellh.ghostty", category: .terminal).finalFullStop, .keep)
        XCTAssertEqual(profiles.rules(forBundleID: "com.apple.Terminal", category: .terminal).finalFullStop, .drop)
        XCTAssertEqual(profiles.rules(forBundleID: "com.example.unknown", category: .other), .asSpoken)
        XCTAssertEqual(profiles.rules(forBundleID: nil, category: .terminal), .asSpoken,
                       "an app with no bundle ID counts as Everything else")
    }

    func testOverrideMatchesBundleIDIgnoringCase() {
        var profiles = AppProfiles()
        profiles.addApp(bundleID: "com.Example.App", displayName: "Example")
        XCTAssertNotNil(profiles.override(forBundleID: "com.example.app"))
        profiles.addApp(bundleID: "com.example.app", displayName: "Again")
        XCTAssertEqual(profiles.apps.count, 1, "an app already listed isn't added twice")
        profiles.removeApp(bundleID: "COM.EXAMPLE.APP")
        XCTAssertTrue(profiles.apps.isEmpty)
    }

    func testOnlyChangedCategoriesAreStored() {
        var profiles = AppProfiles()
        var chat = profiles.rules(for: .chat)
        chat.finalFullStop = .drop
        profiles.setRules(chat, for: .chat)
        XCTAssertEqual(profiles.categories.keys.sorted(), ["chat"])
        XCTAssertTrue(profiles.isChanged(.chat))

        profiles.setRules(.defaults(for: .chat), for: .chat)
        XCTAssertTrue(profiles.categories.isEmpty, "resetting a category removes its stored copy")
        XCTAssertEqual(profiles.rules(for: .chat).finalFullStop, .keep)
    }

    func testCategoryLookupByBundleID() {
        XCTAssertEqual(AppCategory.category(forBundleID: "com.googlecode.iterm2"), .terminal)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.microsoft.VSCode"), .codeEditor)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(AppCategory.category(forBundleID: "com.example.notes"), .other)
        XCTAssertEqual(AppCategory.terminal.displayName, "Terminals")
        XCTAssertEqual(AppCategory.other.displayName, "Everything else")
    }
}
