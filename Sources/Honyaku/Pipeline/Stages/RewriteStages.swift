/// What OpenSpec change `rewrite-modes` adds to the pipeline. Empty until that feature lands; it plugs in by
/// editing only this file (see `PipelineStages.live(_:)` for where these run).
@MainActor
enum RewriteStages {
    static func make(_ environment: FeatureEnvironment) -> PipelineStages {
        .none
    }
}
