import SwiftUI

/// First run in one window: permissions, then models, then a live test dictation.
struct FirstRunView: View {
    enum Step: Int, CaseIterable {
        case permissions, models, tryIt

        var title: String {
            switch self {
            case .permissions: return "Permissions"
            case .models: return "Models"
            case .tryIt: return "Try it"
            }
        }
    }

    static let windowTitle = "Set up Honyaku"

    /// First run is needed while a permission is missing or models haven't been set up.
    @MainActor
    static func isNeeded(appState: AppState, permissions: PermissionManager) -> Bool {
        isNeeded(setupComplete: appState.setupComplete, microphoneGranted: permissions.microphoneGranted,
                 accessibilityGranted: permissions.accessibilityGranted)
    }

    static func isNeeded(setupComplete: Bool, microphoneGranted: Bool, accessibilityGranted: Bool) -> Bool {
        !microphoneGranted || !accessibilityGranted || !setupComplete
    }

    /// Resumes at the first incomplete step. A missing permission always comes first, even when models
    /// were set up before (Accessibility can be turned off later).
    static func firstIncompleteStep(setupComplete: Bool, microphoneGranted: Bool, accessibilityGranted: Bool) -> Step {
        if !microphoneGranted || !accessibilityGranted { return .permissions }
        if !setupComplete { return .models }
        return .tryIt
    }

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var step: Step
    @State private var didPickInitialStep = false

    /// Pass a step to open on it; otherwise first run resumes at the first incomplete step.
    init(initialStep: Step? = nil) {
        _step = State(initialValue: initialStep ?? .permissions)
        _didPickInitialStep = State(initialValue: initialStep != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(current: step)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 18)
            Divider()

            Group {
                switch step {
                case .permissions: PermissionsStep(onContinue: { step = .models })
                case .models: ModelsStep(onBack: { step = .permissions }, onDone: { step = .tryIt })
                case .tryIt: TryItStep(onFinish: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 520, height: 560)
        .tint(Theme.ai)
        .onAppear {
            permissionManager.checkAll()
            guard !didPickInitialStep else { return }
            didPickInitialStep = true
            step = Self.firstIncompleteStep(setupComplete: appState.setupComplete,
                                            microphoneGranted: permissionManager.microphoneGranted,
                                            accessibilityGranted: permissionManager.accessibilityGranted)
        }
    }

    private func finish() {
        appState.endFirstRunTest()
        NSApplication.shared.windows.first { $0.title == Self.windowTitle }?.close()
    }
}

// MARK: - Step header

/// First run really is a sequence, so its steps are numbered.
private struct StepHeader: View {
    let current: FirstRunView.Step

    var body: some View {
        HStack(spacing: 18) {
            ForEach(FirstRunView.Step.allCases, id: \.self) { step in
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(step == current ? Theme.aiFill : .clear)
                            .overlay(Circle().strokeBorder(step.rawValue <= current.rawValue ? Theme.ai : Color.secondary.opacity(0.4)))
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ai)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(step == current ? Color.white : .secondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(step.title)
                        .font(.callout.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current.rawValue + 1) of 3, \(current.title)")
    }
}

// MARK: - Shared layout

private struct StepLayout<Content: View, Footer: View>: View {
    let title: String
    let lede: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.title)
                Text(lede)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)
            content
            Spacer(minLength: 16)
            HStack { footer }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }
}

// MARK: - Step 1: permissions

private struct PermissionsStep: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    let onContinue: () -> Void
    @State private var accessibilityAttempted = false

