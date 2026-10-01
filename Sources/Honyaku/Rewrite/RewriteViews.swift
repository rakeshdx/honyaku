import SwiftUI

// MARK: - Settings > Rewrite

/// The Rewrite tab: the "Rewrite as" choice, the template for each kind of app, and each template's prompt.
struct RewriteSettingsView: View {
    @Environment(FeatureEnvironment.self) private var features
    @Environment(AppState.self) private var appState
    /// Whether the selected cleanup model is on disk; checked off the main thread when the tab appears.
    @State private var cleanupModelInstalled: Bool?

    var body: some View {
        let settings = features.store(RewriteSettings.self)
        Form {
            Section {
                Text(RewriteCopy.tabIntro)
                if let note = modelNote {
                    HStack(alignment: .firstTextBaseline) {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Models") {
                            NotificationCenter.default.post(name: SettingsWindowController.showTabNotification,
                                                            object: SettingsWindowController.Tab.models.rawValue)
                        }
                    }
                }
            }
            Section {
                Picker(selection: Binding(get: { settings.fixedTemplate }, set: { settings.fixedTemplate = $0 })) {
                    Text("Automatic (by app)").tag(RewriteTemplateID?.none)
                    Divider()
                    ForEach(RewriteTemplateID.allCases, id: \.self) { template in
                        Text(template.name).tag(RewriteTemplateID?.some(template))
                    }
                } label: {
                    Text("Rewrite as")
                    Text("Also in the menu bar icon's right-click menu.")
                }
            }
            Section {
                ForEach(RewriteSettings.categories, id: \.self) { category in
                    Picker(Self.title(for: category),
                           selection: Binding(get: { settings.template(for: category) },
                                              set: { settings.setTemplate($0, for: category) })) {
                        ForEach(RewriteTemplateID.allCases, id: \.self) { template in
                            Text(template.name).tag(template)
                        }
                    }
                }
            } header: {
                Text("Templates by app")
            } footer: {
                Text(settings.fixedTemplate == nil
                     ? "Chosen by the app that was in front when you started holding the keys."
                     : "Not used while Rewrite as is set to \(settings.fixedTemplate?.name ?? "a template").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Templates") {
                ForEach(RewriteTemplateID.allCases, id: \.self) { template in
                    TemplateRow(template: template, settings: settings)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
        .task(id: appState.selectedCleanupModelID) {
            guard let model = ModelRegistry.model(id: appState.selectedCleanupModelID) else {
                cleanupModelInstalled = false
                return
            }
            cleanupModelInstalled = await Task.detached(priority: .userInitiated) {
                ModelInstaller.isInstalled(model)
            }.value
        }
    }

    private var modelNote: String? {
        if cleanupModelInstalled == false { return "Rewrite needs a cleanup model." }
        if appState.selectedCleanupModelID == ModelRegistry.smallCleanupModelID {
            return "Qwen3-1.7B is fast but writes weaker rewrites. Qwen3-4B is better for this."
        }
        return nil
    }

    static func title(for category: AppCategory) -> String {
        switch category {
        case .chat: return "Chat apps"
        case .email: return "Email"
        case .terminal: return "Terminals"
        case .codeEditor: return "Code editors"
        case .browser: return "Browsers"
        case .other: return "Everything else"
        }
    }
}

/// One template: its name and what it writes, with the editable prompt under Advanced.
private struct TemplateRow: View {
    let template: RewriteTemplateID
    let settings: RewriteSettings
    @State private var showPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
            Text(template.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            DisclosureGroup("Advanced", isExpanded: $showPrompt) {
                TextEditor(text: Binding(get: { settings.editorText(for: template) },
                                         set: { settings.setPrompt($0, for: template) }))
                    .font(.system(.callout))
                    .frame(minHeight: 110)
                    .accessibilityLabel("\(template.name) prompt")
                HStack {
                    Text("Honyaku's rules against inventing facts always apply too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to default") { settings.resetPrompt(for: template) }
                        .disabled(!settings.isEdited(template))
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - General tab

/// Below the status card: how to rewrite, and whether a key press cancels a hold.
struct RewriteGeneralHint: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text(RewriteCopy.generalHint)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if appState.keyPressCancelUnavailable {
            Text(AppCoordinator.keyPressCancelUnavailableMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - History

/// Under a rewrite's text in History: which template it used, and the words that were spoken.
struct RewriteHistoryDetails: View {
    let entry: TranscriptEntry
    @State private var showWords = false

    var body: some View {
        if let template = entry.rewriteTemplateID.flatMap(RewriteTemplateID.init(rawValue:)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RewriteCopy.historyCaption(template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Your words", isExpanded: $showWords) {
                    Text(entry.rawText)
                        .font(Theme.transcript)
                        .lineSpacing(Theme.transcriptLineSpacing)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }
}
