import SwiftUI

struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpeechID = ModelRegistry.defaultSpeechModelID
    @State private var selectedCleanupID = ModelRegistry.defaultCleanupModelID
    @State private var enableDiarization = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var setupDone = false

    var body: some View {
        VStack(spacing: 24) {
            if setupDone {
                doneView
            } else {
                pickerView
            }
        }
        .padding(32)
        .frame(width: 460)
        .onAppear {
            // Restore previously saved selections so the wizard reflects current state
            if appState.setupComplete {
                selectedSpeechID = appState.selectedSpeechModelID
                selectedCleanupID = appState.selectedCleanupModelID
                enableDiarization = appState.diarizationEnabled
            }
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(spacing: 24) {
            Text("Choose Your Models")
                .font(.title2.bold())

            Text("Honyaku downloads models once and runs entirely offline. Nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            ModelPickerSection(
                title: "Speech Model",
                subtitle: "Converts your voice to text",
                models: ModelRegistry.speechModels,
                selectedID: $selectedSpeechID
            )

            ModelPickerSection(
                title: "Cleanup Model",
                subtitle: "Removes filler words and polishes text",
                models: ModelRegistry.cleanupModels,
                selectedID: $selectedCleanupID
            )

            // Diarization toggle (optional — model downloads on first use, ~10 MB)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speaker Diarization").font(.callout.bold())
                    Text("Label multiple speakers [Speaker 1], [Speaker 2] — ~10 MB, downloads on first use")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enableDiarization).labelsHidden()
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if let error = downloadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 360)
                    Text("Downloading… \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download & Start") { startDownload() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.title2.bold())

            Text("Hold ⌃ Control to start recording. Release to transcribe and paste.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Get Started") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Download

    private func startDownload() {
        downloadError = nil
        isDownloading = true
        downloadProgress = 0

        let speechID = selectedSpeechID
        let cleanupID = selectedCleanupID
        let diarizationOn = enableDiarization
        Task.detached(priority: .utility) {
            let installer = ModelInstaller.shared
            do {
                // Speech model first (first half of the bar), then the cleanup model
                let speechModel = ModelRegistry.model(id: speechID)!
                if !ModelInstaller.isInstalled(speechModel) {
                    try await installer.install(speechModel) { p in
                        Task { @MainActor in downloadProgress = p * 0.5 }
                    }
                }

                let cleanupModel = ModelRegistry.model(id: cleanupID)!
                if ModelInstaller.isInstalled(cleanupModel) {
                    Task { @MainActor in downloadProgress = 1.0 }
                } else {
                    try await installer.install(cleanupModel) { p in
                        Task { @MainActor in downloadProgress = 0.5 + p * 0.5 }
                    }
                }

                await MainActor.run {
                    appState.selectedSpeechModelID = selectedSpeechID
                    appState.selectedCleanupModelID = selectedCleanupID
                    appState.diarizationEnabled = diarizationOn
                    appState.setupComplete = true
                    isDownloading = false
                    setupDone = true
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }

}

struct ModelPickerSection: View {
    let title: String
    let subtitle: String
    let models: [ModelInfo]
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(models) { model in
                ModelRowView(model: model, isSelected: selectedID == model.id) {
                    selectedID = model.id
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ModelRowView: View {
    let model: ModelInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName).font(.callout)
                Text("\(model.sizeMB) MB · \(model.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .padding(.vertical, 4)
    }
}
