import CoreML
import WhisperKit

/// Stops Whisper ending a window before its first word when a prompt is given.
///
/// WhisperKit 0.18.0 applies its own blank filter at the prefill-cache index, which is 0 whenever prompt
/// tokens are used, not at the first sampled token. Without this, a vocabulary hint makes Whisper emit
/// end-of-text straight away and the transcript comes back empty. Only acts on windows that start with
/// `<|startofprev|>` (a prompt), and only until the first non-special token is sampled.
final class WhisperPromptBlankFilter: LogitsFiltering {
    private let specialTokens: SpecialTokens

    init(specialTokens: SpecialTokens) {
        self.specialTokens = specialTokens
    }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        guard tokens.first == specialTokens.startOfPreviousToken,
              let start = tokens.lastIndex(of: specialTokens.startOfTranscriptToken),
              tokens[start...].allSatisfy({ $0 >= specialTokens.specialTokenBegin }) else { return logits }
        for token in [specialTokens.endToken, specialTokens.whitespaceToken] {
            logits[[0, 0, NSNumber(value: token)]] = NSNumber(value: -Float.infinity)
        }
        return logits
    }
}
