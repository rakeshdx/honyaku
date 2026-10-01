/// What OpenSpec change `custom-vocabulary` adds to the pipeline (see `PipelineStages.live(_:)` for where
/// these run): the Whisper hint and cleanup rule before transcription, and the corrections after it.
@MainActor
enum VocabularyStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        let store = environment.store(VocabularyStore.self)
        return PipelineStages(preparers: [VocabularyPreparer(store: store)],
                              afterTranscription: [VocabularyCorrectionStage(store: store)])
    }
}
