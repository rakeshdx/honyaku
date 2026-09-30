import AppKit

/// Keeps a single Honyaku process running: a newly launched instance quits any
/// older ones ("newest wins"), so two event taps never listen for Control at once.
@MainActor
final class SingleInstanceService {
    private let provider: RunningInstanceProviding
    private let bundleIdentifier: String
    private let currentPID: pid_t
    private let currentLaunchDate: Date?
    private let timeout: Duration
    private let pollInterval: Duration
    private let isEnabled: Bool
    private var resolution: Task<Void, Never>?

    init(
        provider: RunningInstanceProviding = WorkspaceInstanceProvider(),
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.honyaku.app",
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        currentLaunchDate: Date? = NSRunningApplication.current.launchDate,
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(100),
        // Unit tests are hosted in the app; a test run must not quit the developer's running copy
        isEnabled: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    ) {
        self.provider = provider
        self.bundleIdentifier = bundleIdentifier
        self.currentPID = currentPID
        self.currentLaunchDate = currentLaunchDate
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.isEnabled = isEnabled
    }

    /// Begins quitting older instances. Safe to call repeatedly — the work runs once.
    @discardableResult
    func start() -> Task<Void, Never> {
        if let resolution { return resolution }
        let task = Task { await terminateOlderInstances() }
        resolution = task
        return task
    }

    /// Returns once no older instance is left running.
    func waitUntilResolved() async {
        await start().value
    }

    private func terminateOlderInstances() async {
        guard isEnabled else { return }
        let older = provider.runningInstances(bundleIdentifier: bundleIdentifier).filter(isOlder)
        guard !older.isEmpty else { return }

        // Graceful quit first so the older copy runs its normal quit cleanup
        older.forEach { $0.terminate() }

        let deadline = ContinuousClock.now + timeout
        while older.contains(where: { !$0.isTerminated }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
        older.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    private func isOlder(_ instance: RunningInstance) -> Bool {
        guard instance.processIdentifier != currentPID else { return false }
        // Unknown dates count as older so a stray copy is never left holding the hotkey
        guard let mine = currentLaunchDate, let theirs = instance.launchDate else { return true }
        // Same launch instant: lower PID loses, so exactly one survives
        return theirs < mine || (theirs == mine && instance.processIdentifier < currentPID)
    }
}

struct WorkspaceInstanceProvider: RunningInstanceProviding {
    func runningInstances(bundleIdentifier: String) -> [RunningInstance] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }
}

extension NSRunningApplication: RunningInstance {}
