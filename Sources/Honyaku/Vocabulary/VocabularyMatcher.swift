import Foundation

/// Replaces listed spellings with the terms as the user writes them. Deterministic: no model involved.
///
/// - Every enabled term matches its heard-as spellings and its own spelling, ignoring case and treating
///   curly and straight apostrophes alike.
/// - Whole words or phrases only: no letter or digit directly before or after. A change of script, or a
///   Han, kana or Hangul character, counts as a boundary (those scripts don't separate words with spaces).
///   A space in a spelling matches any run of whitespace. Punctuation and a possessive "'s" are kept.
/// - Never inside a contraction ("Don" leaves "don't" alone), a link, an email address, a path or a code
///   identifier: a whitespace-delimited token with "://", "@", "/", "_" or a "." between letters is only
///   matched as a whole.
/// - Scanning left to right, the longest match wins; on a tie, the term higher in the list. One pass:
///   replaced text is never matched again. `[Speaker N]` labels are left alone.
struct VocabularyMatcher: Sendable {
    private enum Unit: Equatable, Sendable {
        case whitespace
        case character(String)
    }

    private struct Candidate: Sendable {
        let units: [Unit]
        let replacement: String
        /// Position in the list, for ties.
        let rank: Int
    }

    /// Candidates by their first folded character, so most positions try only a few.
    private let candidates: [String: [Candidate]]

    init(terms: [VocabularyTerm]) {
        var byFirst: [String: [Candidate]] = [:]
        for (rank, term) in terms.enumerated() where term.enabled {
            for spelling in [term.term] + term.heardAs {
                let units = Self.units(of: spelling)
                guard case let .character(first)? = units.first else { continue }
                byFirst[first, default: []].append(Candidate(units: units, replacement: term.term, rank: rank))
            }
        }
        candidates = byFirst
    }

    func apply(_ text: String) -> String {
        scan(text).output
    }

    /// The terms, as written, that occur in `text` by any of their spellings, in list order and without
    /// repeats. Uses the same rules as `apply`: boundaries, contractions, links and code, speaker labels.
    func matchedTerms(in text: String) -> [String] {
        scan(text).matches.sorted { $0.rank < $1.rank }.map(\.term)
    }

    /// One left-to-right pass: the corrected text, and each term matched (once, by its best rank).
    private func scan(_ text: String) -> (output: String, matches: [(term: String, rank: Int)]) {
        guard !candidates.isEmpty, !text.isEmpty else { return (text, []) }
        let characters = Array(text)
        let folded = characters.map { Self.fold($0) }
        let protected = Self.protectedTokens(in: characters)
        var output = ""
        output.reserveCapacity(text.utf8.count)
        var matched: [String: Int] = [:]
        var index = 0
        while index < characters.count {
            if let labelEnd = Self.speakerLabelEnd(in: characters, at: index) {
                output.append(contentsOf: characters[index..<labelEnd])
                index = labelEnd
                continue
            }
            let atBoundary = index == 0 || Self.isBoundary(characters[index - 1], characters[index])
            if atBoundary, let match = longestMatch(in: characters, folded: folded, at: index, protected: protected) {
                output += match.replacement
                matched[match.replacement] = min(matched[match.replacement] ?? .max, match.rank)
                index = match.end
                continue
            }
            output.append(characters[index])
            index += 1
        }
        return (output, matched.map { (term: $0.key, rank: $0.value) })
    }

    // MARK: - Matching

    private func longestMatch(in characters: [Character], folded: [String], at start: Int,
                              protected: [ProtectedToken]) -> (replacement: String, end: Int, rank: Int)? {
        guard let options = candidates[folded[start]] else { return nil }
        var best: (replacement: String, end: Int, rank: Int)?
        for candidate in options {
            guard let end = Self.match(candidate.units, in: characters, folded: folded, at: start) else { continue }
            // A letter or digit straight after means it's part of a longer word
            if end < characters.count, !Self.isBoundary(characters[end - 1], characters[end]) { continue }
            if Self.isInsideContraction(characters, matchEnd: end) { continue }
            if !Self.isAllowed(start..<end, by: protected) { continue }
            if let current = best, end < current.end || (end == current.end && candidate.rank >= current.rank) {
                continue
            }
            best = (candidate.replacement, end, candidate.rank)
        }
        return best
    }

    /// Where `units` stop matching the text from `start`, or nil if they don't.
    private static func match(_ units: [Unit], in characters: [Character], folded: [String], at start: Int) -> Int? {
        var position = start
        for unit in units {
            switch unit {
            case .whitespace:
                guard position < characters.count, characters[position].isWhitespace else { return nil }
                while position < characters.count, characters[position].isWhitespace { position += 1 }
            case let .character(expected):
                guard position < characters.count, folded[position] == expected else { return nil }
                position += 1
            }
        }
        return position
    }

