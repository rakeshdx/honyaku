/// What OpenSpec change `per-app-behaviour` adds to the pipeline: the password guard, then the receiving
/// app's formatting rules, both at paste time (see `PipelineStages.live(_:)` for where these run).
@MainActor
enum PerAppStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        make(store: environment.store(AppProfilesStore.self), probe: SystemPasteGuardProbe())
    }

    static func make(store: AppProfilesStore, probe: any PasteGuardProbe) -> PipelineStages {
        PipelineStages(final: [PasteGuardStage(probe: probe), FormattingStage(store: store)])
    }
}
