import XCTest
@testable import Honyaku

/// The visible background downloads, against a temporary model folder and a fake install step: never the
/// user's models folder, settings or network.
@MainActor
final class ModelDownloadsTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var suiteName: String!
    private var appState: AppState!
    private let model = ModelInfo(id: "downloads-test", type: .cleanup, engine: .mlx, displayName: "Test Model",
                                  hfRepoPath: "test/repo", fileNames: [], sizeMB: 1, tier: "test", notes: "",
                                  sha256Checksums: [:])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "honyaku-downloads-test-\(UUID())")
        folder = root.appending(path: "model")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Weights, config and tokenizer, but no chat template
        for name in ["config.json", "tokenizer.json", "model.safetensors"] {
            try Data("x".utf8).write(to: folder.appending(path: name))
        }
        try Data("{}".utf8).write(to: folder.appending(path: "tokenizer_config.json"))
        suiteName = "HonyakuModelDownloadsTests.\(UUID().uuidString)"
        appState = AppState(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDownloads(_ step: @escaping ModelInstaller.InstallStep) -> ModelDownloads {
        let folder = folder!
        return ModelDownloads(appState: appState, installer: ModelInstaller(installStep: step),
                              folder: { _ in folder }, installedCheck: { _ in ModelInstaller.isMLXComplete(at: folder) })
    }

    private func waitUntilIdle(_ downloads: ModelDownloads) async throws {
        for _ in 0..<200 where downloads.isRunning(model) { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(downloads.isRunning(model))
    }

    func testRepairFetchesTheTemplateAndCallsBack() async throws {
        let folder = folder!
        let downloads = makeDownloads { _, _, progress in
            try Data("{{ messages }}".utf8).write(to: folder.appending(path: "chat_template.jinja"))
            progress(1)
        }
        let repaired = expectation(description: "repaired")
        downloads.repairChatTemplateIfNeeded(model) { repaired.fulfill() }
        await fulfillment(of: [repaired], timeout: 2)

        XCTAssertTrue(ModelInstaller.isMLXComplete(at: folder))
        XCTAssertTrue(appState.modelDownloads.isEmpty)
        XCTAssertNil(appState.lastError)
    }

    func testRepairDoesNothingWhenTheTemplateIsThere() throws {
        try Data("{{ messages }}".utf8).write(to: folder.appending(path: "chat_template.jinja"))
        let installs = Counter()
        let downloads = makeDownloads { _, _, _ in installs.increment() }
        downloads.repairChatTemplateIfNeeded(model) { XCTFail("Nothing to repair") }
        XCTAssertFalse(downloads.isRunning(model))
        XCTAssertEqual(installs.value, 0)
    }

    func testARepoWithoutATemplateIsReportedOnceAndNotRetried() async throws {
        let attempts = Counter()
        let downloads = makeDownloads { model, _, _ in
            attempts.increment()
            throw ModelDownloadError.noChatTemplate(model.displayName)
        }
        downloads.repairChatTemplateIfNeeded(model) { XCTFail("The repair can't succeed") }
        try await waitUntilIdle(downloads)

        let message = "Test Model has no chat template, so Honyaku can't use it for cleanup. Choose another model in Settings > Models."
        XCTAssertEqual(appState.lastError, message)
        XCTAssertEqual(downloads.cleanupSkippedNotice(for: model), message)

        // Neither a dictation nor Settings retries it during this launch
        downloads.startDownload(model)
        XCTAssertFalse(downloads.isRunning(model))
        XCTAssertEqual(attempts.value, 1)
    }

    func testAFailedDownloadKeepsTheConnectionMessage() async throws {
        let downloads = makeDownloads { _, _, _ in
            throw ModelDownloadError.downloadFailed(URLError(.notConnectedToInternet))
        }
        downloads.startDownload(model)
        try await waitUntilIdle(downloads)
        XCTAssertTrue(appState.lastError?.hasPrefix("Couldn't download Test Model:") == true)
        XCTAssertEqual(downloads.cleanupSkippedNotice(for: model), "Cleanup is off until Test Model finishes downloading.")
    }
}

/// A count shared with an install step, which runs off the main actor.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
