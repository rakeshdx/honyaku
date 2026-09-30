import AppKit
import SwiftUI

/// Shows the floating recording capsule while a dictation is in progress. The panel never becomes key,
/// never activates Honyaku and ignores the mouse, so the app being dictated into keeps focus.
@MainActor
final class RecordingCapsuleController {
    private let appState: AppState
    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// A quick tap is over before this, so it never flashes the capsule.
    private let showDelay: Duration = .milliseconds(250)
    private let errorDuration: Duration = .milliseconds(1500)

    init(appState: AppState) {
        self.appState = appState
    }

    func update(for status: AppStatus) {
        switch status {
        case .recording:
            hideTask?.cancel()
            guard panel?.isVisible != true else { return }
            showTask?.cancel()
            showTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: showDelay)
                guard !Task.isCancelled, self.appState.status == .recording else { return }
                self.show()
            }
        case .transcribing, .processing:
            // Stays up (content switches to "Transcribing…") only if it was already showing
            hideTask?.cancel()
        case .error:
            showTask?.cancel()
            guard panel?.isVisible == true else { return }
            hide(after: errorDuration)
        case .idle:
            showTask?.cancel()
            hide(after: .zero)
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        }
    }

    private func hide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let panel = self.panel, panel.isVisible else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                     completionHandler: { panel.orderOut(nil) })
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: RecordingCapsuleView().environment(appState))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    /// Bottom centre of the screen with the pointer, clear of the Dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame, let content = panel.contentView else { return }
        let size = content.fittingSize
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height),
                       display: true)
    }
}

struct RecordingCapsuleView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            KeycapView(state: KeycapView.KeyState(appState.status), level: appState.inputLevel, size: 26)
            switch appState.status {
            case .recording:
                LevelMeter(level: appState.inputLevel)
                ElapsedTime(since: appState.recordingStartedAt)
            case .error(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .frame(maxWidth: 280, alignment: .leading)
            default:
                Text("Transcribing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frame(minWidth: 200, alignment: .leading)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .tint(Theme.ai)
    }
}

/// Twelve bars that follow the voice: each new level enters on the right.
private struct LevelMeter: View {
    let level: Double
    @State private var history = Array(repeating: 0.0, count: 12)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Static bar: no moving parts
                Capsule().fill(Theme.live.opacity(0.2))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Theme.live).frame(width: geo.size.width * level)
                        }
                    }
                    .frame(width: 84, height: 6)
            } else {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(history.indices, id: \.self) { index in
                        Capsule()
                            .fill(Theme.live.opacity(0.35 + 0.65 * history[index]))
                            .frame(width: 4, height: 4 + 16 * history[index])
                    }
                }
                .frame(height: 20)
                .animation(.linear(duration: 0.08), value: history)
            }
        }
        .onChange(of: level) { _, new in
            history.removeFirst()
            history.append(new)
        }
        .accessibilityHidden(true)
    }
}

private struct ElapsedTime: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Text(Self.format(context.date.timeIntervalSince(since ?? context.date)))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
