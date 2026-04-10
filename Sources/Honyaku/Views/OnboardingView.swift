import SwiftUI

/// Bridge view that has access to openWindow so it can chain onboarding → setup wizard.
struct OnboardingBridge: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var permissionManager: PermissionManager

    var body: some View {
        OnboardingView {
            NSApplication.shared.keyWindow?.close()
            openWindow(id: "setup")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    var onComplete: () -> Void

    @State private var accessibilityAttempted = false

    private func bringOnboardingToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first { $0.title == "Welcome to Honyaku" }?
            .orderFrontRegardless()
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to Honyaku")
                .font(.title2.bold())

            Text("Before you start, Honyaku needs two permissions. Everything stays on your Mac — nothing is sent anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            VStack(spacing: 12) {
                // Microphone
                PermissionRowView(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "To capture your speech while you hold Control.",
                    isGranted: permissionManager.microphoneGranted,
                    action: {
                        Task { await permissionManager.requestMicrophone() }
                    },
                    settingsAction: permissionManager.openMicrophoneSettings
                )

                // Accessibility
                if permissionManager.accessibilityGranted {
                    PermissionRowView(
                        icon: "lock.shield",
                        title: "Accessibility",
                        description: "Granted.",
                        isGranted: true,
                        action: {},
                        settingsAction: permissionManager.openAccessibilitySettings
                    )
                } else if accessibilityAttempted {
                    // User already went to System Settings — need a restart
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restart Required").font(.callout.bold())
                            Text("macOS requires Honyaku to restart after granting Accessibility. Quit and relaunch — permission will be remembered.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Quit & Relaunch") {
                            NSApplication.shared.relaunch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    PermissionRowView(
                        icon: "lock.shield",
                        title: "Accessibility",
                        description: "Required to register the global hotkey and paste text.",
                        isGranted: false,
                        action: {
                            accessibilityAttempted = true
                            permissionManager.requestAccessibility()
                        },
                        settingsAction: permissionManager.openAccessibilitySettings
                    )
                }
            }

            Button("Continue") { onComplete() }
                .buttonStyle(.borderedProminent)
                .disabled(!permissionManager.microphoneGranted)
        }
        .padding(32)
        .frame(width: 440)
        .onAppear { permissionManager.checkAll() }
        .onChange(of: permissionManager.microphoneGranted) { _, granted in
            if granted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { bringOnboardingToFront() }
            }
        }
        .onChange(of: permissionManager.accessibilityGranted) { _, granted in
            if granted { bringOnboardingToFront() }
        }
        .task {
            while !permissionManager.allGranted {
                try? await Task.sleep(for: .seconds(1))
                permissionManager.checkAll()
            }
        }
    }
}

extension NSApplication {
    func relaunch() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [Bundle.main.bundlePath]
        task.launch()
        terminate(nil)
    }
}

struct PermissionRowView: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
