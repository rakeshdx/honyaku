import Foundation
import Observation

/// Rewrite's saved settings: the "Rewrite as" choice, the template for each kind of app, and edited prompts.
/// Shared through `FeatureEnvironment.store(RewriteSettings.self)` by the pipeline, the right-click menu and
/// the Rewrite tab. Only values that differ from the defaults are stored, so improved defaults reach the user.
@Observable
@MainActor
final class RewriteSettings: FeatureStore {
    static let choiceKey = "rewriteTemplateChoice"
    static let categoryTemplatesKey = "rewriteCategoryTemplates"
    static func promptKey(for template: RewriteTemplateID) -> String { "rewritePrompt.\(template.rawValue)" }

    /// The categories the Rewrite tab lists, in its order.
    static let categories: [AppCategory] = [.chat, .email, .terminal, .codeEditor, .browser, .other]

    @ObservationIgnored private let defaults: UserDefaults

    /// A template picked under "Rewrite as"; nil is Automatic (by app). Sticks until set back to Automatic.
    var fixedTemplate: RewriteTemplateID? {
        didSet { defaults.set(fixedTemplate?.rawValue ?? "automatic", forKey: Self.choiceKey) }
    }

    /// Templates the user chose for a category, where they differ from `RewriteTemplateID.automatic(for:)`.
    private(set) var categoryOverrides: [AppCategory: RewriteTemplateID]
    /// Prompts the user edited, where they differ from the template's default.
    private(set) var editedPrompts: [RewriteTemplateID: String]

    init(environment: FeatureEnvironment) {
        let defaults = environment.defaults
        self.defaults = defaults
        fixedTemplate = defaults.string(forKey: Self.choiceKey).flatMap(RewriteTemplateID.init(rawValue:))
        let stored = defaults.dictionary(forKey: Self.categoryTemplatesKey) as? [String: String] ?? [:]
        categoryOverrides = stored.reduce(into: [:]) { result, pair in
            if let category = AppCategory(rawValue: pair.key), let template = RewriteTemplateID(rawValue: pair.value) {
                result[category] = template
            }
        }
        editedPrompts = RewriteTemplateID.allCases.reduce(into: [:]) { result, template in
            if let prompt = defaults.string(forKey: Self.promptKey(for: template)) { result[template] = prompt }
        }
    }

    // MARK: - Templates by app

    /// The template Automatic uses for `category`.
    func template(for category: AppCategory) -> RewriteTemplateID {
        categoryOverrides[category] ?? RewriteTemplateID.automatic(for: category)
    }

    func setTemplate(_ template: RewriteTemplateID, for category: AppCategory) {
        if template == RewriteTemplateID.automatic(for: category) {
            categoryOverrides[category] = nil
        } else {
            categoryOverrides[category] = template
        }
        let stored = Dictionary(uniqueKeysWithValues: categoryOverrides.map { ($0.key.rawValue, $0.value.rawValue) })
        if stored.isEmpty {
            defaults.removeObject(forKey: Self.categoryTemplatesKey)
        } else {
            defaults.set(stored, forKey: Self.categoryTemplatesKey)
        }
    }

    // MARK: - Prompts

    func prompt(for template: RewriteTemplateID) -> String {
        editedPrompts[template] ?? template.defaultPrompt
    }

    /// Saving the default text removes the stored copy, the same as "Reset to default".
    func setPrompt(_ prompt: String, for template: RewriteTemplateID) {
        if prompt == template.defaultPrompt {
            editedPrompts[template] = nil
            defaults.removeObject(forKey: Self.promptKey(for: template))
        } else {
            editedPrompts[template] = prompt
            defaults.set(prompt, forKey: Self.promptKey(for: template))
        }
    }

    func resetPrompt(for template: RewriteTemplateID) {
        setPrompt(template.defaultPrompt, for: template)
    }

    // MARK: - Choosing

    /// The template for a rewrite that started in `app`: the "Rewrite as" choice, or the one for its category.
    /// An unknown app counts as "everything else".
    func resolvedTemplate(forAppAtStart app: TargetApp?) -> RewriteTemplateID {
        fixedTemplate ?? template(for: app?.category ?? .other)
    }

    func plan(forAppAtStart app: TargetApp?) -> RewritePlan {
        let template = resolvedTemplate(forAppAtStart: app)
        return RewritePlan(template: template, templatePrompt: prompt(for: template))
    }
}
