import Foundation

/// The seven built-in rewrite formats. Raw values are stored in settings and history.
enum RewriteTemplateID: String, CaseIterable, Codable, Sendable {
    case jiraTicket, chatMessage, email, commitMessage, prDescription, agentPrompt, standupUpdate

    /// As a title: "Jira ticket".
    var name: String {
        switch self {
        case .jiraTicket: return "Jira ticket"
        case .chatMessage: return "Chat message"
        case .email: return "Email"
        case .commitMessage: return "Commit message"
        case .prDescription: return "PR description"
        case .agentPrompt: return "Coding-agent prompt"
        case .standupUpdate: return "Standup update"
        }
    }

    /// Inside a sentence: "Rewriting as chat message".
    var inlineName: String {
        switch self {
        case .jiraTicket: return "Jira ticket"
        case .prDescription: return "PR description"
        default: return name.prefix(1).lowercased() + name.dropFirst()
        }
    }

    /// One line for the Rewrite tab.
    var summary: String {
        switch self {
        case .jiraTicket: return "Summary, description, steps if you gave any, and acceptance criteria."
        case .chatMessage: return "One to three short, friendly sentences."
        case .email: return "A greeting, short paragraphs and a sign-off."
        case .commitMessage: return "A short subject line in the imperative, with a body only if needed."
        case .prDescription: return "Summary, changes and how it was tested."
        case .agentPrompt: return "One paragraph of instructions that keeps every name you said."
        case .standupUpdate: return "Yesterday, today and blockers."
        }
    }

    /// Output cap before it's reduced for short dictations.
    var tokenCap: Int {
        switch self {
        case .commitMessage: return 200
        case .chatMessage, .standupUpdate: return 300
        case .agentPrompt: return 400
        case .jiraTicket, .prDescription, .email: return 700
        }
    }

    /// The prompt the user can edit in Settings > Rewrite.
    var defaultPrompt: String {
        switch self {
        case .jiraTicket:
            return """
            Rewrite the dictation as a Jira ticket in exactly this layout, starting each section with its label:

            Summary: one line

            Description: what the problem or request is, in a few sentences

            Acceptance criteria:
            - what must be true when this is done, one bullet each

            Only if the speaker described steps to reproduce, add "Steps to reproduce:" with numbered steps after the description. Every acceptance criterion must come from what the speaker said; add none of your own.
            """
        case .chatMessage:
            return """
            Rewrite the dictation as a chat message to a colleague: one to three short sentences, plain and friendly. \
            No greeting or sign-off unless the speaker said one.
            """
        case .email:
            return """
            Rewrite the dictation as an email body: a short greeting, then short paragraphs, then a sign-off such as \
            "Thanks," with no name after it. No subject line.
            """
        case .commitMessage:
            return """
            Rewrite the dictation as a git commit message: a subject line in the imperative mood, under 72 characters, \
            with no full stop. If the speaker described more than the subject covers, add a blank line and a short body.
            """
        case .prDescription:
            return """
            Rewrite the dictation as a pull request description in exactly this layout, starting each section with its label:

            Summary: one or two sentences

            Changes:
            - one bullet per change the speaker described

            Testing: how the speaker said it was tested, or TBD
            """
        case .agentPrompt:
            return """
            Rewrite the dictation as one clear paragraph of instructions for a coding agent, written in the second \
            person ("Add…", "Make sure you…"). Keep every file, function, command and error message the speaker named, \
            exactly as spoken.
            """
        case .standupUpdate:
            return """
            Rewrite the dictation as a standup update in exactly this layout, starting each section with its label:

            Yesterday:
            - one bullet per thing done

            Today:
            - one bullet per thing planned

            Blockers:
            - one bullet per blocker, or "None" if the speaker mentioned none
            """
        }
    }

    /// Automatic: the template for the kind of app the recording started in.
    static func automatic(for category: AppCategory) -> RewriteTemplateID {
        switch category {
        case .chat: return .chatMessage
        case .terminal, .codeEditor: return .agentPrompt
        case .email: return .email
        case .browser, .other: return .jiraTicket
        }
    }
}

/// A rewrite to run: the template and the prompt for it (the user's edit or the default).
struct RewritePlan: Equatable, Sendable {
    let template: RewriteTemplateID
    let templatePrompt: String

    init(template: RewriteTemplateID, templatePrompt: String? = nil) {
        self.template = template
        self.templatePrompt = templatePrompt ?? template.defaultPrompt
    }

    /// The model call for `transcript`. `extraRules` are the dictation's cleanup rules (vocabulary terms).
    func request(for transcript: String, extraRules: [String], englishFillers: Bool) -> CleanupRequest {
        CleanupRequest(systemPrompt: RewritePrompt.sharedRules + "\n" + templatePrompt,
                       extraRules: extraRules,
                       faithfulness: .none,
                       maxTokens: RewritePrompt.tokenCap(for: template, transcript: transcript),
                       englishFillers: englishFillers,
                       transcriptLabel: RewritePrompt.transcriptLabel,
                       speakerLabelRule: RewritePrompt.speakerLabelRule)
    }
}

/// The fixed parts of every rewrite prompt, and cleaning up what the model returns.
enum RewritePrompt {
    /// Prepended to every template and not editable, so an edited template can't drop the no-invention rule.
    static let sharedRules = """
    You turn dictated speech into a written format. Follow these rules:
    - Use only what the speaker said. Never invent names, numbers, dates, links, ticket IDs or facts.
    - If the format needs something the speaker didn't say, write TBD.
    - Keep every name, product, file, function and command exactly as spoken.
    - Write plain text. Use labels followed by a colon, "- " for bullets, and blank lines between sections. No Markdown headings, bold or code fences.
    - Output only the rewritten text, with no introduction or comment.
    """

