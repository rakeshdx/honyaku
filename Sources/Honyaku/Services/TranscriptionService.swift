import Foundation
import WhisperKit

enum TranscriptionError: Error {
    case timedOut
    case modelNotLoaded
    case emptyResult
}

actor TranscriptionService: ASRService {
    private var loadedModelID: String?
    private var whisperKit: WhisperKit?
    private let store = ModelStore.shared
    private let timeoutSeconds: Double = 15

    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult {
        defer { deleteTempFile(audioURL) }

        let kit = try await loadWhisperKit(modelID: modelID)

        let result = try await withThrowingTaskGroup(of: [TranscriptionResult].self) { group in
            group.addTask {
                let segments = try await kit.transcribe(audioPath: audioURL.path)
                guard !segments.isEmpty, let first = segments.first else {
                    throw TranscriptionError.emptyResult
                }
                let whisperSegments = segments.flatMap { $0.segments }
                let duration = whisperSegments.last.map { Double($0.end) } ?? 0
                let fullText = TranscriptionService.stripTokens(segments.map(\.text).joined(separator: " "))
                let timed = whisperSegments.map {
                    TimedSegment(startSeconds: Double($0.start), endSeconds: Double($0.end),
                                 text: TranscriptionService.stripTokens($0.text))
                }
                return [TranscriptionResult(
                    rawText: fullText,
                    language: first.language,
                    durationSeconds: duration,
                    timedSegments: timed
                )]
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeoutSeconds))
                throw TranscriptionError.timedOut
            }
            let results = try await group.next()!
            group.cancelAll()
            return results
        }
        return result[0]
    }

    // MARK: - Private

    private func loadWhisperKit(modelID: String) async throws -> WhisperKit {
        if let kit = whisperKit, loadedModelID == modelID { return kit }
        guard let info = ModelRegistry.model(id: modelID),
              let variant = info.whisperVariant else { throw TranscriptionError.modelNotLoaded }
        // WhisperKit manages its own model cache; passing the variant re-uses a previously
        // downloaded model or downloads it on first use.
        let kit = try await WhisperKit(model: variant, modelRepo: info.hfRepoPath)
        whisperKit = kit
        loadedModelID = modelID
        return kit
    }

    /// Remove WhisperKit special tokens like <|startoftranscript|>, <|0.00|>, <|en|>, etc.
    static func stripTokens(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: " ", options: .regularExpression)
        return stripped.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func deleteTempFile(_ url: URL) {
        guard url.path.hasPrefix(NSTemporaryDirectory()),
              url.lastPathComponent.hasPrefix("honyaku_") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Launch-time temp file cleanup

    static func cleanupOrphanedTempFiles() {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("honyaku_") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
