import XCTest
@testable import Honyaku

/// Every download goes into a temporary folder: the tests never write to the user's models folder.
final class ModelDownloaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "honyaku-downloader-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSuccessfulDownloadMarksModelDownloaded() async throws {
        let downloader = ModelDownloader(session: makeMockSession(data: Data("fake model".utf8), statusCode: 200))
        let model = ModelRegistry.cleanupModels[0]
        // Remove checksums so verification is skipped
        let noChecksumModel = ModelInfo(
            id: model.id + "_test_\(UUID())",
            type: model.type,
            engine: model.engine,
            displayName: model.displayName,
            hfRepoPath: model.hfRepoPath,
            fileNames: ["test.bin"],
            sizeMB: 1,
            tier: model.tier,
            notes: model.notes,
            sha256Checksums: [:]
        )
        let folder = root.appending(path: noChecksumModel.id)
        try await downloader.download(model: noChecksumModel, to: folder) { _ in }
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "test.bin"), encoding: .utf8), "fake model")
    }

    func testChecksumMismatchThrowsError() async throws {
        let downloader = ModelDownloader(session: makeMockSession(data: Data("corrupt".utf8), statusCode: 200))
        let model = ModelInfo(
            id: "checksum_test_\(UUID())",
            type: .cleanup,
            engine: .mlx,
            displayName: "Test",
            hfRepoPath: "test/repo",
            fileNames: ["test.bin"],
            sizeMB: 1,
            tier: "test",
            notes: "",
            sha256Checksums: ["test.bin": "0000000000000000000000000000000000000000000000000000000000000000"]
        )
        do {
            try await downloader.download(model: model, to: root.appending(path: model.id)) { _ in }
            XCTFail("Expected checksumMismatch error")
        } catch ModelDownloadError.checksumMismatch {
            // Expected
        }
    }

    func testNetworkErrorSurfacesDownloadFailed() async throws {
        let downloader = ModelDownloader(session: makeMockSession(error: URLError(.notConnectedToInternet)))
        let model = ModelInfo(
            id: "network_test_\(UUID())",
            type: .cleanup,
            engine: .mlx,
            displayName: "Test",
            hfRepoPath: "test/repo",
            fileNames: ["test.bin"],
            sizeMB: 1,
            tier: "test",
            notes: "",
            sha256Checksums: [:]
        )
        do {
            try await downloader.download(model: model, to: root.appending(path: model.id)) { _ in }
            XCTFail("Expected downloadFailed error")
        } catch ModelDownloadError.downloadFailed {
            // Expected
        }
    }

    // MARK: - Chat templates and missing files

    func testMLXFileListIncludesTheChatTemplate() {
        // The file list of mlx-community/Qwen3-4B-Instruct-2507-4bit
        let repo = [".gitattributes", "README.md", "added_tokens.json", "chat_template.jinja", "config.json",
                    "generation_config.json", "merges.txt", "model.safetensors", "model.safetensors.index.json",
                    "special_tokens_map.json", "tokenizer.json", "tokenizer_config.json", "vocab.json"]
        let files = ModelDownloader.mlxFiles(in: repo)
        XCTAssertTrue(files.contains("chat_template.jinja"))
        XCTAssertFalse(files.contains("README.md"))
        XCTAssertFalse(files.contains(".gitattributes"))
        XCTAssertEqual(files.count, 11)
    }

    func testOnlyMissingFilesAreFetched() throws {
        let folder = root.appending(path: "model")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: folder.appending(path: "model.safetensors"))
        try Data().write(to: folder.appending(path: "config.json"))  // empty: an unfinished file
        let missing = ModelDownloader.missingFiles(["model.safetensors", "config.json", "chat_template.jinja"], in: folder)
        XCTAssertEqual(missing, ["config.json", "chat_template.jinja"])
    }

    func testRepairDownloadsOnlyTheMissingFile() async throws {
        let folder = root.appending(path: "model")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let weights = Data("existing weights".utf8)
        try weights.write(to: folder.appending(path: "model.safetensors"))

        let downloader = ModelDownloader(session: makeMockSession(data: Data("{{ template }}".utf8), statusCode: 200))
        let model = ModelInfo(id: "repair-test", type: .cleanup, engine: .mlx, displayName: "Test", hfRepoPath: "test/repo",
                              fileNames: ["model.safetensors", "chat_template.jinja"], sizeMB: 1, tier: "test",
                              notes: "", sha256Checksums: [:])
        try await downloader.download(model: model, to: folder) { _ in }

        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "model.safetensors")), weights,
                       "A file already on disk must not be downloaded again")
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "chat_template.jinja"), encoding: .utf8), "{{ template }}")
    }

    // MARK: - Error responses and file names

    func testErrorResponsesLeaveNoFileAndALaterAttemptFetchesIt() async throws {
        let model = ModelInfo(id: "status-test", type: .cleanup, engine: .mlx, displayName: "Test", hfRepoPath: "test/repo",
                              fileNames: ["chat_template.jinja"], sizeMB: 1, tier: "test", notes: "", sha256Checksums: [:])
        let folder = root.appending(path: "model")
        let template = folder.appending(path: "chat_template.jinja")
        for status in [404, 500] {
            let downloader = ModelDownloader(session: makeMockSession(data: Data("Entry not found".utf8), statusCode: status))
            do {
                try await downloader.download(model: model, to: folder) { _ in }
                XCTFail("A \(status) must fail the download")
            } catch ModelDownloadError.downloadFailed {
                // Expected
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: template.path), "A \(status) page must not be saved")
        }

        let downloader = ModelDownloader(session: makeMockSession(data: Data("{{ messages }}".utf8), statusCode: 200))
        try await downloader.download(model: model, to: folder) { _ in }
        XCTAssertEqual(try String(contentsOf: template, encoding: .utf8), "{{ messages }}")
    }

    func testOnlyHTTPSuccessCounts() {
        let url = URL(string: "https://huggingface.co/x")!
        XCTAssertTrue(ModelDownloader.isSuccess(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        XCTAssertFalse(ModelDownloader.isSuccess(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)))
        XCTAssertFalse(ModelDownloader.isSuccess(URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)))
        XCTAssertFalse(ModelDownloader.isSuccess(nil))
    }

    func testUnsafeFileNamesAreNeverDownloaded() async throws {
        XCTAssertEqual(ModelDownloader.safeFileNames(["../x.json", "a/../../b.jinja", "/etc/x.json", "ok.json", "sub/ok.jinja"]),
                       ["ok.json", "sub/ok.jinja"])

        let model = ModelInfo(id: "names-test", type: .cleanup, engine: .mlx, displayName: "Test", hfRepoPath: "test/repo",
                              fileNames: ["../x.json", "a/../../b.jinja", "ok.json"], sizeMB: 1, tier: "test",
                              notes: "", sha256Checksums: [:])
        let folder = root.appending(path: "nested/model")
        let downloader = ModelDownloader(session: makeMockSession(data: Data("{}".utf8), statusCode: 200))
        try await downloader.download(model: model, to: folder) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "ok.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "nested/x.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "nested/b.jinja").path))
    }

    // MARK: - Helpers

    private func makeMockSession(data: Data? = nil, statusCode: Int = 200, error: Error? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.mockData = data
        MockURLProtocol.mockStatusCode = statusCode
        MockURLProtocol.mockError = error
        return URLSession(configuration: config)
    }
}

// MARK: - MockURLProtocol

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockStatusCode: Int = 200
    static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
