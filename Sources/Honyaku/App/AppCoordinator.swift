import AppKit
import SwiftUI
import ServiceManagement
import ApplicationServices

/// Owns the delegate for the SwiftUI app. SwiftUI's `MenuBarExtra` can't run an action on click, and
/// on macOS 14 its `Settings` scene can only be opened from inside SwiftUI views, so the menu bar icon
/// and both windows are AppKit, driven from here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.launch()
    }
}

/// Holds the app's long-lived state and wiring: what `HonyakuApp` held when it had a menu bar popover.
@MainActor
final class AppCoordinator {
    let appState: AppState
    let permissionManager = PermissionManager()
    let transcriptStore = TranscriptStore()

    private let hotkeyService = HotkeyService()
    private let singleInstanceService = SingleInstanceService()
    // Pipeline is created once setup is complete; nil until then.
    private var pipeline: TranscriptionPipeline?
    private var capsule: RecordingCapsuleController?
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(coordinator: self)
    private lazy var firstRunWindow = HostedWindow(title: FirstRunView.windowTitle, freshContentOnReopen: true) { [unowned self] in
        // A closed first run starts over at its first incomplete step when reopened
        AnyView(withSharedState(FirstRunView()))
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
        appState = AppState()
    }

    static var isHostingTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    // MARK: - Launch

    func launch() {
        // Newest instance wins: quit any older copies before this one installs its event tap
        singleInstanceService.start()
        // Clean up any orphaned temp audio files from a previous crash
        TranscriptionService.cleanupOrphanedTempFiles()
        registerLoginItemIfNeeded()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppCoordinator.performQuitCleanup() }
        }

        // Unit tests are hosted in the app: no menu bar icon, capsule, Control listener or model loads
        guard !Self.isHostingTests else { return }

        statusItem = StatusItemController(
            onOpen: { [unowned self] in openFromMenuBar() },
            onSettings: { [unowned self] in showSettings() }
        )
        capsule = RecordingCapsuleController(appState: appState)
        observeState()
        permissionManager.checkAll()
        startPipelineIfReady()
        if FirstRunView.isNeeded(appState: appState, permissions: permissionManager) {
            firstRunWindow.show()
        }
    }

    // MARK: - Windows

    /// A click on the icon opens Settings, or first run while setup isn't finished.
    private func openFromMenuBar() {
        permissionManager.checkAll()
        // Retry for when Accessibility was granted after launch
        startPipelineIfReady()
        if FirstRunView.isNeeded(appState: appState, permissions: permissionManager) {
            firstRunWindow.show()
        } else {
            showSettings()
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    // MARK: - State

    /// Follows the status (menu bar symbol, capsule) and setup completion for as long as the app runs.
    private func observeState() {
        withObservationTracking {
            _ = appState.status
            _ = appState.setupComplete
        } onChange: { [weak self] in
            // onChange fires before the new value is set, so read it on the next main-actor turn
            Task { @MainActor in
                guard let self else { return }
                self.stateChanged()
                self.observeState()
            }
        }
        stateChanged()
    }

    private func stateChanged() {
        statusItem?.setSymbol(StatusItemController.symbol(for: appState.status))
        capsule?.update(for: appState.status)
        if appState.setupComplete, pipeline == nil { startPipelineIfReady() }
    }

    // MARK: - Pipeline + hotkey wiring

    private func startPipelineIfReady() {
        guard appState.setupComplete else { return }
        // Unit tests are hosted in the app; a test run must not add a second Control listener or load models
        guard !Self.isHostingTests else { return }

        // Create the pipeline once
        if pipeline == nil {
            let p = TranscriptionPipeline(appState: appState, transcriptStore: transcriptStore)
            pipeline = p
            hotkeyService.onRecordingStarted = { p.startRecording() }
            hotkeyService.onRecordingEnded   = { p.stopRecordingAndProcess() }
            hotkeyService.onRecordingCancelled = { p.cancelRecording() }
            let appState = appState
            hotkeyService.setPipelineBusyCheck { appState.status.isBusy }
            p.warmUp()
        }

        // Attempt to start the hotkey tap — retried on every icon click in case
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

    static func performQuitCleanup() {
        // Clear pasteboard if it still holds a Honyaku transcript
        NSPasteboard.general.clearContents()
        // Temp files cleaned at launch; also clean on quit for extra safety
        TranscriptionService.cleanupOrphanedTempFiles()
    }

    /// Wraps a tab or window's SwiftUI content with the shared state it reads.
    func withSharedState<V: View>(_ view: V) -> some View {
        view.environment(appState)
            .environmentObject(permissionManager)
            .environmentObject(transcriptStore)
            .tint(Theme.ai)
    }
}
