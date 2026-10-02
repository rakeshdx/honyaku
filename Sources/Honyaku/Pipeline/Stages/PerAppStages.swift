/// What OpenSpec change `per-app-behaviour` adds to the pipeline: the receiving app's formatting rules,
/// then the password guard, both at paste time (see `PipelineStages.live(_:)` for where these run). The
/// guard goes last so it knows whether the rules turned the paste off before it warns.
@MainActor
enum PerAppStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        make(store: environment.store(AppProfilesStore.self), probe: SystemPasteGuardProbe())
    }

    static func make(store: AppProfilesStore, probe: any PasteGuardProbe) -> PipelineStages {
        PipelineStages(final: [FormattingStage(store: store), PasteGuardStage(probe: probe)])
    }
}
