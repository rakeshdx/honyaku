/// What OpenSpec change `rewrite-modes` adds to the pipeline (see `PipelineStages.live(_:)` for where these run):
/// a preparer that picks the template for a rewrite, and a final stage that puts a rewrite into a terminal on
/// one line. `llmStage` runs the rewrite itself.
@MainActor
enum RewriteStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        PipelineStages(preparers: [RewritePlanner(settings: environment.store(RewriteSettings.self))],
                       final: [TerminalOneLine()])
    }
}

/// For a rewrite, chooses the template from the app the recording started in, before anything is transcribed.
@MainActor
struct RewritePlanner: DictationContextPreparer {
    let settings: RewriteSettings

    func prepare(_ context: inout DictationContext) {
        guard context.mode == .rewrite else { return }
        context.rewrite = settings.plan(forAppAtStart: context.appAtStart)
    }
}

/// A rewrite pasted into a terminal is one line, so pasting it can't run anything. Per-app formatting
/// (`per-app-behaviour`) runs after this and may take over the join.
@MainActor
struct TerminalOneLine: TextStage {
    func apply(_ text: String, context: inout DictationContext) -> String {
        guard context.mode == .rewrite, context.appAtPaste?.category == .terminal else { return text }
        return RewritePrompt.joinedOnOneLine(text)
    }
}