    var body: some View {
        StepLayout(
            title: "Let Honyaku hear you and type for you",
            lede: "Everything stays on your Mac. Audio is processed locally and deleted straight after."
        ) {
            VStack(spacing: 0) {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records only while you hold Control.",
                    granted: permissionManager.microphoneGranted,
                    actionTitle: "Allow",
                    action: { Task { await permissionManager.requestMicrophone() } }
                )
                Divider()
                PermissionRow(
                    title: "Accessibility",
                    detail: accessibilityAttempted
                        ? "Turn Honyaku on in the list. If it's on but still not detected here, relaunch Honyaku."
                        : "Lets Honyaku notice the Control key anywhere and paste the text.",
                    granted: permissionManager.accessibilityGranted,
                    actionTitle: "Open System Settings",
                    action: {
                        accessibilityAttempted = true
                        permissionManager.requestAccessibility()
                    },
                    secondaryTitle: accessibilityAttempted ? "Relaunch" : nil,
                    secondaryAction: { NSApplication.shared.relaunch() }
                )
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.panelRadius))
        } footer: {
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(Theme.aiFill)
                .keyboardShortcut(.defaultAction)
                .disabled(!permissionManager.microphoneGranted)
        }
        .task {
            while !permissionManager.allGranted {
                try? await Task.sleep(for: .seconds(1))
                permissionManager.checkAll()
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(Theme.ai)
            } else {
                if let secondaryTitle { Button(secondaryTitle, action: secondaryAction) }
                Button(actionTitle, action: action)
            }
        }
        .padding(14)
    }
}

// MARK: - Step 2: models

private struct ModelsStep: View {
    @Environment(AppState.self) private var appState
    let onBack: () -> Void
    let onDone: () -> Void

    private static let recommendation = ModelRegistry.recommended(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
    @State private var speechID = ModelsStep.recommendation.speech
    @State private var cleanupID = ModelsStep.recommendation.cleanup
    @State private var choosing = false
    @State private var downloading: ModelInfo?
    @State private var progress: Double = 0
    @State private var error: String?

    private var speech: ModelInfo? { ModelRegistry.model(id: speechID) }
    private var cleanup: ModelInfo? { ModelRegistry.model(id: cleanupID) }
    private var totalMB: Int { (speech?.sizeMB ?? 0) + (cleanup?.sizeMB ?? 0) }
    private var memoryGB: Int { Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()) }

    var body: some View {
        StepLayout(
            title: "Download the models",
            lede: "Honyaku downloads them once and then works offline. Nothing you say leaves your Mac."
        ) {
            if choosing {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ModelChoiceList(title: "Speech", models: ModelRegistry.speechModels, selection: $speechID)
                        ModelChoiceList(title: "Cleanup", models: ModelRegistry.cleanupModels, selection: $cleanupID)
                    }
                }
                .frame(maxHeight: 260)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.setupComplete ? "Your models" : "Recommended for this Mac (\(memoryGB) GB)")
                        .font(.callout.weight(.semibold))
                    if let speech { RecommendedRow(model: speech, role: "Turns your voice into text") }
                    if let cleanup { RecommendedRow(model: cleanup, role: "Removes filler words and adds punctuation") }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.panelRadius))
            }

            HStack {
                Button(choosing ? "Use the recommendation" : "Choose models myself") {
                    if choosing {
                        speechID = ModelsStep.recommendation.speech
                        cleanupID = ModelsStep.recommendation.cleanup
                    }
                    choosing.toggle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ai)
                .disabled(downloading != nil)
                Spacer()
                Text("\(ModelCopy.size(mb: totalMB)) in total")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 10)

            if let downloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                    Text("Downloading \(downloading.displayName), \(Int(progress * Double(downloading.sizeMB))) of \(downloading.sizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.top, 14)
            }
            if let error {
                Text("\(error) Check your connection, then try again.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        } footer: {
            Button("Back", action: onBack).disabled(downloading != nil)
            Spacer()
            Button(downloading == nil ? "Download" : "Downloading…", action: download)
                .buttonStyle(.borderedProminent)
                .tint(Theme.aiFill)
                .keyboardShortcut(.defaultAction)
                .disabled(downloading != nil || speech == nil || cleanup == nil)
        }
        .onAppear {
            if appState.setupComplete {
                speechID = appState.selectedSpeechModelID
                cleanupID = appState.selectedCleanupModelID
            }
        }
    }

    private func download() {
        guard let speech, let cleanup else { return }
        error = nil
        Task {
            do {
                // ModelInstaller skips what's already on disk and compiles each model as it lands
                for model in [speech, cleanup] where !ModelInstaller.isInstalled(model) {
                    downloading = model
                    progress = 0
                    try await ModelInstaller.shared.install(model) { p in
                        Task { @MainActor in progress = p }
                    }
                }
                appState.selectedSpeechModelID = speech.id
                appState.selectedCleanupModelID = cleanup.id
                appState.setupComplete = true
                downloading = nil
                onDone()
            } catch {
                self.error = "The download didn't finish."
                downloading = nil
            }
        }
    }
}

