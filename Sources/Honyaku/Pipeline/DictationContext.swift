import AppKit

/// How a dictation's words are turned into text. Plain dictation keeps every word.
enum DictationMode: Equatable, Sendable {
    case dictate

    /// Stored in history (`TranscriptEntry.mode`).
    var id: String {
        switch self {
        case .dictate: return "dictate"
        }
    }
}

/// Where text is headed, by kind of app. Rewrite picks templates by it; per-app rules format by it.
enum AppCategory: String, Codable, CaseIterable, Sendable {
    case terminal, codeEditor, chat, email, browser, other

    /// Known apps, keyed by lowercased bundle ID. Unknown apps are `.other`.
    static let knownBundleIDs: [String: AppCategory] = {
        let table: [AppCategory: [String]] = [
            .terminal: [
                "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "com.cmuxterm.app",
                "co.zeit.hyper", "org.tabby",
            ],
            .codeEditor: [
                "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
                "com.apple.dt.Xcode", "dev.zed.Zed",
            ],
            .chat: [
                "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.MobileSMS",
                "com.hnc.Discord",
            ],
            .email: ["com.microsoft.Outlook", "com.apple.mail"],
            .browser: [
                "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser",
                "com.microsoft.edgemac", "com.brave.Browser",
            ],
        ]
        var byID: [String: AppCategory] = [:]
        for (category, ids) in table {
            for id in ids { byID[id.lowercased()] = category }
        }
        return byID
    }()

    static func category(forBundleID bundleID: String?) -> AppCategory {
        guard let bundleID else { return .other }
        return knownBundleIDs[bundleID.lowercased()] ?? .other
    }
}

/// An app that text may be pasted into.
struct TargetApp: Equatable, Sendable {
    let bundleID: String?
    let pid: pid_t
    let name: String?
    let category: AppCategory

    init(bundleID: String?, pid: pid_t, name: String? = nil, category: AppCategory? = nil) {
        self.bundleID = bundleID
        self.pid = pid
        self.name = name
        self.category = category ?? AppCategory.category(forBundleID: bundleID)
    }
}

/// Hints handed to the speech model with the audio.
struct SpeechHints: Equatable, Sendable {
    /// The language to transcribe in (a Whisper code such as "it"); nil detects it. Only Whisper uses it.
    var language: String?
    /// Terms the speech model should expect, most important last (Whisper keeps the end of a long prompt).
    var glossary: [String] = []

    init(language: String? = nil, glossary: [String] = []) {
        self.language = language
        self.glossary = glossary
    }

    static let none = SpeechHints()
}

/// What the pipeline knows about one dictation. Preparers fill in hints and rules; text stages may turn
/// off the paste or add notices.
struct DictationContext: Sendable {
    var mode: DictationMode
    /// The app in front when recording started: anything the model does is decided for this app.
    var appAtStart: TargetApp?
    /// The app in front when the text is ready: formatting and the paste are for this app.
    var appAtPaste: TargetApp?
    /// Honyaku itself is in front at paste time: ⌘V would land in its own window.
    var honyakuIsFrontmost = false
    /// A password field has focus at paste time: the text is neither pasted nor saved.
    var isSecureField = false
    /// Whether the text may be pasted. A final stage turns it off for an app set to History only.
    var pasteAllowed = true
    /// Shown when `pasteAllowed` is off, e.g. "Saved to History — paste is off for Slack".
    var pasteOffNotice: String?
    /// Messages for the user, shown once after the text is routed (e.g. "Couldn't rewrite: …").
    var notices: [String] = []
    /// The first-run test running when the recording started, if any.
    var firstRunTestSession: Int?
    /// The speech model for this dictation, set before the preparers run.
    var speechModelID: String?
    /// Language the speech model detected or was told to use.
    var language: String?
    /// um/uh are fillers in English only: "um" is a word in German and Portuguese.
    var englishFillers = true
    var speechHints = SpeechHints.none
    /// Extra lines for the cleanup prompt.
    var cleanupRules: [String] = []
    /// Every enabled vocabulary term, as written, for any engine and language. Formatting leaves these
    /// alone and cleanup must keep them (`speechHints.glossary` is only the Whisper hint).
    var vocabularyTerms: [String] = []

    init(mode: DictationMode = .dictate, appAtStart: TargetApp? = nil, firstRunTestSession: Int? = nil) {
        self.mode = mode
        self.appAtStart = appAtStart
        self.firstRunTestSession = firstRunTestSession
    }
}

// MARK: - Extension points

/// Runs before transcription and may add speech hints or cleanup rules.
@MainActor
protocol DictationContextPreparer {
    func prepare(_ context: inout DictationContext)
}

/// A text transform at a fixed point in the pipeline (see `PipelineStages`). It may also turn off the
/// paste or add a notice through the context. Synchronous: load any data ahead of time, never in `apply`.
@MainActor
protocol TextStage {
    func apply(_ text: String, context: inout DictationContext) -> String
}

// MARK: - Target app

/// What's in front at paste time.
struct PasteTarget: Equatable, Sendable {
    var app: TargetApp?
    var honyakuIsFrontmost: Bool
    var isSecureField = false
}

@MainActor
protocol TargetAppResolving {
    /// The app in front now, if any.
    func frontmostApp() -> TargetApp?
    /// The app in front now and whether text may safely be pasted into it.
    func pasteTarget() -> PasteTarget
}

@MainActor
struct TargetAppResolver: TargetAppResolving {
    func frontmostApp() -> TargetApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return TargetApp(bundleID: app.bundleIdentifier, pid: app.processIdentifier, name: app.localizedName)
    }

    func pasteTarget() -> PasteTarget {
        PasteTarget(app: frontmostApp(), honyakuIsFrontmost: NSApplication.shared.isActive)
    }
}
