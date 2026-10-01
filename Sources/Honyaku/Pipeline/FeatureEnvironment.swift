import Foundation
import Observation

/// A feature's saved settings: created once per environment and shared by the feature's pipeline stages
/// and its Settings tab.
@MainActor
protocol FeatureStore: AnyObject {
    init(environment: FeatureEnvironment)
}

/// Where features keep their settings, and the one shared store of each kind.
///
/// The app uses Application Support/Honyaku and `.standard`. Tests, the test host and UI-test launches pass
/// a temporary folder and a private suite, so they never touch the user's data.
@Observable
@MainActor
final class FeatureEnvironment {
    /// Folder for feature files such as `vocabulary.json`.
    @ObservationIgnored let directory: URL
    /// Settings for features that keep small values in UserDefaults.
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var stores: [ObjectIdentifier: AnyObject] = [:]

    init(directory: URL, defaults: UserDefaults) {
        self.directory = directory
        self.defaults = defaults
    }

    /// The app's own: next to `history.json`, with the user's settings.
    static func live() -> FeatureEnvironment {
        FeatureEnvironment(directory: TranscriptStore.defaultFileURL.deletingLastPathComponent(), defaults: .standard)
    }

    /// The shared store of type `S`, created on first use. A feature's stages and its Settings tab both call
    /// this, so they see the same data without a singleton.
    func store<S: FeatureStore>(_ type: S.Type = S.self) -> S {
        if let existing = stores[ObjectIdentifier(type)] as? S { return existing }
        let created = S(environment: self)
        stores[ObjectIdentifier(type)] = created
        return created
    }
}
