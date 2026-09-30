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
        // FluidAudio strips "-coreml" from the repo name when it picks its download folder
        XCTAssertEqual(ModelInstaller.parakeetFolder(base: root).lastPathComponent, "parakeet-tdt-0.6b-v2")
    }

    // MARK: MLX

    func testMLXWithAllIndexedShardsIsComplete() throws {
        try write("config.json")
        try write("tokenizer.json")
        try write("model-00001-of-00002.safetensors")
        try write("model-00002-of-00002.safetensors")
        try writeIndex(["a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"])
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    func testMLXMissingShardIsIncomplete() throws {
        try write("config.json")
        try write("tokenizer.json")
        try write("model-00001-of-00002.safetensors")
        try writeIndex(["a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"])
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root), "config.json alone must not count as installed")
    }

    func testSingleFileMLXModel() throws {
        try write("config.json")
        try write("tokenizer.json")
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root))
        try write("model.safetensors")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    func testMLXWithoutTokenizerIsIncomplete() throws {
        try write("config.json")
        try write("model.safetensors")
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root), "A download interrupted before the tokenizer can't load")
    }

    // MARK: Single-flight and delete safety

    func testConcurrentInstallsOfOneModelRunOnce() async throws {
        let counter = InstallCounter()
        let installer = ModelInstaller { _, _, _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(200))
        }
        let model = try XCTUnwrap(ModelRegistry.model(id: "qwen3-1.7b"))
        async let first: Void = installer.install(model) { _ in }
        async let second: Void = installer.install(model) { _ in }
        _ = try await (first, second)
        let runs = await counter.count
        XCTAssertEqual(runs, 1, "The second install must wait for the first, not start its own")
    }

    func testSequentialInstallsRunAgain() async throws {
        let counter = InstallCounter()
        let installer = ModelInstaller { _, _, _ in await counter.increment() }
        let model = try XCTUnwrap(ModelRegistry.model(id: "qwen3-1.7b"))
        try await installer.install(model) { _ in }
        try await installer.install(model) { _ in }
        let runs = await counter.count
        XCTAssertEqual(runs, 2)
    }

    func testUnsafePathPartsAreRejected() {
        XCTAssertTrue(ModelInstaller.isSafePathPart("argmaxinc/whisperkit-coreml"))
        XCTAssertTrue(ModelInstaller.isSafePathPart("openai_whisper-large-v3-v20240930_626MB"))
        for bad in ["", "/", "..", "a/../b", "a//b", "/abs", "./x"] {
            XCTAssertFalse(ModelInstaller.isSafePathPart(bad), bad)
        }
    }

    func testDeletingAModelWithAnEmptyVariantIsRefused() async throws {
        let bad = ModelInfo(id: "bad-whisper", type: .speech, engine: .whisperKit, displayName: "Bad",
                            hfRepoPath: "argmaxinc/whisperkit-coreml", fileNames: [], sizeMB: 1, tier: "x", notes: "",
                            sha256Checksums: [:], whisperVariant: "")
        do {
            try await ModelInstaller().delete(bad)
            XCTFail("An empty variant names the whole WhisperKit folder and must be refused")
        } catch {}
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

private actor InstallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
