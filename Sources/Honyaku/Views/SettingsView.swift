import SwiftUI
import ServiceManagement

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("selectedMicrophoneID") private var microphoneID = ""

    var body: some View {
        Form {
            Section {
                StatusCard()
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
        .frame(width: 500, height: 420)
        .onAppear { permissionManager.checkAll() }
    }
}

/// What Honyaku is doing right now: the keycap, the state (or the full error), the active models, and
/// any model downloading in the background. With no popover, this is where status lives.
struct StatusCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                KeycapView(state: KeycapView.KeyState(appState.status), level: appState.inputLevel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(StatusCopy.stateLine(for: appState.status))
                        .foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(StatusCopy.detailLine(for: appState.status,
                                               speechModelID: appState.selectedSpeechModelID,
                                               cleanupEnabled: appState.cleanupEnabled))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
            }
            ForEach(appState.modelDownloads.sorted { $0.key < $1.key }, id: \.key) { id, fraction in
                DownloadLine(modelID: id, fraction: fraction)
            }
        }
        .padding(.vertical, 2)
    }

    private var isError: Bool {
        if case .error = appState.status { return true }
        return false
    }
}

/// One background download: a caption and a slim progress bar in the accent tint.
struct DownloadLine: View {
    let modelID: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StatusCopy.downloadLine(modelID: modelID, fraction: fraction))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // Drawn rather than a ProgressView, which turns gray whenever the window isn't key
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ai.opacity(0.15))
                    Capsule().fill(Theme.ai).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

enum StatusCopy {
    static func stateLine(for status: AppStatus) -> String {
        switch status {
        case .idle: return "Hold Control to talk"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .processing: return "Cleaning up…"
        case .error(let message): return message
        }
    }

    /// While idle, how to dictate plus the active models; otherwise just the models.
    static func detailLine(for status: AppStatus, speechModelID: String, cleanupEnabled: Bool) -> String {
        let speech = ModelRegistry.model(id: speechModelID)?.displayName ?? "No speech model"
        let models = "\(speech), cleanup \(cleanupEnabled ? "on" : "off")"
        guard status == .idle else { return models }
        return "Let go to paste the text where you're typing. \(models)."
    }

    static func downloadLine(modelID: String, fraction: Double) -> String {
        let name = ModelRegistry.model(id: modelID)?.displayName ?? modelID
        return "Downloading \(name), \(Int((fraction * 100).rounded()))%"
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

/// Each model's install state and the retired model files, computed off the main thread so the Models
/// tab never walks the disk while drawing. Refreshed when the tab appears, after a download, delete or
/// Move to Trash, and when a background download starts or finishes — never on a progress tick.
@MainActor
final class ModelInstallStates: ObservableObject {
    @Published private(set) var states: [String: InstallState] = [:]
    @Published private(set) var retired: [RetiredModelFiles.Item] = []
    /// Move to Trash failures, by folder
    @Published private(set) var trashFailures: [URL: String] = [:]

    static let models = ModelRegistry.speechModels + ModelRegistry.cleanupModels

    func refresh() async { await refresh(Self.models) }

    func refresh(_ models: [ModelInfo]) async {
        let results = await Task.detached(priority: .userInitiated) {
            models.map { ($0.id, ModelInstaller.state(of: $0)) }
        }.value
        for (id, state) in results { states[id] = state }
    }

    func refreshRetired() async {
        retired = await Task.detached(priority: .userInitiated) { RetiredModelFiles.onDisk() }.value
    }

    func moveToTrash(_ item: RetiredModelFiles.Item) async {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            trashFailures[item.url] = nil
        } catch {
            trashFailures[item.url] = "Couldn't move it to the Trash: \(error.localizedDescription)"
        }
        await refreshRetired()
    }
}

struct ModelsSettings: View {
    @Environment(AppState.self) private var appState
    @StateObject private var installs = ModelInstallStates()

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                ForEach(ModelRegistry.speechModels) { model in
                    ModelSettingsRow(model: model, selectedID: $appState.selectedSpeechModelID,
                                     state: installs.states[model.id]) { await installs.refresh([model]) }
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("Turns your voice into text.").foregroundStyle(.secondary)
            }
            Section {
                ForEach(ModelRegistry.cleanupModels) { model in
                    ModelSettingsRow(model: model, selectedID: $appState.selectedCleanupModelID,
                                     state: installs.states[model.id]) { await installs.refresh([model]) }
                }
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Removes filler words and adds punctuation, without changing what you said.").foregroundStyle(.secondary)
            }
            OlderModelsSection(installs: installs)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .task {
            await installs.refresh()
            await installs.refreshRetired()
        }
        // A background download started or finished (the key set doesn't change on progress ticks)
        .onChange(of: Set(appState.modelDownloads.keys)) { _, _ in
            Task { await installs.refresh() }
        }
    }
}

