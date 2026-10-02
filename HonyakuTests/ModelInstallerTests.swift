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
        try writeTokenizerConfig(chatTemplate: "{{ messages }}")
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
        try writeTokenizerConfig(chatTemplate: "{{ messages }}")
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root))
        try write("model.safetensors")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    func testMLXWithoutTokenizerIsIncomplete() throws {
        try write("config.json")
        try write("model.safetensors")
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root), "A download interrupted before the tokenizer can't load")
    }

    // MARK: MLX chat template

    func testMLXWithoutChatTemplateIsNotInstalled() throws {
        try makeMLXWeights()
        try writeTokenizerConfig(chatTemplate: nil)
        XCTAssertFalse(ModelInstaller.isMLXComplete(at: root), "Without a template the prompt falls back to plain text")
        XCTAssertTrue(ModelInstaller.needsChatTemplateOnly(at: root))
    }

    func testChatTemplateInTokenizerConfigCounts() throws {
        // Qwen3-1.7B keeps its template inside tokenizer_config.json
        try makeMLXWeights()
        try writeTokenizerConfig(chatTemplate: "{%- for message in messages %}{{ message.content }}{%- endfor %}")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
        XCTAssertFalse(ModelInstaller.needsChatTemplateOnly(at: root))
    }

    func testChatTemplateJinjaFileCounts() throws {
        // Qwen3-4B-Instruct-2507 keeps it in a separate chat_template.jinja
        try makeMLXWeights()
        try writeTokenizerConfig(chatTemplate: nil)
        try write("chat_template.jinja")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: root))
    }

    func testChatTemplateJSONFileCounts() throws {
        try makeMLXWeights()
        try write("chat_template.json")
        XCTAssertTrue(ModelInstaller.hasChatTemplate(at: root))
    }

    func testEmptyTemplatesDontCount() throws {
        try makeMLXWeights()
        try writeTokenizerConfig(chatTemplate: "")
        try Data().write(to: root.appending(path: "chat_template.jinja"))
        XCTAssertFalse(ModelInstaller.hasChatTemplate(at: root), "An empty entry or an empty file is no template")
    }

    func testNamedTemplatesCount() throws {
        try makeMLXWeights()
        let config: [String: Any] = ["chat_template": [["name": "default", "template": "{{ messages }}"]]]
        try JSONSerialization.data(withJSONObject: config).write(to: root.appending(path: "tokenizer_config.json"))
        XCTAssertTrue(ModelInstaller.hasChatTemplate(at: root))
    }

    func testMissingWeightsIsNotATemplateOnlyRepair() throws {
        try write("config.json")
        try write("tokenizer.json")
        XCTAssertFalse(ModelInstaller.needsChatTemplateOnly(at: root), "A model without weights needs a full download")
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

    func testJoinerReceivesProgress() async throws {
        let installer = ModelInstaller { _, _, progress in
            try await Task.sleep(for: .milliseconds(150))
            progress(0.5)
            try await Task.sleep(for: .milliseconds(150))
            progress(1)
        }
        let model = try XCTUnwrap(ModelRegistry.model(id: "qwen3-1.7b"))
        let first = ProgressRecorder(), second = ProgressRecorder()
        async let a: Void = installer.install(model) { first.record($0) }
        async let b: Void = installer.install(model) { second.record($0) }
        _ = try await (a, b)
        XCTAssertEqual(first.values.last, 1)
        XCTAssertEqual(second.values.last, 1, "A caller that joined an install must see its progress too")
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

    func testDeletingAModelWithAnEmptyVariantIsRefused() throws {
        // Asks only which folder a delete would remove, against temporary bases: never the real models
        let bad = ModelInfo(id: "bad-whisper", type: .speech, engine: .whisperKit, displayName: "Bad",
                            hfRepoPath: "argmaxinc/whisperkit-coreml", fileNames: [], sizeMB: 1, tier: "x", notes: "",
                            sha256Checksums: [:], whisperVariant: "")
        XCTAssertThrowsError(try ModelInstaller.deletionFolder(for: bad, modelsBase: root, documents: root),
                             "An empty variant names the whole WhisperKit folder and must be refused")
    }

    func testDeletionFoldersStayInsideTheModelsOwnFolder() throws {
        let cleanup = try XCTUnwrap(ModelRegistry.model(id: "qwen3-1.7b"))
        XCTAssertEqual(try ModelInstaller.deletionFolder(for: cleanup, modelsBase: root, documents: root),
                       root.appendingPathComponent("cleanup/qwen3-1.7b", isDirectory: true))
        let whisper = try XCTUnwrap(ModelRegistry.speechModels.first { $0.engine == .whisperKit })
        let folder = try XCTUnwrap(try ModelInstaller.deletionFolder(for: whisper, modelsBase: root, documents: root))
        XCTAssertTrue(folder.path.hasPrefix(root.appending(path: "huggingface/models").path))
        XCTAssertNotEqual(folder.lastPathComponent, "whisperkit-coreml", "Never the whole WhisperKit folder")
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

    private func makeMLXWeights() throws {
        try write("config.json")
        try write("tokenizer.json")
        try write("model.safetensors")
    }

    /// A `tokenizer_config.json`, with a `chat_template` entry only when one is given.
    private func writeTokenizerConfig(chatTemplate: String?) throws {
        var config: [String: Any] = ["tokenizer_class": "Qwen2Tokenizer"]
        if let chatTemplate { config["chat_template"] = chatTemplate }
        try JSONSerialization.data(withJSONObject: config).write(to: root.appending(path: "tokenizer_config.json"))
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

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []

    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
    var values: [Double] { lock.withLock { recorded } }
}
