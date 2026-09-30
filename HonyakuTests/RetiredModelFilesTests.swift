import XCTest
@testable import Honyaku

final class RetiredModelFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "honyaku-retired-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ path: String) throws {
        let dir = root.appending(path: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_000).write(to: dir.appending(path: "weights.bin"))
    }

    func testListsOnlyKnownRetiredFoldersThatExist() throws {
        try makeFolder("cleanup/qwen-3b-mlx")
        try makeFolder("cleanup/qwen3-1.7b")          // current model: must not be listed
        try makeFolder("cleanup/network_test_ABC")    // test leftovers: must not be listed
        try makeFolder("whisper/openai_whisper-small.en")

        let items = RetiredModelFiles.onDisk(cleanup: root.appending(path: "cleanup"),
                                             whisper: root.appending(path: "whisper"))

        XCTAssertEqual(Set(items.map(\.name)), ["Qwen 2.5 3B", "Whisper Small (English)"])
        XCTAssertTrue(items.allSatisfy { $0.bytes > 0 })
    }

    func testNothingRetiredOnDisk() throws {
        try makeFolder("cleanup/qwen3-4b-2507")
        XCTAssertTrue(RetiredModelFiles.onDisk(cleanup: root.appending(path: "cleanup"),
                                               whisper: root.appending(path: "whisper")).isEmpty)
    }
}
