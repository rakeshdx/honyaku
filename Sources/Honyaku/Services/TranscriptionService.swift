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
    private var loading: (modelID: String, allowsFetch: Bool, task: Task<WhisperKit, Error>)?
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
                let fullText = TranscriptionService.assembleText(
                    windowTexts: segments.map(\.text), segmentTexts: whisperSegments.map(\.text)
                )
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

    /// Loads the speech model ahead of the first dictation (launch warm-up). Local only: skipped unless the
    /// model and its tokenizer are on disk, and never falls back to a fetch, so launch makes no network call.
    func prepareIfDownloaded(modelID: String) async throws {
        guard let info = ModelRegistry.model(id: modelID), let variant = info.whisperVariant,
              TranscriptionService.isModelDownloaded(at: TranscriptionService.localModelFolder(repo: info.hfRepoPath, variant: variant)),
              TranscriptionService.isTokenizerDownloaded(variant: variant)
        else { return }
        _ = try await loadWhisperKit(modelID: modelID, allowFetch: false)
    }

    private func loadWhisperKit(modelID: String, allowFetch: Bool = true) async throws -> WhisperKit {
        if let kit = whisperKit, loadedModelID == modelID { return kit }
        if let loading, loading.modelID == modelID {
            do {
                return try await loading.task.value
            } catch where allowFetch && !loading.allowsFetch {
                // Warm-up's local-only load failed; a dictation may still fetch the model
            }
        }
        guard let info = ModelRegistry.model(id: modelID),
              let variant = info.whisperVariant else { throw TranscriptionError.modelNotLoaded }

        let task = Task {
            try await TranscriptionService.makeWhisperKit(repo: info.hfRepoPath, variant: variant, allowFetch: allowFetch)
        }
        loading = (modelID, allowFetch, task)
        defer { if loading?.task == task { loading = nil } }  // only clear our own load
        let kit = try await task.value
        whisperKit = kit
        loadedModelID = modelID
        return kit
    }

    private static func makeWhisperKit(repo: String, variant: String, allowFetch: Bool) async throws -> WhisperKit {
        let folder = localModelFolder(repo: repo, variant: variant)
        if isModelDownloaded(at: folder) {
            do {
                // On disk: load it directly. download: true would send a metadata request per model file.
                return try await WhisperKit(WhisperKitConfig(
                    model: variant, modelRepo: repo, modelFolder: folder.path, download: false
                ))
            } catch {
                // An unloadable local copy counts as missing; the error type is logged, never transcript data
                log.error("Local speech model failed to load (\(String(describing: type(of: error)), privacy: .public))")
                guard allowFetch else { throw error }
            }
        }
        guard allowFetch else { throw TranscriptionError.modelNotLoaded }
        // Missing or unreadable: let WhisperKit fetch it from Hugging Face.
        return try await WhisperKit(model: variant, modelRepo: repo)
    }

    /// Where `WhisperKit.download` stores a model: the Hugging Face Hub default,
    /// `~/Documents/huggingface/models/<repo>/<variant>`.
    static func localModelFolder(repo: String, variant: String,
                                 documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) -> URL {
        documents.appending(path: "huggingface/models").appending(path: repo).appending(path: variant)
    }

    /// WhisperKit loads the tokenizer from `<documents>/huggingface/models/openai/whisper-<size>/tokenizer.json`
    /// ("openai_whisper-tiny.en" → "openai/whisper-tiny.en"), fetching it on first load if missing.
    static func isTokenizerDownloaded(variant: String,
                                      documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) -> Bool {
        guard variant.hasPrefix("openai_") else { return false }
        let name = "openai/" + variant.dropFirst("openai_".count)
        let file = documents.appending(path: "huggingface/models").appending(path: name).appending(path: "tokenizer.json")
        return FileManager.default.fileExists(atPath: file.path)
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

    /// Transcript text from WhisperKit's window text — which keeps the original spacing, so scripts without
    /// spaces aren't split — with non-speech annotations removed, including segments that are only a
    /// parenthesised annotation such as "(clears throat)".
    static func assembleText(windowTexts: [String], segmentTexts: [String]) -> String {
        var text = windowTexts.map(stripTokens).joined(separator: " ")
        for segment in segmentTexts.map(stripTokens)
        where segment.range(of: #"^\([^)]*\)$"#, options: .regularExpression) != nil {
            if let range = text.range(of: segment) { text.removeSubrange(range) }
        }
        return stripNonSpeech(text)
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
