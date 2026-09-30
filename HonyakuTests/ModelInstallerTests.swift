import XCTest
@testable import Honyaku

final class ModelInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "honyaku-installer-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Parakeet

    func testCompleteParakeetFolder() throws {
        try makeParakeet(skipping: nil)
        XCTAssertTrue(ModelInstaller.isParakeetComplete(at: root))
    }

    func testParakeetMissingWeightsIsIncomplete() throws {
        try makeParakeet(skipping: "Encoder.mlmodelc/weights/weight.bin")
        XCTAssertFalse(ModelInstaller.isParakeetComplete(at: root))
    }

    func testParakeetWithPartialFileIsIncomplete() throws {
        try makeParakeet(skipping: nil)
        try write("Encoder.mlmodelc/weights/weight.bin.partial")
        XCTAssertFalse(ModelInstaller.isParakeetComplete(at: root))
    }

    func testParakeetFolderIsNamedForFluidAudio() {
        XCTAssertEqual(ModelInstaller.parakeetFolder(base: root).lastPathComponent, "parakeet-tdt-0.6b-v2-coreml")
    }

    // MARK: MLX

    func testMLXWithAllIndexedShardsIsComplete() throws {
        try write("config.json")
        try write("model-00001-of-00002.safetensors")
        try write("model-00002-of-00002.safetensors")
        try writeIndex(["a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"])
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    func testMLXMissingShardIsIncomplete() throws {
        try write("config.json")
        try write("model-00001-of-00002.safetensors")
        try writeIndex(["a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"])
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root), "config.json alone must not count as installed")
    }

    func testSingleFileMLXModel() throws {
        try write("config.json")
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root))
        try write("model.safetensors")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    // MARK: - Helpers

    private func makeParakeet(skipping skipped: String?) throws {
        let parts = ["coremldata.bin", "model.mil", "metadata.json", "weights/weight.bin"]
        for bundle in ["Preprocessor", "Encoder", "Decoder", "JointDecision"] {
            for part in parts where "\(bundle).mlmodelc/\(part)" != skipped {
                try write("\(bundle).mlmodelc/\(part)")
            }
        }
        try write("parakeet_vocab.json")
    }

    private func write(_ relativePath: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func writeIndex(_ weightMap: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["weight_map": weightMap])
        try data.write(to: root.appending(path: "model.safetensors.index.json"))
    }
}
