import AVFoundation
import Foundation
import os
import WhisperKit

enum TranscriptionError: Error {
    case timedOut
    case modelNotLoaded
    case emptyResult
}

actor TranscriptionService: ASRService {
    private var loadedModelID: String?
    private var whisperKit: WhisperKit?
    // In-flight load, so a launch warm-up and a dictation never load the model twice
    private var loading: (modelID: String, task: Task<WhisperKit, Error>)?
    private let store = ModelStore.shared
    private let timeoutSeconds: Double = 15
    private static let log = Logger(subsystem: "com.honyaku.app", category: "transcription")

    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult {
        defer { deleteTempFile(audioURL) }

        let kit = try await loadWhisperKit(modelID: modelID)
        let options = TranscriptionService.decodeOptions(forDurationSeconds: Self.duration(of: audioURL))

        let result = try await withThrowingTaskGroup(of: [TranscriptionResult].self) { group in
            group.addTask {
                let segments = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
                guard !segments.isEmpty, let first = segments.first else {
                    throw TranscriptionError.emptyResult
                }
                let whisperSegments = segments.flatMap { $0.segments }
                let duration = whisperSegments.last.map { Double($0.end) } ?? 0
                let timed = whisperSegments.map {
                    TimedSegment(startSeconds: Double($0.start), endSeconds: Double($0.end),
                                 text: TranscriptionService.stripNonSpeech(TranscriptionService.stripTokens($0.text)))
                }
                // Built from cleaned segments so a segment that is only "(clears throat)" drops out mid-transcript
                let fullText = whisperSegments.isEmpty
                    ? TranscriptionService.assembleText(segments.map(\.text))
                    : TranscriptionService.assembleText(whisperSegments.map(\.text))
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

    /// Loads the speech model ahead of the first dictation (launch warm-up) — only if it is already on
    /// disk, so warm-up never starts a download. A missing model is fetched by the first dictation.
    func prepareIfDownloaded(modelID: String) async throws {
        guard let info = ModelRegistry.model(id: modelID), let variant = info.whisperVariant,
              TranscriptionService.isModelDownloaded(at: TranscriptionService.localModelFolder(repo: info.hfRepoPath, variant: variant))
        else { return }
        _ = try await loadWhisperKit(modelID: modelID)
    }

    private func loadWhisperKit(modelID: String) async throws -> WhisperKit {
        if let kit = whisperKit, loadedModelID == modelID { return kit }
        if let loading, loading.modelID == modelID { return try await loading.task.value }
        guard let info = ModelRegistry.model(id: modelID),
              let variant = info.whisperVariant else { throw TranscriptionError.modelNotLoaded }

        let task = Task { try await TranscriptionService.makeWhisperKit(repo: info.hfRepoPath, variant: variant) }
        loading = (modelID, task)
        defer { if loading?.modelID == modelID { loading = nil } }
        let kit = try await task.value
        whisperKit = kit
        loadedModelID = modelID
        return kit
    }

    private static func makeWhisperKit(repo: String, variant: String) async throws -> WhisperKit {
        let folder = localModelFolder(repo: repo, variant: variant)
        if isModelDownloaded(at: folder) {
            do {
                // On disk: load it directly. download: true would send a metadata request per model file.
                return try await WhisperKit(WhisperKitConfig(
                    model: variant, modelRepo: repo, modelFolder: folder.path, download: false
                ))
            } catch {
                // An unloadable local copy counts as missing; the error type is logged, never transcript data
                log.error("Local speech model failed to load (\(String(describing: type(of: error)), privacy: .public)); fetching it")
            }
        }
        // Missing or unreadable: let WhisperKit fetch it from Hugging Face.
        return try await WhisperKit(model: variant, modelRepo: repo)
    }

    /// Where `WhisperKit.download` stores a model: the Hugging Face Hub default,
    /// `~/Documents/huggingface/models/<repo>/<variant>`.
    static func localModelFolder(repo: String, variant: String,
                                 documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) -> URL {
        documents.appending(path: "huggingface/models").appending(path: repo).appending(path: variant)
    }

    /// True when every compiled model WhisperKit needs is complete; an interrupted download fails this.
    static func isModelDownloaded(at folder: URL) -> Bool {
        ["AudioEncoder", "TextDecoder", "MelSpectrogram"].allSatisfy { name in
            let marker = folder.appending(path: "\(name).mlmodelc/coremldata.bin")
            return FileManager.default.fileExists(atPath: marker.path)
        }
    }

    /// WhisperKit only decodes while more than `windowClipTime` (default 1 s) remains, so a clip of 1 s
    /// or less is skipped entirely. The trim also stops a trailing sliver after the last timestamp being
    /// decoded on its own (where Whisper invents "Thank you."), so it is only shrunk for clips too short to
    /// decode at all, and kept just under the clip length so that sliver still can't be decoded alone.
    static func decodeOptions(forDurationSeconds duration: Double?) -> DecodingOptions? {
        guard let duration, duration < 1.1 else { return nil }
        return DecodingOptions(windowClipTime: Float(max(0, duration - 0.1)))
    }

    /// Joins segment texts after removing special tokens and non-speech annotations from each.
    static func assembleText(_ segmentTexts: [String]) -> String {
        segmentTexts
            .map { stripNonSpeech(stripTokens($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Remove WhisperKit special tokens like <|startoftranscript|>, <|0.00|>, <|en|>, etc.
    static func stripTokens(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: " ", options: .regularExpression)
        return stripped.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Remove Whisper's non-speech annotations such as [BLANK_AUDIO], [MUSIC] or a bare (silence),
    /// so silence is discarded instead of pasted. Dictated words never come back in square brackets;
    /// parentheses only go when they are the whole text, since they can appear in real speech.
    static func stripNonSpeech(_ text: String) -> String {
        let unbracketed = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let collapsed = unbracketed.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if collapsed.range(of: #"^\([^)]*\)$"#, options: .regularExpression) != nil { return "" }
        return collapsed
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
