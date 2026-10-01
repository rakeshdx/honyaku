import Foundation

/// Runs a rewrite in the pipeline's model step. Whatever happens, the user's words are never lost: without a
/// model, or when the model fails, the dictation goes ahead as plain dictation with a notice.
@MainActor
enum RewriteStep {
    /// `installed` is whether the selected cleanup model is on disk. Returns the rewrite, or `text` unchanged
    /// after switching the context back to plain dictation (so filler removal applies and History says so).
    static func run(_ text: String, plan: RewritePlan, installed: Bool, context: inout DictationContext,
                    cleanup: any CleanupServiceProtocol) async -> String {
        guard installed else {
            fallBack(&context, notice: RewriteCopy.noModelNotice)
            return text
        }
        let request = plan.request(for: text, extraRules: context.cleanupRules, englishFillers: context.englishFillers)
        do {
            let output = try await cleanup.generate(text, request: request)
            // Reasoning the cap cut off is never pasted, and what came before it isn't the rewrite
            guard !output.reasoningCutOff else {
                fallBack(&context, notice: RewriteCopy.failedNotice)
                return text
            }
            var rewrite = RewritePrompt.stripEchoes(output.text, plan: plan)
            if output.hitTokenLimit, !rewrite.isEmpty {
                // Stopped mid-sentence at the cap: keep what's complete and say so
                rewrite = RewritePrompt.trimmedToLastComplete(rewrite)
                if !rewrite.isEmpty { context.notices.append(RewriteCopy.cutShortNotice) }
            }
            guard !rewrite.isEmpty else {
                fallBack(&context, notice: RewriteCopy.failedNotice)
                return text
            }
            return rewrite
        } catch {
            // Timeout, model not loaded, or any other error: the words as dictated, with no second model call
            fallBack(&context, notice: RewriteCopy.failedNotice)
            return text
        }
    }

    private static func fallBack(_ context: inout DictationContext, notice: String) {
        context.mode = .dictate
        context.rewrite = nil
        context.notices.append(notice)
    }
}
