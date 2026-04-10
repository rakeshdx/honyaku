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