    // MARK: - Text

    private static func units(of spelling: String) -> [Unit] {
        var units: [Unit] = []
        for character in VocabularyText.normalized(spelling) {
            if character.isWhitespace {
                if units.last != .whitespace { units.append(.whitespace) }
            } else {
                units.append(.character(fold(character)))
            }
        }
        return units
    }

    private static func fold(_ character: Character) -> String {
        VocabularyText.fold(String(character))
    }

    /// A letter or digit, except in scripts written without spaces between words.
    private static func isWordCharacter(_ character: Character) -> Bool {
        (character.isLetter || character.isNumber) && Script(character) != .unspaced
    }

    /// Whether a match may start or end between `before` and `after`.
    private static func isBoundary(_ before: Character, _ after: Character) -> Bool {
        guard isWordCharacter(before), isWordCharacter(after) else { return true }
        return Script(before) != Script(after)
    }

    /// "Don" in "don't": an apostrophe and a letter right after the match. A possessive "'s" ending the
    /// word is fine.
    private static func isInsideContraction(_ characters: [Character], matchEnd end: Int) -> Bool {
        guard end + 1 < characters.count, characters[end] == "'" || characters[end] == "\u{2019}",
              characters[end + 1].isLetter else { return false }
        let isPossessive = characters[end + 1] == "s" || characters[end + 1] == "S"
        let wordEnds = end + 2 == characters.count || !isWordCharacter(characters[end + 2])
        return !(isPossessive && wordEnds)
    }

    // MARK: - Links and code

    /// A whitespace-delimited token that's a link, email address, path or identifier. Only a match of the
    /// whole token (trailing punctuation aside) may change it.
    private struct ProtectedToken {
        let range: Range<Int>
        /// `range` without trailing sentence punctuation.
        let core: Range<Int>
    }

    private static func protectedTokens(in characters: [Character]) -> [ProtectedToken] {
        var tokens: [ProtectedToken] = []
        var index = 0
        while index < characters.count {
            guard !characters[index].isWhitespace else { index += 1; continue }
            let start = index
            while index < characters.count, !characters[index].isWhitespace { index += 1 }
            let token = characters[start..<index]
            guard isLinkOrCode(token) else { continue }
            var coreEnd = index
            while coreEnd > start, ".,;:!?)]\"'\u{201D}\u{2019}".contains(characters[coreEnd - 1]) { coreEnd -= 1 }
            tokens.append(ProtectedToken(range: start..<index, core: start..<coreEnd))
        }
        return tokens
    }

    private static func isLinkOrCode(_ token: ArraySlice<Character>) -> Bool {
        if token.contains(where: { $0 == "@" || $0 == "/" || $0 == "_" }) { return true }
        // A dot between two letters: a domain or file name such as github.com or main.swift
        let characters = Array(token)
        return characters.indices.dropFirst().dropLast().contains { position in
            characters[position] == "." && characters[position - 1].isLetter && characters[position + 1].isLetter
        }
    }

    private static func isAllowed(_ match: Range<Int>, by protected: [ProtectedToken]) -> Bool {
        for token in protected where token.range.overlaps(match) {
            if token.core != match { return false }
        }
        return true
    }

    /// The end of a `[Speaker N]` label starting at `index`, if there is one.
    private static func speakerLabelEnd(in characters: [Character], at index: Int) -> Int? {
        let prefix = Array("[Speaker ")
        guard characters[index] == "[", index + prefix.count < characters.count,
              Array(characters[index..<(index + prefix.count)]) == prefix else { return nil }
        var position = index + prefix.count
        let digitsStart = position
        while position < characters.count, characters[position].isNumber { position += 1 }
        guard position > digitsStart, position < characters.count, characters[position] == "]" else { return nil }
        return position + 1
    }
}

/// The scripts that matter for word boundaries.
private enum Script: Equatable {
    case latin, greek, cyrillic, arabic, hebrew, devanagari
    /// Han, Hiragana, Katakana and Hangul: written without spaces between words.
    case unspaced
    case other

    init(_ character: Character) {
        guard let scalar = character.unicodeScalars.first?.value else { self = .other; return }
        switch scalar {
        case 0x0041...0x024F, 0x1E00...0x1EFF: self = .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF: self = .greek
        case 0x0400...0x052F: self = .cyrillic
        case 0x0590...0x05FF: self = .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F: self = .arabic
        case 0x0900...0x097F: self = .devanagari
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x31F0...0x31FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF66...0xFF9F, 0x20000...0x2FA1F:
            self = .unspaced
        default: self = character.isNumber ? .latin : .other
        }
    }
}
