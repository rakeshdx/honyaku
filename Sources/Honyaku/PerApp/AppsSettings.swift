import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Apps: formatting rules per category, and apps with their own rules.
struct AppsSettings: View {
    @Environment(FeatureEnvironment.self) private var features

    var body: some View {
        AppsSettingsForm(store: features.store(AppProfilesStore.self))
    }
}

private struct AppsSettingsForm: View {
    @Bindable var store: AppProfilesStore
    @State private var expanded: Set<String> = []

    var body: some View {
        Form {
            if let notice = store.fileNotice {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Dismiss") { store.fileNotice = nil }
                    }
                }
            }
            Section {
                Text("Formatting only. Honyaku never changes your words here.")
                    .foregroundStyle(.secondary)
            }
            Section("Categories") {
                ForEach(AppCategory.allCases, id: \.self) { category in
                    DisclosureGroup(isExpanded: isExpanded(category.rawValue)) {
                        RulesEditor(rules: categoryBinding(category))
                        if store.profiles.isChanged(category) {
                            HStack {
                                Spacer()
                                Button("Reset to defaults") {
                                    store.profiles.setRules(.defaults(for: category), for: category)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(category.displayName)
                            Spacer()
                            if store.profiles.isChanged(category) {
                                Text("Changed").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                if store.profiles.apps.isEmpty {
                    Text("No apps have their own rules. Each app follows its category.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.profiles.apps) { app in
                    DisclosureGroup(isExpanded: isExpanded("app." + app.id)) {
                        RulesEditor(rules: appBinding(app.bundleID))
                        HStack {
                            Spacer()
                            Button("Delete", role: .destructive) {
                                store.profiles.removeApp(bundleID: app.bundleID)
                            }
                            .accessibilityLabel("Delete \(app.displayName)'s rules")
                        }
                    } label: {
                        AppRowLabel(bundleID: app.bundleID, displayName: app.displayName)
                    }
                    .accessibilityIdentifier("apps.override.\(app.bundleID)")
                }
            } header: {
                HStack {
                    Text("Apps with their own rules")
                    Spacer()
                    AddAppMenu(store: store) { added in expanded.insert("app." + added.lowercased()) }
                }
            }
            Section {
                Text("Honyaku never pastes into password fields. Terminals can't report password prompts, so don't dictate passwords into them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
    }

    private func isExpanded(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    private func categoryBinding(_ category: AppCategory) -> Binding<FormattingRules> {
        Binding(get: { store.profiles.rules(for: category) },
                set: { store.profiles.setRules($0, for: category) })
    }

    private func appBinding(_ bundleID: String) -> Binding<FormattingRules> {
        Binding(get: { store.profiles.override(forBundleID: bundleID)?.rules ?? .asSpoken },
                set: { store.profiles.setRules($0, forApp: bundleID) })
    }
}

private struct AppRowLabel: View {
    let bundleID: String
    let displayName: String

    var body: some View {
        let app = AppIdentity.of(bundleID: bundleID)
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(displayName)
            if !app.isInstalled {
                Text("Not installed").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName), own rules")
    }
}

/// The six rules, as pickers and toggles.
private struct RulesEditor: View {
    @Binding var rules: FormattingRules

    var body: some View {
        Picker("Final full stop", selection: $rules.finalFullStop) {
            Text("Keep").tag(FormattingRules.FullStop.keep)
            Text("Drop").tag(FormattingRules.FullStop.drop)
        }
        Picker("First letter", selection: $rules.firstLetter) {
            Text("As spoken").tag(FormattingRules.FirstLetter.asSpoken)
            Text("Lowercase").tag(FormattingRules.FirstLetter.lowercase)
        }
        Picker("Quotes", selection: $rules.quotes) {
            Text("As spoken").tag(FormattingRules.Quotes.asSpoken)
            Text("Straight").tag(FormattingRules.Quotes.straight)
        }
        Picker("Line breaks", selection: $rules.lineBreaks) {
            Text("Keep").tag(FormattingRules.LineBreaks.keep)
            Text("Join into one line").tag(FormattingRules.LineBreaks.join)
        }
        Toggle("Add a space after the text", isOn: $rules.trailingSpace)
        Toggle(isOn: $rules.paste) {
            Text("Paste")
            Text("When off, the text is saved to History and not pasted.")
        }
    }
}

/// + menu: the running apps (not Honyaku, not ones already listed), then "Choose app…".
private struct AddAppMenu: View {
    let store: AppProfilesStore
    let onAdd: (String) -> Void

    var body: some View {
        Menu {
            let running = runningApps
            ForEach(running, id: \.bundleID) { app in
                Button(app.name) { add(bundleID: app.bundleID, name: app.name) }
            }
            if !running.isEmpty { Divider() }
            Button("Choose app…", action: chooseApp)
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add an app")
        .accessibilityLabel("Add an app")
        .accessibilityIdentifier("apps.add")
    }

    private var runningApps: [(bundleID: String, name: String)] {
        let listed = Set(store.profiles.apps.map(\.id))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !listed.contains(id.lowercased()), seen.insert(id.lowercased()).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(bundleID: String, name: String) {
        store.profiles.addApp(bundleID: bundleID, displayName: name)
        onAdd(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID: bundleID, name: AppIdentity.displayName(of: url))
    }
}
