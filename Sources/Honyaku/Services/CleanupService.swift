import Foundation
import MLXLLM
import MLXLMCommon

enum CleanupError: Error {
    case timedOut
    case modelNotLoaded
}

actor CleanupService: CleanupServiceProtocol {
    private var loadedModelID: String?
    private var container: ModelContainer?
    private let timeoutSeconds: Double = 60

    static let defaultPrompt = """
    You are a transcript cleaner. Your ONLY job is to clean up the following speech transcript.
    Rules:
    - Remove filler words: um, uh, like, you know, sort of, kind of, basically, literally, right, so
    - Remove false starts and self-corrections (e.g., "I was — I mean I went")
    - Fix run-on sentences into clean prose
    - Preserve ALL [Speaker N] labels exactly as they appear — do not remove or reformat them
    - Output ONLY the cleaned text, nothing else — no explanations, no preamble
    """

    func clean(_ rawText: String, prompt: String) async throws -> String {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rawText
        }
        let model = try await loadModel()

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                // Create a fresh session per call so history doesn't accumulate
                let session = ChatSession(model, instructions: prompt,
                                          generateParameters: .init(temperature: 0.0))
                let response = try await session.respond(to: rawText)
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? rawText : trimmed
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeoutSeconds))
                throw CleanupError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func loadModel() async throws -> ModelContainer {
        let modelID = UserDefaults.standard.string(forKey: "selectedCleanupModelID") ?? ModelRegistry.defaultCleanupModelID
        if let existing = container, loadedModelID == modelID { return existing }
        guard let info = ModelRegistry.model(id: modelID) else { throw CleanupError.modelNotLoaded }

        let modelDir = ModelStore.shared.modelDirectory(for: info)
        guard FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path) else {
            throw CleanupError.modelNotLoaded
        }

        let loaded = try await loadModelContainer(directory: modelDir)
        container = loaded
        loadedModelID = modelID
        return loaded
    }
}
