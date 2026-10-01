import XCTest
@testable import Honyaku

final class ModelDownloaderTests: XCTestCase {

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
        // Should complete without throwing
        try await downloader.download(model: noChecksumModel) { _ in }
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
            try await downloader.download(model: model) { _ in }
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
            try await downloader.download(model: model) { _ in }
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
        let folder = FileManager.default.temporaryDirectory.appending(path: "honyaku-downloader-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: folder.appending(path: "model.safetensors"))
        try Data().write(to: folder.appending(path: "config.json"))  // empty: an unfinished file
        let missing = ModelDownloader.missingFiles(["model.safetensors", "config.json", "chat_template.jinja"], in: folder)
        XCTAssertEqual(missing, ["config.json", "chat_template.jinja"])
    }

    func testRepairDownloadsOnlyTheMissingFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "honyaku-downloader-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
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
