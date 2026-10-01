import CoreML
import WhisperKit

/// Stops Whisper ending a prompted window before it has sampled anything.
///
/// WhisperKit 0.18.0 applies its own blank filter at the prefill-cache index, which is 0 whenever prompt
/// tokens are used, not at the first sampled token. Without this, a vocabulary hint makes Whisper emit
/// end-of-text straight away and the transcript comes back empty. Like WhisperKit's filter without a
/// prompt (and OpenAI's reference), it acts only until the first token is sampled, so a window with no
/// speech can still end without a word. Only windows that start with `<|startofprev|>` are touched.
final class WhisperPromptBlankFilter: LogitsFiltering {
    private let specialTokens: SpecialTokens

    init(specialTokens: SpecialTokens) {
        self.specialTokens = specialTokens
    }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        guard Self.isBeforeFirstSample(tokens, specialTokens: specialTokens) else { return logits }
        for token in [specialTokens.endToken, specialTokens.whitespaceToken] {
            logits[[0, 0, NSNumber(value: token)]] = NSNumber(value: -Float.infinity)
        }
        return logits
    }

    /// True while `tokens` is still just the prompted prefill: `<|startofprev|>`, the prompt, then
    /// `<|startoftranscript|>`, any language and task tokens, and one timestamp (or no-timestamps) token.
    /// WhisperKit passes the whole prefill on every prefill step, and an end-of-text predicted on any of
    /// them ends the window, so all of those steps and the first sampled position are covered.
    static func isBeforeFirstSample(_ tokens: [Int], specialTokens: SpecialTokens) -> Bool {
        guard tokens.first == specialTokens.startOfPreviousToken,
              let start = tokens.lastIndex(of: specialTokens.startOfTranscriptToken),
              let last = tokens.last, isTimestampMarker(last, specialTokens) else { return false }
        let prefill = tokens[start...]
        // SOT, at most language and task, then the one timestamp token: nothing sampled yet
        return prefill.count <= 4
            && prefill.allSatisfy { $0 >= specialTokens.specialTokenBegin }
            && !prefill.dropLast().contains { isTimestampMarker($0, specialTokens) }
    }

    private static func isTimestampMarker(_ token: Int, _ specialTokens: SpecialTokens) -> Bool {
        token >= specialTokens.timeTokenBegin || token == specialTokens.noTimestampsToken
    }
}
