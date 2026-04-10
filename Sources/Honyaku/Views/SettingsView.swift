import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var transcriptStore: TranscriptStore
    @EnvironmentObject private var permissionManager: PermissionManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cleanupEnabled") private var cleanupEnabled = true
    @AppStorage("diarizationEnabled") private var diarizationEnabled = false
    @AppStorage("cleanupPrompt") private var cleanupPrompt = CleanupService.defaultPrompt
    @AppStorage("selectedSpeechModelID") private var selectedSpeechModelID = ModelRegistry.defaultSpeechModelID
    @AppStorage("selectedCleanupModelID") private var selectedCleanupModelID = ModelRegistry.defaultCleanupModelID

    @State private var selectedSection: String = "models"
    @State private var showClearHistoryAlert = false
    @State private var showHFToken = false
    @State private var hfTokenInput = ""
    @State private var hfTokenSaved = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Label("Models", systemImage: "cpu").tag("models")
                Label("Audio", systemImage: "mic").tag("audio")
                Label("Cleanup", systemImage: "wand.and.stars").tag("cleanup")
                Label("Diarization", systemImage: "person.2").tag("diarization")
                Label("History", systemImage: "clock").tag("history")
                Label("Privacy", systemImage: "lock.shield").tag("privacy")
                Label("General", systemImage: "gearshape").tag("general")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140)
        } detail: {
            Group {
                switch selectedSection {
                case "audio":       audioSection
                case "cleanup":     cleanupSection
                case "diarization": diarizationSection
                case "history":     historySection
                case "privacy":     privacySection
                case "general":     generalSection
                default:            modelsSection
                }
            }
        }
        .frame(width: 560, height: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Form {
            Section("Speech Model") {
                ForEach(ModelRegistry.speechModels) { model in
                    ModelSettingsRow(model: model, selectedID: $selectedSpeechModelID)
                }
            }
            Section("Cleanup Model") {
                ForEach(ModelRegistry.cleanupModels) { model in
                    ModelSettingsRow(model: model, selectedID: $selectedCleanupModelID)
                }
            }
            Section("Diarization Model") {
                ForEach(ModelRegistry.diarizationModels) { model in
                    ModelSettingsRow(model: model, selectedID: .constant(ModelRegistry.defaultDiarizationModelID))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Audio

    private var audioSection: some View {
        Form {
            Section("Microphone") {
                Picker("Input Device", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? "" },
                    set: { UserDefaults.standard.set($0, forKey: "selectedMicrophoneID") }
                )) {
                    Text("System Default").tag("")
                    ForEach(AudioCaptureService.availableInputDevices(), id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
            }
            if !permissionManager.microphoneGranted {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Microphone permission not granted.")
                        Button("Open Settings") { permissionManager.openMicrophoneSettings() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        Form {
            Section {
                Toggle("Enable LLM Cleanup", isOn: $cleanupEnabled)
            }
            Section("System Prompt") {
                TextEditor(text: $cleanupPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        cleanupPrompt = CleanupService.defaultPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Diarization

    private var diarizationSection: some View {
        Form {
            Section {
                Toggle("Enable Speaker Diarization", isOn: $diarizationEnabled)
                    .onChange(of: diarizationEnabled) { _, enabled in
                        if enabled {
                            // Trigger model download if needed
                            appState.diarizationEnabled = enabled
                        }
                    }
            }
            Section("Model") {
                let model = ModelRegistry.diarizationModels[0]
                HStack {
                    Text(model.displayName)
                    Spacer()
                    if ModelStore.shared.isDownloaded(model) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Text("\(model.sizeMB) MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - History

    private var historySection: some View {
        VStack(spacing: 0) {
            List(transcriptStore.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.cleanedText).lineLimit(2)
                    HStack {
                        Text(entry.timestamp, style: .date)
                        Text(entry.timestamp, style: .time)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.cleanedText, forType: .string)
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Clear All History") { showClearHistoryAlert = true }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .disabled(transcriptStore.entries.isEmpty)
            }
            .padding(12)
        }
        .alert("Clear History?", isPresented: $showClearHistoryAlert) {
            Button("Clear", role: .destructive) { transcriptStore.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcript history.")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Form {
            Section("Hugging Face Access Token") {
                Text("Required for downloading certain diarization models. Stored securely in your Keychain — never used at runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if showHFToken {
                        TextField("hf_...", text: $hfTokenInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("hf_...", text: $hfTokenInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showHFToken ? "Hide" : "Show") { showHFToken.toggle() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                HStack {
                    Button("Save Token") {
                        try? KeychainService.save(key: KeychainService.hfTokenKey, value: hfTokenInput)
                        hfTokenSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { hfTokenSaved = false }
                    }
                    .buttonStyle(.bordered)
                    .disabled(hfTokenInput.isEmpty)

                    if hfTokenSaved { Label("Saved", systemImage: "checkmark").foregroundStyle(.green) }

                    Spacer()

                    Button("Remove Token") {
                        KeychainService.delete(key: KeychainService.hfTokenKey)
                        hfTokenInput = ""
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }

            Section("Data Practices") {
                Label("All speech processing happens on your Mac", systemImage: "lock.fill")
                Label("No audio or transcripts are sent to the cloud", systemImage: "icloud.slash")
                Label("Models are downloaded once and used offline", systemImage: "wifi.slash")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hfTokenInput = KeychainService.load(key: KeychainService.hfTokenKey) ?? ""
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert toggle on failure
                            launchAtLogin = !enabled
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
        .padding()
    }
}

// MARK: - Helpers

struct ModelSettingsRow: View {
    let model: ModelInfo
    @Binding var selectedID: String
    @State private var isDownloading = false
    @State private var progress: Double = 0

    private var isDownloaded: Bool { ModelStore.shared.isDownloaded(model) }
    private var isSelected: Bool { selectedID == model.id }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text("\(model.sizeMB) MB · \(model.notes)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isDownloading {
                ProgressView(value: progress).frame(width: 80)
            } else if isDownloaded {
                if isSelected {
                    Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.blue).font(.caption)
                } else {
                    Button("Use") { selectedID = model.id }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Button("Download (\(model.sizeMB) MB)") { downloadModel() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func downloadModel() {
        isDownloading = true
        Task {
            let downloader = ModelDownloader()
            do {
                try await downloader.download(model: model) { p in
                    Task { @MainActor in progress = p }
                }
                await MainActor.run {
                    selectedID = model.id
                    isDownloading = false
                }
            } catch {
                await MainActor.run { isDownloading = false }
            }
        }
    }
}

struct PermissionStatusRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            } else {
                Button("Open Settings") { action() }.buttonStyle(.link).font(.caption)
            }
        }
    }
}
