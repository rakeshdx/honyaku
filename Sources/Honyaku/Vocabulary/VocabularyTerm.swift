import Foundation

/// A word the user wants spelled their way, and the ways the speech model mishears it.
struct VocabularyTerm: Identifiable, Equatable, Sendable {
    var id: UUID
    /// How the term is written, exactly.
    var term: String
    /// Misheard spellings that are replaced by `term`. The term itself always matches, ignoring case.
    var heardAs: [String]
    var enabled: Bool

    init(id: UUID = UUID(), term: String, heardAs: [String] = [], enabled: Bool = true) {
        self.id = id
        self.term = term
        self.heardAs = heardAs
        self.enabled = enabled
    }
}

extension VocabularyTerm: Codable {
    private enum CodingKeys: String, CodingKey { case id, term, heardAs, enabled }

    /// Lenient, so a hand-written or older list imports: only `term` is required.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try container.decode(String.self, forKey: .term)
        heardAs = try container.decodeIfPresent([String].self, forKey: .heardAs) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// `vocabulary.json`, and the format Export writes and Import reads.
struct VocabularyFile: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    /// The user's order: the top of the list matters most.
    var terms: [VocabularyTerm]

    init(version: Int = VocabularyFile.currentVersion, terms: [VocabularyTerm]) {
        self.version = version
        self.terms = terms
    }
}

/// Why an edit to the list was refused. The message is shown under the fields.
enum VocabularyError: Error, Equatable, LocalizedError {
    case emptyTerm
    case tooLong
    case duplicateTerm
    /// The spelling is already used by another term, named here.
    case heardAsInUse(spelling: String, term: String)

    static let maxLength = 100

    var errorDescription: String? {
        switch self {
        case .emptyTerm: return "Enter how the term is written."
        case .tooLong: return "Keep terms and spellings to \(Self.maxLength) characters or fewer."
        case .duplicateTerm: return "Already in your list"
        case let .heardAsInUse(spelling, term): return "\u{201C}\(spelling)\u{201D} is already used by \u{201C}\(term)\u{201D}."
        }
    }
}

/// Why an import was refused before reading the terms.
enum VocabularyImportError: Error, Equatable, LocalizedError {
    case tooLarge

    var errorDescription: String? {
        "A word list can have at most 2,000 terms and be at most 1 MB. Your list is unchanged."
    }
}

/// What an import changed, for the summary shown afterwards.
struct VocabularyImportSummary: Equatable {
    var added = 0
    var updated = 0
    /// Heard-as spellings left out because another term uses them, with that term.
    var skipped: [(spelling: String, term: String)] = []

    var message: String {
        var text = "Added \(added) term\(added == 1 ? "" : "s"), updated \(updated)"
        if let first = skipped.first {
            text += ", skipped \(skipped.count) (already used by \u{201C}\(first.term)\u{201D}"
            text += skipped.count > 1 ? " and others)" : ")"
        }
        return text
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.added == rhs.added && lhs.updated == rhs.updated
            && lhs.skipped.map(\.spelling) == rhs.skipped.map(\.spelling)
            && lhs.skipped.map(\.term) == rhs.skipped.map(\.term)
    }
}

/// Text and spellings are compared ignoring case, with curly and straight apostrophes treated alike.
enum VocabularyText {
    static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
    }

    /// Trimmed, with inner runs of whitespace collapsed to one space.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
