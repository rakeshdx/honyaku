import Foundation

/// The vocabulary as Whisper's previous-context prompt: a plain comma-separated glossary, never an
/// instruction, so Whisper treats it as earlier speech rather than something to repeat.
enum WhisperHint {
    /// WhisperKit 0.18.0 keeps only the last 111 prompt tokens (`TextDecoder` trims to `224 / 2 - 1` from the front).
    static let maxTokens = 111

    /// Prompt tokens for `glossary` (most important term last): as many terms from its end as fit in
    /// `maxTokens`, never cutting a term. `encode` turns text into tokens without special tokens.
    /// Nil when no term fits or the glossary is empty.
    static func promptTokens(glossary: [String], encode: (String) -> [Int]) -> [Int]? {
        var best: [Int]?
        var included: [String] = []
        for term in glossary.reversed() {
            let attempt = [term] + included
            let tokens = encode(text(for: attempt))
            guard tokens.count <= maxTokens else { break }
            included = attempt
            best = tokens
        }
        return best
    }

    /// The prompt text: a leading space, as Whisper's own prompts have, then the terms in order.
    static func text(for terms: [String]) -> String {
        " " + terms.joined(separator: ", ")
    }

    /// How many terms from the top of the list (`terms`, most important first) are likely to fit, for the
    /// tab's approximate mark: about one token per 4 characters, plus one per separator. The exact cut is
    /// made at each dictation with the speech model's own tokenizer.
    static func estimatedTermCount(_ terms: [String]) -> Int {
        var used = 0
        var count = 0
        for term in terms {
            let cost = Int((Double(term.count) / 4).rounded(.up)) + 1
            guard used + cost <= maxTokens else { break }
            used += cost
            count += 1
        }
        return count
    }
}