struct ModelSettingsRow: View {
    let model: ModelInfo
    @Binding var selectedID: String
    /// nil until the Models tab has checked the disk
    let state: InstallState?
    /// Re-checks this model's state after a download or delete
    let onChange: () async -> Void
    @Environment(AppState.self) private var appState
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var failure: String?

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
            } else if let background {
                ProgressView(value: background).frame(width: 90)
            } else {
                switch state {
                case .installed?:
                    if isSelected {
                        Text("In use").font(.callout).foregroundStyle(Theme.ai)
                    } else {
                        Button("Delete", role: .destructive, action: delete)
                        Button("Use") { selectedID = model.id }
                    }
                case .incomplete?:
                    Button("Resume download", action: download)
                case .notInstalled?:
                    Button("Download", action: download)
                case nil:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A download started in the background (e.g. after a migration) rather than from this row.
    private var background: Double? { appState.modelDownloads[model.id] }

    private var detail: String {
        if let failure { return failure }
        if isDownloading { return "Downloading, \(Int(progress * Double(model.sizeMB))) of \(model.sizeMB) MB" }
        if let background { return "Downloading, \(Int(background * Double(model.sizeMB))) of \(model.sizeMB) MB" }
        if case .installed(let bytes)? = state {
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
            await onChange()
            isDownloading = false
        }
    }

    private func delete() {
        failure = nil
        Task {
            do {
                try await ModelInstaller.shared.delete(model)
            } catch {
                failure = "Couldn't delete the model files: \(error.localizedDescription)"
            }
            await onChange()
        }
    }
}

/// Files from models earlier versions of Honyaku offered, which the registry no longer lists.
/// Removed to the Trash rather than deleted outright, so a mistake can be undone.
struct OlderModelsSection: View {
    @ObservedObject var installs: ModelInstallStates

    var body: some View {
        if !installs.retired.isEmpty {
            Section {
                ForEach(installs.retired, id: \.url) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                            if let failure = installs.trashFailures[model.url] {
                                Text(failure).font(.callout).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file) + " on disk")
                                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer()
                        Button("Move to Trash", role: .destructive) {
                            Task { await installs.moveToTrash(model) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Older models")
            } footer: {
                Text("Earlier versions of Honyaku downloaded these. If another app uses WhisperKit, it may use them too.")
                    .foregroundStyle(.secondary)
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
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.cleanedText)
                .font(Theme.transcript)
                .lineSpacing(Theme.transcriptLineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                // Visible and in the key loop, not only in the context menu
                HStack(spacing: 6) {
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy")
                    .accessibilityLabel(copied ? "Copied" : "Copy")
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                    .accessibilityLabel("Delete")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.cleanedText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @State private var showAdvanced = false
    @State private var revealToken = false
    @State private var tokenInput = ""
    @State private var tokenSaved = false
    @State private var tokenError: String?

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
                        Button("Save token", action: saveToken)
                            .disabled(tokenInput.isEmpty)
                        if tokenSaved { Text("Saved").foregroundStyle(Theme.ai) }
                        Spacer()
                        Button("Remove token", role: .destructive) {
                            KeychainService.delete(key: KeychainService.hfTokenKey)
                            tokenInput = ""
                        }
                        .disabled(tokenInput.isEmpty)
                    }
                    if let tokenError {
                        Text(tokenError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: showAdvanced ? 440 : 300)
        .onAppear { tokenInput = KeychainService.load(key: KeychainService.hfTokenKey) ?? "" }
        // The token is hidden again whenever the tab is left
        .onDisappear { revealToken = false }
    }

    private func saveToken() {
        do {
            try KeychainService.save(key: KeychainService.hfTokenKey, value: tokenInput)
            tokenError = nil
            tokenSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tokenSaved = false }
        } catch {
            tokenSaved = false
            tokenError = "Couldn't save the token to your Keychain: \(error.localizedDescription) Try again."
        }
    }
}