    /// Only for labelled transcripts: an unconditional label rule made Qwen3-4B answer "[Speaker 1]".
    static let speakerLabelRule = "The dictation has speaker labels. Use them to know who said what, but don't include the labels in the output."

    static let transcriptLabel = "Dictation to rewrite:"

    /// `min(cap, 150 + 3 × input tokens)`.
    static func tokenCap(for template: RewriteTemplateID, transcript: String) -> Int {
        min(template.tokenCap, 150 + 3 * estimatedTokens(transcript))
    }

    /// Words × 4/3 for text written with spaces, plus one per character of a script written without them
    /// (Han, kana, Thai…), which would otherwise count a minute of Japanese as a few words.
    static func estimatedTokens(_ text: String) -> Int {
        var unspaced = 0
        var spaced = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isWrittenWithoutSpaces(scalar) {
                unspaced += 1
                spaced.append(" ")
            } else {
                spaced.append(scalar)
            }
        }
        let words = String(spaced).split { $0.isWhitespace }.count
        return (words * 4 + 2) / 3 + unspaced
    }

    private static func isWrittenWithoutSpaces(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x30FF,    // CJK punctuation, hiragana, katakana
             0x31F0...0x31FF,    // katakana extensions
             0x3400...0x4DBF,    // CJK extension A
             0x4E00...0x9FFF,    // CJK unified ideographs
             0xF900...0xFAFF,    // CJK compatibility ideographs
             0xFF66...0xFF9F,    // half-width katakana
             0x20000...0x2FFFF,  // CJK extensions B and later
             0x0E00...0x0EFF,    // Thai, Lao
             0x1000...0x109F,    // Myanmar
             0x1780...0x17FF:    // Khmer
            return true
        default:
            return false
        }
    }

    /// Removes what the model echoes back before the rewrite: a heading line that names a template
    /// ("Rewritten chat message:", "Here's your Jira ticket:"), a line copied from `plan`'s prompt, the dictation
    /// label, or a lone "Rewrite:" label. Any other first line is content, even one that starts like an
    /// instruction ("Rewrite the dictation pipeline as stages"). Also drops spaces at the ends of lines and outer
    /// whitespace. Delimiters and reasoning are already stripped by `CleanupService`.
    static func stripEchoes(_ output: String, plan: RewritePlan) -> String {
        let promptLines = (sharedRules + "\n" + plan.templatePrompt).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        var lines = output.replacingOccurrences(of: #"(?m)[ \t]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        while let first = lines.first, isEcho(first, promptLines: promptLines) {
            lines.removeFirst()
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        }
        var result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for label in [transcriptLabel, "Rewritten:"] where result.lowercased().hasPrefix(label.lowercased()) {
            result = String(result.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func isEcho(_ line: String, promptLines: [String]) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
        if [transcriptLabel.lowercased(), "rewrite:", "rewritten:"].contains(lower) { return true }
        // Copied from the prompt, whole or cut off where the model added a colon
        let copied = lower.hasSuffix(":") ? String(lower.dropLast()) : lower
        if copied.count >= 20, promptLines.contains(where: { $0 == lower || $0.hasPrefix(copied) }) { return true }
        return lower.range(of: templateHeading, options: .regularExpression) != nil
    }

    /// "Jira ticket:", "Rewritten chat message:", "Here's your Jira ticket:", "The PR description:".
    private static let templateHeading: String = {
        let names = RewriteTemplateID.allCases.flatMap { [$0.name.lowercased(), $0.inlineName.lowercased()] }
            .map(NSRegularExpression.escapedPattern(for:))
        return #"^(?:(?:here is|here's|here are|rewritten|rewritten as|your|the|an?)\s+)*(?:"#
            + names.joined(separator: "|") + #")(?:\s+(?:rewrite|rewritten|draft|version))?:$"#
    }()

    /// A rewrite that stopped at its token cap, back to its last complete line, or for one line its last complete
    /// sentence. Empty when nothing complete is left.
    static func trimmedToLastComplete(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, ".!?…。！？".contains(last) { return trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        if lines.count > 1 {
            lines.removeLast()
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let sentences = trimmed.range(of: #"^.*[.!?。！？](?=\s|$)"#, options: .regularExpression) else { return "" }
        return String(trimmed[sentences])
    }

    /// For terminals: one line, so pasting can't run anything. Every kind of line break (CRLF, U+2028, U+0085,
    /// vertical tab, form feed…) and the whitespace around it becomes one space, control characters other than
    /// tab go, and so do leading and trailing whitespace. Nothing else changes.
    static func joinedOnOneLine(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]*(?:\R[ \t]*)+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\x{0}-\x{8}\x{E}-\x{1F}\x{7F}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Copy shared by the Rewrite tab, the General tab and the capsule.
enum RewriteCopy {
    static let noModelNotice = "To use Rewrite, download a cleanup model in Settings > Models"
    static let failedNotice = "Couldn't rewrite: used your words as dictated"
    static let cutShortNotice = "The rewrite was cut short"
    static let generalHint = "Hold Control+Shift to rewrite as a Jira ticket, chat message, email and more."
    static let tabIntro = "Hold Control+Shift to rewrite what you say in a format for where it's going."

    static func recording(_ template: RewriteTemplateID) -> String { "Rewriting as \(template.inlineName)" }
    static func generating(_ template: RewriteTemplateID) -> String { "Rewriting as \(template.inlineName)…" }
    static func historyCaption(_ template: RewriteTemplateID) -> String { "Rewritten as \(template.inlineName)" }
}
