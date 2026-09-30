import SwiftUI
import ServiceManagement

/// The native Settings window (⌘,), in five tabs.
struct SettingsView: View {
    enum Tab: String { case general, models, dictation, history, privacy }

    @AppStorage("settingsTab") private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ModelsSettings()
                .tabItem { Label("Models", systemImage: "square.stack.3d.up") }
                .tag(Tab.models)
            DictationSettings()
                .tabItem { Label("Dictation", systemImage: "text.bubble") }
                .tag(Tab.dictation)
            HistorySettings()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "lock") }
                .tag(Tab.privacy)
        }
        .tint(Theme.ai)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("selectedMicrophoneID") private var microphoneID = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    KeycapView(state: .idle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hold Control to talk")
                        Text("Let go to paste the text where you're typing. A tap on its own does nothing.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
                Toggle("Open Honyaku when you log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = !enabled  // revert on failure
                        }
                    }
                Picker("Microphone", selection: $microphoneID) {
                    Text("System default").tag("")
                    ForEach(AudioCaptureService.availableInputDevices(), id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
            }
            Section("Permissions") {
                PermissionStatusRow(title: "Microphone", granted: permissionManager.microphoneGranted,
                                    action: permissionManager.openMicrophoneSettings)
                PermissionStatusRow(title: "Accessibility", granted: permissionManager.accessibilityGranted,
                                    action: permissionManager.openAccessibilitySettings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 360)
        .onAppear { permissionManager.checkAll() }
    }
}

struct PermissionStatusRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ai)
            } else {
                Button("Open System Settings", action: action)
            }
        }
    }
}

// MARK: - Models

struct ModelsSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                ForEach(ModelRegistry.speechModels) { model in
                    ModelSettingsRow(model: model, selectedID: $appState.selectedSpeechModelID)
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("Turns your voice into text.").foregroundStyle(.secondary)
            }
            Section {
                ForEach(ModelRegistry.cleanupModels) { model in
                    ModelSettingsRow(model: model, selectedID: $appState.selectedCleanupModelID)
                }
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Removes filler words and adds punctuation, without changing what you said.").foregroundStyle(.secondary)
            }
            OlderModelsSection()
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
    }
}

struct ModelSettingsRow: View {
    let model: ModelInfo
    @Binding var selectedID: String
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var failure: String?
    @State private var refresh = 0  // re-evaluates disk state after download or delete

    private var state: InstallState { _ = refresh; return ModelInstaller.state(of: model) }
    private var isSelected: Bool { selectedID == model.id }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .monospacedDigit()
            }
            Spacer()
            if isDownloading {
                ProgressView(value: progress).frame(width: 90)
            } else {
                switch state {
                case .installed:
                    if isSelected {
                        Text("In use").font(.callout).foregroundStyle(Theme.ai)
                    } else {
                        Button("Delete", role: .destructive, action: delete)
                        Button("Use") { selectedID = model.id }
                    }
                case .incomplete:
                    Button("Resume download", action: download)
                case .notInstalled:
                    Button("Download", action: download)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        if let failure { return failure }
        if isDownloading { return "Downloading, \(Int(progress * Double(model.sizeMB))) of \(model.sizeMB) MB" }
        if case .installed(let bytes) = state {
            return "\(ModelCopy.summary(for: model)), \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on disk"
        }
        return "\(ModelCopy.summary(for: model)), \(ModelCopy.size(mb: model.sizeMB))"
    }

    private func download() {
        failure = nil
        isDownloading = true
        Task {
            do {
                try await ModelInstaller.shared.install(model) { p in
                    Task { @MainActor in progress = p }
                }
                selectedID = model.id
            } catch {
                failure = "Download didn't finish. Check your connection and try again."
            }
            isDownloading = false
            refresh += 1
        }
    }

    private func delete() {
        Task {
            do { try await ModelInstaller.shared.delete(model) } catch { failure = "Couldn't delete the model files." }
            refresh += 1
        }
    }
}

/// Files from models earlier versions of Honyaku offered, which the registry no longer lists.
/// Removed to the Trash rather than deleted outright, so a mistake can be undone.
struct OlderModelsSection: View {
    @State private var models = RetiredModelFiles.onDisk()

    var body: some View {
        if !models.isEmpty {
            Section {
                ForEach(models, id: \.url) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                            Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file) + " on disk")
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Button("Move to Trash", role: .destructive) {
                            try? FileManager.default.trashItem(at: model.url, resultingItemURL: nil)
                            models = RetiredModelFiles.onDisk()
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Older models")
            } footer: {
                Text("Earlier versions of Honyaku used these. They're no longer needed.").foregroundStyle(.secondary)
            }
        }
    }
}

enum RetiredModelFiles {
    struct Item { let name: String; let url: URL; let bytes: Int64 }

