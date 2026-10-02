/// What OpenSpec change `custom-vocabulary` adds to the pipeline (see `PipelineStages.live(_:)` for where
/// these run): the Whisper hint and cleanup rule before transcription, and the corrections after it.
@MainActor
enum VocabularyStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        let store = environment.store(VocabularyStore.self)
        let snapshot = VocabularySnapshot()
        return PipelineStages(preparers: [VocabularyPreparer(store: store, snapshot: snapshot)],
                              afterTranscription: [VocabularyCorrectionStage(snapshot: snapshot)])
    }
}
