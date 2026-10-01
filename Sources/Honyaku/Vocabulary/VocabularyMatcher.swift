import Foundation

/// Replaces listed spellings with the terms as the user writes them. Deterministic: no model involved.
///
/// - Every enabled term matches its heard-as spellings and its own spelling, ignoring case and treating
///   curly and straight apostrophes alike.
/// - Whole words or phrases only: no letter or digit directly before or after. A space in a spelling matches
///   any run of whitespace. Punctuation and a possessive "'s" next to a match are kept.
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

    var isEmpty: Bool { candidates.isEmpty }

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
        guard !candidates.isEmpty, !text.isEmpty else { return text }
        let characters = Array(text)
        let folded = characters.map { Self.fold($0) }
        var output = ""
        output.reserveCapacity(text.utf8.count)
        var index = 0
        while index < characters.count {
            if let labelEnd = Self.speakerLabelEnd(in: characters, at: index) {
                output.append(contentsOf: characters[index..<labelEnd])
                index = labelEnd
                continue
            }
            let atBoundary = index == 0 || !Self.isWordCharacter(characters[index - 1])
            if atBoundary, let match = longestMatch(in: characters, folded: folded, at: index) {
                output += match.replacement
                index = match.end
                continue
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }

    // MARK: - Matching

    private func longestMatch(in characters: [Character], folded: [String],
                              at start: Int) -> (replacement: String, end: Int)? {
        guard let options = candidates[folded[start]] else { return nil }
        var best: (replacement: String, end: Int, rank: Int)?
        for candidate in options {
            guard let end = Self.match(candidate.units, in: characters, folded: folded, at: start) else { continue }
            // A letter or digit straight after means it's part of a longer word
            if end < characters.count, Self.isWordCharacter(characters[end]) { continue }
            if let current = best, end < current.end || (end == current.end && candidate.rank >= current.rank) {
                continue
            }
            best = (candidate.replacement, end, candidate.rank)
        }
        return best.map { ($0.replacement, $0.end) }
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

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
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