private struct RecommendedRow: View {
    let model: ModelInfo
    let role: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                Text(role).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ModelCopy.size(mb: model.sizeMB))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct ModelChoiceList: View {
    let title: String
    let models: [ModelInfo]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.semibold))
            VStack(spacing: 0) {
                ForEach(models) { model in
                    Button { selection = model.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.displayName).foregroundStyle(.primary)
                                Text("\(ModelCopy.summary(for: model)), \(ModelCopy.size(mb: model.sizeMB))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: model.id == selection ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.id == selection ? Theme.ai : Color.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.id == selection ? .isSelected : [])
                    .background(model.id == selection ? Theme.ai.opacity(0.08) : .clear)
                    if model.id != models.last?.id { Divider().padding(.leading, 12) }
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.panelRadius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        }
    }
}

// MARK: - Step 3: try it

private struct TryItStep: View {
    @Environment(AppState.self) private var appState
    let onFinish: () -> Void

    var body: some View {
        StepLayout(
            title: "Try it",
            lede: "Hold Control, say something, then let go. This time the text appears here instead of being pasted."
        ) {
            HStack(alignment: .center, spacing: 16) {
                KeycapView(state: KeycapView.KeyState(appState.status), level: appState.inputLevel, size: 56)
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

            if let transcript = appState.firstRunTestTranscript {
                Text(transcript)
                    .font(Theme.transcript)
                    .lineSpacing(Theme.transcriptLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.panelRadius))
            }
        } footer: {
            Spacer()
            if appState.firstRunTestTranscript == nil {
                Button("Skip for now", action: onFinish)
            } else {
                Button("Start using Honyaku", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.aiFill)
                    .keyboardShortcut(.defaultAction)
            }
        }
        // A new test each time the step shows; closing the window also ends it (AppCoordinator)
        .onAppear { appState.beginFirstRunTest() }
        .onDisappear { appState.endFirstRunTest() }
    }

    private var isError: Bool {
        if case .error = appState.status { return true }
        return false
    }

    private var statusLine: String {
        switch appState.status {
        case .recording: return "Listening…"
        case .transcribing, .processing: return "Transcribing…"
        case .error(let message): return message
        case .idle:
            return appState.firstRunTestTranscript == nil
                ? "Waiting for you to hold Control."
                : "That's it. From now on the text goes wherever you're typing."
        }
    }
}

// MARK: - Model copy

/// Plain-language model descriptions for the UI, independent of the registry's notes.
enum ModelCopy {
    static func summary(for model: ModelInfo) -> String {
        switch model.tier {
        case "recommended": return "Most accurate for English, and fastest"
        case "fast": return "Fastest"
        case "best": return "Most accurate, needs 16 GB of memory"
        case "multilingual": return "99 languages"
        default: return model.notes
        }
    }

    static func size(mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000) : "\(mb) MB"
    }
}

// MARK: - Relaunch

extension NSApplication {
    /// Quits, then starts a fresh instance once this process has fully exited.
    /// A detached shell waits on our PID; `open` while we're still running would
    /// just re-activate this process instead of launching a new one.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$2\"",
            "relaunch",  // $0
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath,
        ]
        guard (try? task.run()) != nil else { return }
        terminate(nil)
    }
}