    /// Known folders only (never a scan), so nothing but retired model files can be listed.
    static func onDisk(
        cleanup: URL = ModelStore.shared.baseDirectory.appending(path: "cleanup"),
        whisper: URL = TranscriptionService.localModelFolder(repo: "argmaxinc/whisperkit-coreml", variant: ""),
        fileManager: FileManager = .default
    ) -> [Item] {
        let candidates: [(String, URL)] = [
            ("Qwen 2.5 1.5B", cleanup.appending(path: "qwen-1.5b-mlx")),
            ("Qwen 2.5 3B", cleanup.appending(path: "qwen-3b-mlx")),
            ("Qwen 2.5 7B", cleanup.appending(path: "qwen-7b-mlx")),
            ("Qwen 0.8B", cleanup.appending(path: "qwen-0.8b")),
            ("Qwen 4B", cleanup.appending(path: "qwen-4b")),
            ("Qwen 7B", cleanup.appending(path: "qwen-7b")),
            ("Whisper Tiny (English)", whisper.appending(path: "openai_whisper-tiny.en")),
            ("Whisper Small (English)", whisper.appending(path: "openai_whisper-small.en")),
            ("Whisper Small (Multilingual)", whisper.appending(path: "openai_whisper-small")),
        ]
        return candidates.compactMap { name, url in
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return Item(name: name, url: url, bytes: ModelInstaller.sizeOnDisk(url))
        }
    }
}

// MARK: - Dictation

struct DictationSettings: View {
    @Environment(AppState.self) private var appState
    @State private var showPrompt = false
    // Read by the speech engine per dictation; empty means Auto-detect
    @AppStorage(TranscriptionService.dictationLanguageKey) private var dictationLanguage = ""

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Toggle(isOn: $appState.cleanupEnabled) {
                    Text("Clean up the text")
                    Text("Removes filler words like \"um\" and adds punctuation. Your words are never changed or reordered.")
                }
                Toggle(isOn: $appState.diarizationEnabled) {
                    Text("Label speakers")
                    Text("Adds [Speaker 1], [Speaker 2] when more than one person talks. Downloads a 10 MB model on first use.")
                }
            }
            Section {
                let multilingual = ModelRegistry.model(id: appState.selectedSpeechModelID)?.supportsDictationLanguage ?? false
                Picker(selection: $dictationLanguage) {
                    Text("Auto-detect").tag("")
                    ForEach(TranscriptionService.dictationLanguages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                } label: {
                    Text("Language")
                    Text(multilingual
                         ? "Choose the language you speak if short phrases come out in the wrong language."
                         : "Only the multilingual speech model uses this. The selected model transcribes English.")
                }
                .disabled(!multilingual)
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $showPrompt) {
                    Text("The instructions the cleanup model follows.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.cleanupPrompt)
                        .font(.system(.callout))
                        .frame(minHeight: 150)
                    HStack {
                        Spacer()
                        Button("Reset to default") { appState.cleanupPrompt = CleanupService.defaultPrompt }
                            .disabled(appState.cleanupPrompt == CleanupService.defaultPrompt)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: showPrompt ? 540 : 340)
    }
}

// MARK: - History

struct HistorySettings: View {
    @EnvironmentObject private var transcriptStore: TranscriptStore
    @State private var query = ""
    @State private var confirmDeleteAll = false

    private var results: [TranscriptEntry] { TranscriptStore.filter(transcriptStore.entries, matching: query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search history", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            Group {
                if transcriptStore.entries.isEmpty {
                    placeholder("No dictations yet. Hold Control and speak to add one.")
                } else if results.isEmpty {
                    placeholder("Nothing matches \u{201C}\(query)\u{201D}.")
                } else {
                    List(results) { entry in
                        HistoryRow(entry: entry) { transcriptStore.delete(entry.id) }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(transcriptStore.entries.count) dictation\(transcriptStore.entries.count == 1 ? "" : "s"), stored only on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete all history…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(transcriptStore.entries.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 500, height: 440)
        .confirmationDialog("Delete all history?", isPresented: $confirmDeleteAll) {
            Button("Delete all history", role: .destructive) { transcriptStore.clearAll() }
        } message: {
            Text("All \(transcriptStore.entries.count) dictations are removed from this Mac. This can't be undone.")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

private struct HistoryRow: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.cleanedText)
                .font(Theme.transcript)
                .lineSpacing(Theme.transcriptLineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cleanedText, forType: .string)
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @State private var showAdvanced = false
    @State private var revealToken = false
    @State private var tokenInput = ""
    @State private var tokenSaved = false

    var body: some View {
        Form {
            Section("What stays on your Mac") {
                Label("Speech is turned into text on this Mac", systemImage: "cpu")
                Label("Audio is deleted as soon as it's transcribed", systemImage: "waveform.slash")
                Label("Transcripts are never sent anywhere", systemImage: "icloud.slash")
                Label("Models download once, then work offline", systemImage: "wifi.slash")
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    Text("A Hugging Face access token is only needed to download some speaker-labelling models. It's kept in your Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if revealToken { TextField("hf_…", text: $tokenInput) } else { SecureField("hf_…", text: $tokenInput) }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button(revealToken ? "Hide" : "Show") { revealToken.toggle() }
                    }
                    HStack {
                        Button("Save token") {
                            try? KeychainService.save(key: KeychainService.hfTokenKey, value: tokenInput)
                            tokenSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tokenSaved = false }
                        }
                        .disabled(tokenInput.isEmpty)
                        if tokenSaved { Text("Saved").foregroundStyle(Theme.ai) }
                        Spacer()
                        Button("Remove token", role: .destructive) {
                            KeychainService.delete(key: KeychainService.hfTokenKey)
                            tokenInput = ""
                        }
                        .disabled(tokenInput.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: showAdvanced ? 440 : 300)
        .onAppear { tokenInput = KeychainService.load(key: KeychainService.hfTokenKey) ?? "" }
    }
}
