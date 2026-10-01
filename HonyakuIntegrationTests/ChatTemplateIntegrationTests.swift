import XCTest
@testable import Honyaku

/// Qwen3-4B keeps its chat template in `chat_template.jinja`, which older installs never fetched. Links the
/// installed model's files into a temporary folder, lets the real downloader fetch what's missing there, and
/// checks the prompt is built with the template. Requires INTEGRATION_TESTS=1 and network access. Reads the
/// real models folder; never writes to it.
final class ChatTemplateIntegrationTests: IntegrationTestBase {
    private var folder: URL!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "honyaku-chat-template-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        try await super.tearDown()
    }

    func testQwen3_4BPromptUsesTheChatTemplate() async throws {
        let model = try XCTUnwrap(ModelRegistry.model(id: "qwen3-4b-2507"))
        let installed = ModelStore.shared.modelDirectory(for: model)
        guard ModelInstaller.hasMLXWeights(at: installed) else {
            throw XCTSkip("Qwen3-4B isn't installed; download it in Settings > Models")
        }
        let before = try contents(of: installed)
        try linkFiles(from: installed)

        if !ModelInstaller.hasChatTemplate(at: folder) {
            // Today's install: no chat prompt can be built, so mlx-swift-lm falls back to plain text
            do {
                _ = try await prompt()
                XCTFail("Without a template there is no chat prompt")
            } catch {}
            XCTAssertTrue(ModelInstaller.needsChatTemplateOnly(at: folder))
        }

        try await ModelDownloader().download(model: model, to: folder) { _ in }

        XCTAssertTrue(ModelInstaller.hasChatTemplate(at: folder), "The repair must fetch the chat template")
        XCTAssertTrue(ModelInstaller.isMLXComplete(at: folder))
        let prompt = try await prompt()
        XCTAssertTrue(prompt.contains("<|im_start|>system\nClean up the transcript."), prompt)
        XCTAssertTrue(prompt.contains("<|im_start|>user\num hello there<|im_end|>"), prompt)
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"), "The assistant turn must be opened: \(prompt)")

        XCTAssertEqual(try contents(of: installed), before, "The real model folder must not change")
        if !ModelInstaller.hasChatTemplate(at: installed) {
            print("Note: the installed Qwen3-4B still lacks its chat template; Honyaku fetches it on next launch.")
        }
    }

    private func prompt() async throws -> String {
        try await CleanupService.chatPromptText(modelDirectory: folder, system: "Clean up the transcript.",
                                                user: "um hello there")
    }

    /// Hard links: no copies of the 2 GB weights, and the downloader only ever replaces the link, never
    /// the installed file.
    private func linkFiles(from source: URL) throws {
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appending(path: name), to = folder.appending(path: name)
            do { try fm.linkItem(at: from, to: to) } catch { try fm.copyItem(at: from, to: to) }
        }
    }

    private func contents(of folder: URL) throws -> [String: Int] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: folder.path).reduce(into: [:]) { result, name in
            result[name] = (try? folder.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        }
    }
}
