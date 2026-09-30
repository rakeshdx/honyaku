import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var transcriptStore: TranscriptStore
    @EnvironmentObject private var permissionManager: PermissionManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            downloadLines
            Divider()

            if transcriptStore.entries.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()
            HStack {
                Button("Settings…") {
                    openSettings()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 340)
        .tint(Theme.ai)
        .onAppear {
            permissionManager.checkAll()
            showRequiredWindowIfNeeded()
        }
    }

    // MARK: - Window routing

    private func showRequiredWindowIfNeeded() {
        guard FirstRunView.isNeeded(appState: appState, permissions: permissionManager) else { return }
        let titles = NSApplication.shared.windows.filter(\.isVisible).map(\.title)
        guard !titles.contains(FirstRunView.windowTitle) else { return }
        openWindow(id: FirstRunView.windowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Header

    /// Models downloading in the background (e.g. after a migration): one quiet line each, in the accent tint.
    @ViewBuilder private var downloadLines: some View {
        ForEach(appState.modelDownloads.sorted { $0.key < $1.key }, id: \.key) { id, fraction in
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading \(ModelRegistry.model(id: id)?.displayName ?? id), \(Int((fraction * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.ai)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            KeycapView(state: KeycapView.KeyState(appState.status), level: appState.inputLevel)
            VStack(alignment: .leading, spacing: 2) {
                Text(stateLine)
                    .font(.callout)
                    .foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(modelLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var isError: Bool {
        if case .error = appState.status { return true }
        return false
    }

    private var stateLine: String {
        switch appState.status {
        case .idle: return "Hold Control to talk"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .processing: return "Cleaning up…"
        case .error(let message): return message
        }
    }

    private var modelLine: String {
        let speech = ModelRegistry.model(id: appState.selectedSpeechModelID)?.displayName ?? "No speech model"
        return "\(speech), cleanup \(appState.cleanupEnabled ? "on" : "off")"
    }

    // MARK: - Transcripts

    private var emptyState: some View {
        Text("Hold Control, speak, then let go. The text appears where you're typing.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
    }

    private var historyList: some View {
        let recent = Array(transcriptStore.entries.prefix(20))
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(recent) { entry in
                    TranscriptRowView(entry: entry) { transcriptStore.delete(entry.id) }
                    if entry.id != recent.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TranscriptRowView: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.cleanedText)
                .font(Theme.transcript)
                .lineSpacing(Theme.transcriptLineSpacing)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(copied ? "Copied" : TimeAgo.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(copied ? AnyShapeStyle(Theme.ai) : AnyShapeStyle(.tertiary))
                    .monospacedDigit()
                if hovering {
                    HStack(spacing: 10) {
                        Button(action: copy) { Image(systemName: "doc.on.doc") }
                            .help("Copy")
                        Button(action: onDelete) { Image(systemName: "trash") }
                            .help("Delete")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: copy)
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.cleanedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
