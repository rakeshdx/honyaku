/// The pipeline's extension points, in the order a dictation passes them:
///
/// 1. `preparers`: before transcription; may set speech hints and cleanup rules
/// 2. `afterTranscription`: after the speech model and speaker labels, before cleanup
/// 3. `final`: after cleanup and filler removal, once the paste target is known; before routing
///
/// Stages take the context `inout`: a final stage can turn off the paste, and any stage can add a notice.
@MainActor
struct PipelineStages {
    var preparers: [any DictationContextPreparer] = []
    var afterTranscription: [any TextStage] = []
    var final: [any TextStage] = []

    static let none = PipelineStages()

    /// The stages the app runs. Each feature plugs in through its own file in `Pipeline/Stages/` and never
    /// edits this one. Order: Vocabulary, Rewrite, Per-app. In `final`, Rewrite's terminal join runs before
    /// Per-app's formatting, which later covers rewrites too.
    static func live(_ environment: FeatureEnvironment) -> PipelineStages {
        combined([
            VocabularyStages.make(environment),
            RewriteStages.make(environment),
            PerAppStages.make(environment),
        ])
    }

    /// Each list in order: all of the first part's stages, then the second's, and so on.
    static func combined(_ parts: [PipelineStages]) -> PipelineStages {
        PipelineStages(preparers: parts.flatMap(\.preparers),
                       afterTranscription: parts.flatMap(\.afterTranscription),
                       final: parts.flatMap(\.final))
    }

    static func apply(_ stages: [any TextStage], to text: String, context: inout DictationContext) -> String {
        stages.reduce(text) { $1.apply($0, context: &context) }
    }
}
