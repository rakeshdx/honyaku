import XCTest
@testable import Honyaku

@MainActor
final class SingleInstanceServiceTests: XCTestCase {
    private let now = Date()
    private let currentPID: pid_t = 500

    func testNoOtherInstancesIsNoOp() async {
        let me = FakeInstance(pid: currentPID, launchDate: now)
        await makeService([me]).waitUntilResolved()
        XCTAssertEqual(me.terminateCalls, 0, "Current process must never be terminated")
        XCTAssertEqual(me.forceTerminateCalls, 0)
    }

    func testOlderInstanceTerminatedGracefully() async {
        let older = FakeInstance(pid: 100, launchDate: now.addingTimeInterval(-60), exitsOnTerminate: true)
        let me = FakeInstance(pid: currentPID, launchDate: now)
        await makeService([older, me]).waitUntilResolved()
        XCTAssertEqual(older.terminateCalls, 1)
        XCTAssertEqual(older.forceTerminateCalls, 0, "Graceful quit succeeded; no force needed")
        XCTAssertEqual(me.terminateCalls, 0)
    }

    func testForceTerminatesAfterTimeout() async {
        let stuck = FakeInstance(pid: 100, launchDate: now.addingTimeInterval(-60), exitsOnTerminate: false)
        await makeService([stuck]).waitUntilResolved()
        XCTAssertEqual(stuck.terminateCalls, 1)
        XCTAssertEqual(stuck.forceTerminateCalls, 1, "Instance ignoring quit must be force-terminated")
    }

    func testNewerInstanceLeftRunning() async {
        let newer = FakeInstance(pid: 900, launchDate: now.addingTimeInterval(60))
        await makeService([newer]).waitUntilResolved()
        XCTAssertEqual(newer.terminateCalls, 0, "Newest wins — a newer copy must not be quit")
    }

    func testDisabledDoesNothing() async {
        let older = FakeInstance(pid: 100, launchDate: now.addingTimeInterval(-60))
        await makeService([older], isEnabled: false).waitUntilResolved()
        XCTAssertEqual(older.terminateCalls, 0)
    }

    // MARK: - Helpers

    private func makeService(_ instances: [FakeInstance], isEnabled: Bool = true) -> SingleInstanceService {
        SingleInstanceService(
            provider: FakeProvider(instances: instances),
            bundleIdentifier: "com.honyaku.app",
            currentPID: currentPID,
            currentLaunchDate: now,
            timeout: .milliseconds(200),
            pollInterval: .milliseconds(10),
            isEnabled: isEnabled
        )
    }
}

private final class FakeInstance: RunningInstance {
    let processIdentifier: pid_t
    let launchDate: Date?
    private let exitsOnTerminate: Bool
    private(set) var isTerminated = false
    private(set) var terminateCalls = 0
    private(set) var forceTerminateCalls = 0

    init(pid: pid_t, launchDate: Date?, exitsOnTerminate: Bool = true) {
        self.processIdentifier = pid
        self.launchDate = launchDate
        self.exitsOnTerminate = exitsOnTerminate
    }

    func terminate() -> Bool {
        terminateCalls += 1
        if exitsOnTerminate { isTerminated = true }
        return true
    }

    func forceTerminate() -> Bool {
        forceTerminateCalls += 1
        isTerminated = true
        return true
    }
}

private struct FakeProvider: RunningInstanceProviding {
    let instances: [FakeInstance]
    func runningInstances(bundleIdentifier: String) -> [RunningInstance] { instances }
}
