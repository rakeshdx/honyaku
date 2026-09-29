import SwiftUI
import ServiceManagement
import ApplicationServices

@main
struct HonyakuApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var transcriptStore = TranscriptStore()
    @State private var appState = AppState()

    private let hotkeyService = HotkeyService()
    private let singleInstanceService = SingleInstanceService()
    // Pipeline is created once setup is complete; nil until then.
    @State private var pipeline: TranscriptionPipeline?

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appState)
                .environmentObject(permissionManager)
                .environmentObject(transcriptStore)
                // Retry for when Accessibility was granted after launch
                .onAppear { startPipelineIfReady() }
                .onChange(of: appState.setupComplete) { _, done in
                    if done { startPipelineIfReady() }
                }
        } label: {
            // The label renders at launch (the popover only on click), so push-to-talk works without opening it
            Image(systemName: menuBarIcon)
                .task { startPipelineIfReady() }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(appState)
                .environmentObject(transcriptStore)
                .environmentObject(permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 480)

        WindowGroup("Welcome to Honyaku", id: "onboarding") {
            OnboardingBridge()
                .environmentObject(permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 400)

        WindowGroup("Set Up Honyaku", id: "setup") {
            SetupWizardView()
                .environment(appState)
                .environmentObject(permissionManager)
                .environmentObject(transcriptStore)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 520)
    }

    private var menuBarIcon: String {
        switch appState.status {
        case .recording:   return "waveform.circle.fill"
        case .transcribing, .processing: return "ellipsis.circle"
        case .error:       return "exclamationmark.circle"
        default:           return "waveform"
        }
    }

    init() {
        // Register default values so UserDefaults.bool(forKey:) returns correct defaults
        // before the user has ever opened Settings. Must run before AppState is initialized.
        UserDefaults.standard.register(defaults: [
            "cleanupEnabled": true,
            "selectedSpeechModelID": ModelRegistry.defaultSpeechModelID,
            "selectedCleanupModelID": ModelRegistry.defaultCleanupModelID,
            "diarizationEnabled": false,
        ])

        // Newest instance wins: quit any older copies before this one installs its event tap
        singleInstanceService.start()

        // Clean up any orphaned temp audio files from a previous crash
        TranscriptionService.cleanupOrphanedTempFiles()

        // Register launch-at-login on first run
        registerLoginItemIfNeeded()

        // Register app-quit handler for cleanup
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                HonyakuApp.performQuitCleanup()
            }
        }
    }

    // MARK: - Pipeline + hotkey wiring

    @MainActor
    private func startPipelineIfReady() {
        guard appState.setupComplete else { return }
        // Unit tests are hosted in the app; a test run must not add a second Control listener or load models
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // Create the pipeline once
        if pipeline == nil {
            let p = TranscriptionPipeline(appState: appState, transcriptStore: transcriptStore)
            pipeline = p
            hotkeyService.onRecordingStarted = { p.startRecording() }
            hotkeyService.onRecordingEnded   = { p.stopRecordingAndProcess() }
            hotkeyService.onRecordingCancelled = { p.cancelRecording() }
            hotkeyService.setPipelineBusyCheck { appState.status.isBusy }
            p.warmUp()
        }

        // Attempt to start the hotkey tap — retry on every popover open in case
        // accessibility was granted after the previous attempt (requires relaunch in practice)
        guard !AXIsProcessTrusted() else {
            Task {
                // Never install a second tap while an older instance still holds one
                await singleInstanceService.waitUntilResolved()
                do {
                    try hotkeyService.start()
                    appState.clearError()
                } catch {
                    appState.setError("Hotkey registration failed: \(error.localizedDescription). Try relaunching.")
                }
            }
            return
        }
        appState.setError("Accessibility not granted — open System Settings → Privacy & Security → Accessibility, add Honyaku, then relaunch.")
    }

    // MARK: - Login item

    private func registerLoginItemIfNeeded() {
        #if DEBUG
        // Debug builds run from DerivedData; never make them launch at login
        #else
        guard !UserDefaults.standard.bool(forKey: "loginItemRegistered") else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemRegistered")
        } catch {
            // Non-fatal; user can enable manually in Settings
        }
        #endif
    }

    // MARK: - Quit cleanup (P1-E / privacy spec)

    @MainActor
    static func performQuitCleanup() {
        // Clear pasteboard if it still holds a Honyaku transcript
        NSPasteboard.general.clearContents()
        // Temp files cleaned at launch; also clean on quit for extra safety
        TranscriptionService.cleanupOrphanedTempFiles()
    }
}
