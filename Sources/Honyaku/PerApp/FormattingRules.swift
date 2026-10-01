import Foundation

/// How text is formatted for one app or category. Formatting only: punctuation, letter case, quote
/// characters and whitespace change; words are never added, removed or reordered.
struct FormattingRules: Codable, Equatable, Sendable {
    enum FullStop: String, Codable, CaseIterable, Sendable { case keep, drop }
    enum FirstLetter: String, Codable, CaseIterable, Sendable { case asSpoken, lowercase }
    enum Quotes: String, Codable, CaseIterable, Sendable { case asSpoken, straight }
    enum LineBreaks: String, Codable, CaseIterable, Sendable { case keep, join }

    var finalFullStop: FullStop = .keep
    var firstLetter: FirstLetter = .asSpoken
    var quotes: Quotes = .asSpoken
    var lineBreaks: LineBreaks = .keep
    /// Adds one space after the text, so the next dictation doesn't run into it.
    var trailingSpace = false
    /// Off: the text is saved to History and not pasted.
    var paste = true

    /// Everything as spoken, pasted.
    static let asSpoken = FormattingRules()

    init(finalFullStop: FullStop = .keep, firstLetter: FirstLetter = .asSpoken, quotes: Quotes = .asSpoken,
         lineBreaks: LineBreaks = .keep, trailingSpace: Bool = false, paste: Bool = true) {
        self.finalFullStop = finalFullStop
        self.firstLetter = firstLetter
        self.quotes = quotes
        self.lineBreaks = lineBreaks
        self.trailingSpace = trailingSpace
        self.paste = paste
    }

    /// A field missing from a saved file reads as its as-spoken value, so rules added later don't break
    /// older files.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finalFullStop = try container.decodeIfPresent(FullStop.self, forKey: .finalFullStop) ?? .keep
        firstLetter = try container.decodeIfPresent(FirstLetter.self, forKey: .firstLetter) ?? .asSpoken
        quotes = try container.decodeIfPresent(Quotes.self, forKey: .quotes) ?? .asSpoken
        lineBreaks = try container.decodeIfPresent(LineBreaks.self, forKey: .lineBreaks) ?? .keep
        trailingSpace = try container.decodeIfPresent(Bool.self, forKey: .trailingSpace) ?? false
        paste = try container.decodeIfPresent(Bool.self, forKey: .paste) ?? true
    }

    /// The built-in rules for a category (decision Q26).
    static func defaults(for category: AppCategory) -> FormattingRules {
        switch category {
        case .terminal: return FormattingRules(finalFullStop: .drop, quotes: .straight, lineBreaks: .join)
        case .codeEditor: return FormattingRules(finalFullStop: .drop, quotes: .straight)
        case .chat, .email, .browser, .other: return .asSpoken
        }
    }

    // MARK: - Applying

    /// The text formatted by these rules, in order: quotes, line breaks, final full stop, first letter,
    /// trailing space. `protectedTerms` (vocabulary terms) keep their first letter.
    func apply(to text: String, protectedTerms: [String] = []) -> String {
        var result = text
        if quotes == .straight { result = Self.straightenQuotes(result) }
        if lineBreaks == .join { result = Self.joinLines(result) }
        if finalFullStop == .drop { result = Self.droppingFinalFullStop(result) }
        if firstLetter == .lowercase { result = Self.lowercasingFirstLetter(result, protectedTerms: protectedTerms) }
        if trailingSpace, let last = result.last, !last.isWhitespace { result += " " }
        return result
    }

    static func straightenQuotes(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}": result.append("'")
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}": result.append("\"")
            default: result.append(character)
            }
        }
        return result
    }

    /// One line: each whitespace run that contains a line break becomes a single space, and there's no
    /// line break at either end.
    static func joinLines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "^\\s*\\R\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\R\\s*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\R\\s*", with: " ", options: .regularExpression)
    }

    /// Drops a single "." that ends the text (ignoring trailing whitespace); "...", "?" and "!" stay.
    static func droppingFinalFullStop(_ text: String) -> String {
        guard let lastIndex = text.lastIndex(where: { !$0.isWhitespace }), text[lastIndex] == "." else { return text }
        if lastIndex > text.startIndex, text[text.index(before: lastIndex)] == "." { return text }
        var result = text
        result.remove(at: lastIndex)
        return result
    }

    /// Lowercases the first letter unless the first word is "I" (or a contraction of it), has another
    /// capital letter (API, iOS, GitHub), is a protected term, or is a speaker label.
    static func lowercasingFirstLetter(_ text: String, protectedTerms: [String]) -> String {
        guard !text.hasPrefix("[Speaker "),
              let wordStart = text.firstIndex(where: { !$0.isWhitespace }) else { return text }
        let wordEnd = text[wordStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
        let word = text[wordStart..<wordEnd]
        guard let letterIndex = word.firstIndex(where: \.isLetter), word[letterIndex].isUppercase else { return text }
        let letters = word[letterIndex...]
        let bare = letters.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        if bare == "I" || bare.hasPrefix("I'") || bare.hasPrefix("I\u{2019}") { return text }
        if letters.dropFirst().contains(where: \.isUppercase) { return text }
        // A term ends at a word boundary: "Jira's", "Paramount+," but not "Jiras"
        if protectedTerms.contains(where: { term in
            guard !term.isEmpty, letters.hasPrefix(term) else { return false }
            return letters.dropFirst(term.count).first.map { !($0.isLetter || $0.isNumber) } ?? true
        }) {
            return text
        }
        var result = text
        result.replaceSubrange(letterIndex...letterIndex, with: String(word[letterIndex]).lowercased())
        return result
    }
}

extension AppCategory {
    /// How the Apps tab names the category.
    var displayName: String {
        switch self {
        case .terminal: return "Terminals"
        case .codeEditor: return "Code editors"
        case .chat: return "Chat"
        case .email: return "Email"
        case .browser: return "Browsers"
        case .other: return "Everything else"
        }
    }
}
