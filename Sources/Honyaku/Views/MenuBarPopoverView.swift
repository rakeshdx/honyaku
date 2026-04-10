import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var transcriptStore: TranscriptStore
    @EnvironmentObject private var permissionManager: PermissionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            statusHeader
            Divider()

            // Transcript history list
            if transcriptStore.entries.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()
            // Footer actions
            HStack {
                Button("Settings") {
                    openWindow(id: "settings")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .onAppear {
            permissionManager.checkAll()
            showRequiredWindowIfNeeded()
        }
    }

    // MARK: - Window routing

    private func showRequiredWindowIfNeeded() {
        let titles = NSApplication.shared.windows.filter(\.isVisible).compactMap(\.title)
        let needsOnboarding = !permissionManager.microphoneGranted || !permissionManager.accessibilityGranted
        if needsOnboarding {
            guard !titles.contains("Welcome to Honyaku") else { return }
            openWindow(id: "onboarding")
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else if !appState.setupComplete {
            guard !titles.contains("Set Up Honyaku") else { return }
            openWindow(id: "setup")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Subviews

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: appState.status == .recording)
            Text(statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if !permissionManager.allGranted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Permissions missing — open Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Hold ⌃ Control to start recording")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) {
                    transcriptStore.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear all history")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(transcriptStore.entries.prefix(20)) { entry in
                        TranscriptRowView(entry: entry)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    // MARK: - Helpers

    private var statusIcon: String {
        switch appState.status {
        case .idle:         return "waveform"
        case .recording:    return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .processing:   return "gearshape"
        case .error:        return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .recording:    return .red
        case .error:        return .orange
        default:            return .secondary
        }
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle:                 return "Ready"
        case .recording:            return "Recording…"
        case .transcribing:         return "Transcribing…"
        case .processing:           return "Processing…"
        case .error(let msg):       return msg
        }
    }
}

struct TranscriptRowView: View {
    let entry: TranscriptEntry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.cleanedText)
                    .font(.callout)
                    .lineLimit(2)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cleanedText, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
