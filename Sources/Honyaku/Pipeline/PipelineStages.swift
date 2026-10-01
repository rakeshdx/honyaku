/// The pipeline's extension points, in the order a dictation passes them:
///
/// 1. `preparers`: before transcription; may set speech hints and cleanup rules
/// 2. `afterTranscription`: after the speech model and speaker labels, before cleanup
/// 3. `final`: after cleanup and filler removal, once the paste target is known; before routing
@MainActor
struct PipelineStages {
    var preparers: [any DictationContextPreparer] = []
    var afterTranscription: [any TextStage] = []
    var final: [any TextStage] = []

    static let none = PipelineStages()

    /// The stages the app runs. Each feature adds its own, one per line.
    static var live: PipelineStages {
        PipelineStages(
            preparers: [
            ],
            afterTranscription: [
            ],
            final: [
            ]
        )
    }

    static func apply(_ stages: [any TextStage], to text: String, context: DictationContext) -> String {
        stages.reduce(text) { $1.apply($0, context: context) }
    }
}
