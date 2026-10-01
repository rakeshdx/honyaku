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
    let transcriptStore: TranscriptStore
    /// Where features keep their settings; shared by the pipeline and the Settings tabs.
    let features: FeatureEnvironment

    private let hotkeyService = HotkeyService()
    private let singleInstanceService = SingleInstanceService()
    // Pipeline is created once setup is complete; nil until then.
    private var pipeline: TranscriptionPipeline?
    private var capsule: RecordingCapsuleController?
    private var statusItem: StatusItemController?
    /// The right-click menu's "Rewrite as" submenu.
    private lazy var rewriteMenu = RewriteMenu(settings: features.store(RewriteSettings.self))
    private lazy var settingsWindow = SettingsWindowController(coordinator: self)
    private lazy var firstRunWindow = HostedWindow(
        title: FirstRunView.windowTitle, freshContentOnReopen: true,
        // However the window closes, a Try it test ends with it, so later dictations paste as usual
        onClose: { [unowned self] in appState.endFirstRunTest() }
    ) { [unowned self] in
        // A closed first run starts over at its first incomplete step when reopened
        AnyView(withSharedState(FirstRunView()))
    }
    /// The last error `startPipelineIfReady` reported, so it clears only its own error once fixed.
    private var listenerError: String?

    init() {
        // Register default values so UserDefaults.bool(forKey:) returns correct defaults
        // before the user has ever opened Settings. Must run before AppState is initialized.
        UserDefaults.standard.register(defaults: [
            "cleanupEnabled": true,
            "selectedSpeechModelID": ModelRegistry.defaultSpeechModelID,
            "selectedCleanupModelID": ModelRegistry.defaultCleanupModelID,
            "diarizationEnabled": false,
        ])
        if Self.isHostingTests || Self.isUITesting {
            // Tests never touch the user's data: history in memory, settings in a separate suite wiped at
            // launch, feature files in a temporary folder
            let defaults = UserDefaults(suiteName: Self.testSettingsSuite) ?? .standard
            defaults.removePersistentDomain(forName: Self.testSettingsSuite)
            appState = AppState(defaults: defaults)
            transcriptStore = TranscriptStore(inMemory: [])
            features = FeatureEnvironment(
                directory: FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)"),
                defaults: defaults)
        } else {
            appState = AppState()
            transcriptStore = TranscriptStore()
            features = .live()
        }
    }

    /// Settings for the test host and UI-test launches; never the user's `com.honyaku.app`.
    static let testSettingsSuite = "com.honyaku.app.tests"

    static var isHostingTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// UI tests launch with `-HonyakuUITestSetupComplete YES`: setup counts as done for this launch only, and
    /// the app shows its menu bar icon and windows without the Control listener, capsule or models.
    static var isUITesting: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HonyakuUITestSetupComplete")
        #else
        false
        #endif
    }

    // MARK: - Launch

    func launch() {
        if Self.isUITesting {
            // No single-instance takeover: a copy the developer is running keeps running
            statusItem = StatusItemController(onOpen: { [unowned self] in showSettings() },
                                              onSettings: { [unowned self] in showSettings() },
                                              extraItems: [rewriteMenu.item])
            return
        }
        // Newest instance wins: quit any older copies before this one installs its event tap
        singleInstanceService.start()
        // Unit tests are hosted in the app: no menu bar icon, capsule, Control listener or model loads, and no
        // temp-file or quit cleanup, which could reach a dictation in the user's running copy
        guard !Self.isHostingTests else { return }

        // Clean up any orphaned temp audio files from a previous crash
        TranscriptionService.cleanupOrphanedTempFiles()
        registerLoginItemIfNeeded()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppCoordinator.performQuitCleanup() }
        }

        statusItem = StatusItemController(
            onOpen: { [unowned self] in openFromMenuBar() },
            onSettings: { [unowned self] in showSettings() },
            extraItems: [rewriteMenu.item]
        )
        capsule = RecordingCapsuleController(appState: appState)
        permissionManager.checkAll()
        // Applies the current state once, which starts the pipeline if setup is complete
        observeState()
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
    /// Each call applies the current state once and re-registers for the next change.
    private func observeState() {
        withObservationTracking {
            _ = appState.status
            _ = appState.setupComplete
            _ = appState.rewriteTemplate
        } onChange: { [weak self] in
            // onChange fires before the new value is set, so read it on the next main-actor turn
            Task { @MainActor in self?.observeState() }
        }
        stateChanged()
    }

    private func stateChanged() {
        // A rewrite's label lasts while its hold or run does
        if !appState.status.isBusy, appState.rewriteTemplate != nil { appState.rewriteTemplate = nil }
        statusItem?.update(for: appState.status, rewriting: appState.rewriteTemplate != nil)
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
            let p = TranscriptionPipeline(appState: appState, transcriptStore: transcriptStore,
                                          stages: .live(features))
            pipeline = p
            hotkeyService.onRecordingStarted = { [unowned self] mode in
                p.startRecording(mode: mode)
                if mode == .rewrite { showRewriteTemplate() }
            }
            hotkeyService.onRewriteHint = { [unowned self] in showRewriteTemplate() }
            hotkeyService.onRecordingEnded   = { mode in _ = p.stopRecordingAndProcess(mode: mode) }
            hotkeyService.onRecordingCancelled = { p.cancelRecording() }
            let appState = appState
            hotkeyService.setPipelineBusyCheck { appState.status.isBusy }
            p.warmUp()
        }

        // Attempt to start the hotkey tap — retried on every icon click in case
        // accessibility was granted after the previous attempt
        guard !AXIsProcessTrusted() else {
            Task {
                // Never install a second tap while an older instance still holds one
                await singleInstanceService.waitUntilResolved()
                do {
                    try hotkeyService.start()
                    // Only the listener's own error is cleared; any other error stays for the user to read
                    if let listenerError, appState.lastError == listenerError { appState.clearError() }
                    listenerError = nil
                } catch {
                    reportListenerError("Honyaku couldn't listen for the Control key: \(error.localizedDescription) Quit and reopen Honyaku to try again.")
                }
            }
            return
        }
        reportListenerError("Honyaku needs Accessibility to hear the Control key. Turn it on in System Settings → Privacy & Security → Accessibility, then click the menu bar icon.")
    }

    /// Names the template on the capsule as soon as a hold becomes a rewrite: the same choice the pipeline
    /// makes when it ends, for the app the recording started in.
    private func showRewriteTemplate() {
        guard appState.status == .recording, let pipeline else { return }
        appState.rewriteTemplate = features.store(RewriteSettings.self)
            .resolvedTemplate(forAppAtStart: pipeline.recordingAppAtStart)
    }

    private func reportListenerError(_ message: String) {
        listenerError = message
        appState.setError(message)
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
            .environment(features)
            .environmentObject(permissionManager)
            .environmentObject(transcriptStore)
            .tint(Theme.ai)
    }
}
