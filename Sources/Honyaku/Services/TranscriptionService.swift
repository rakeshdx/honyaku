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
    private var engine: (any SpeechEngine)?
    // In-flight load, so a launch warm-up and a dictation never load the model twice
    private var loading: (modelID: String, allowsFetch: Bool, task: Task<any SpeechEngine, Error>)?
    private let timeoutSeconds: Double = 15
    private static let log = Logger(subsystem: "com.honyaku.app", category: "transcription")

    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, samples16k: nil, modelID: modelID)
    }

    /// `samples16k` is the same audio as 16 kHz mono floats, which Parakeet uses directly.
    func transcribe(audioURL: URL, samples16k: [Float]?, modelID: String) async throws -> TranscriptionResult {
        defer { Self.deleteTempFile(audioURL) }

        let engine = try await loadEngine(modelID: modelID)

        return try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            group.addTask {
                try await engine.transcribe(audioURL: audioURL, samples16k: samples16k)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeoutSeconds))
                throw TranscriptionError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private

    /// Loads the speech model ahead of the first dictation (launch warm-up). Local only: skipped unless the
    /// model (and, for Whisper, its tokenizer) is on disk, and never falls back to a fetch, so launch makes
    /// no network call.
    func prepareIfDownloaded(modelID: String) async throws {
        guard let info = ModelRegistry.model(id: modelID), ModelInstaller.isInstalled(info) else { return }
        _ = try await loadEngine(modelID: modelID, allowFetch: false)
    }

    private func loadEngine(modelID: String, allowFetch: Bool = true) async throws -> any SpeechEngine {
        if let engine, loadedModelID == modelID { return engine }
        if let loading, loading.modelID == modelID {
            do {
                return try await loading.task.value
            } catch where allowFetch && !loading.allowsFetch {
                // Warm-up's local-only load failed; a dictation may still fetch the model
            }
        }
        guard let info = ModelRegistry.model(id: modelID), info.type == .speech else {
            throw TranscriptionError.modelNotLoaded
        }

        let task = Task { try await TranscriptionService.makeEngine(for: info, allowFetch: allowFetch) }
        loading = (modelID, allowFetch, task)
        defer { if loading?.task == task { loading = nil } }  // only clear our own load
        let loaded = try await task.value
        engine = loaded
        loadedModelID = modelID
        return loaded
    }

    private static func makeEngine(for info: ModelInfo, allowFetch: Bool) async throws -> any SpeechEngine {
        switch info.engine {
        case .parakeet:
            let folder = ModelInstaller.parakeetFolder()
            if !ModelInstaller.isParakeetComplete(at: folder) {
                guard allowFetch else { throw TranscriptionError.modelNotLoaded }
                // Missing or partial: fetch it (and compile it) first
                try await ModelInstaller.shared.install(info) { _ in }
            }
            do {
                return try await ParakeetEngine.load(from: folder)
            } catch {
                // An unloadable local copy counts as missing, as for Whisper; warm-up never re-fetches
                log.error("Local speech model failed to load (\(String(describing: type(of: error)), privacy: .public))")
                guard allowFetch else { throw error }
                try await ModelInstaller.shared.install(info, force: true) { _ in }
                return try await ParakeetEngine.load(from: folder)
            }
        case .whisperKit:
            guard let variant = info.whisperVariant else { throw TranscriptionError.modelNotLoaded }
            return WhisperKitEngine(kit: try await makeWhisperKit(repo: info.hfRepoPath, variant: variant,
                                                                 allowFetch: allowFetch))
        case .mlx, .speakerKit:
            throw TranscriptionError.modelNotLoaded
        }
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
        guard let name = tokenizerName(forVariant: variant) else { return false }
        let file = documents.appending(path: "huggingface/models").appending(path: name).appending(path: "tokenizer.json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// The tokenizer repo WhisperKit uses for a variant: the base model name, without the size or build
    /// suffix after "_" or a "-vYYYYMMDD" date stamp ("openai_whisper-large-v3-v20240930_626MB" → "openai/whisper-large-v3").
    static func tokenizerName(forVariant variant: String) -> String? {
        guard variant.hasPrefix("openai_") else { return nil }
        let model = variant.dropFirst("openai_".count).split(separator: "_").first.map(String.init) ?? ""
        let base = model.replacingOccurrences(of: #"-v\d{8}$"#, with: "", options: .regularExpression)
        return base.isEmpty ? nil : "openai/" + base
    }

    /// True when every compiled model WhisperKit needs is complete; an interrupted download fails this.
    static func isModelDownloaded(at folder: URL) -> Bool {
        ["AudioEncoder", "TextDecoder", "MelSpectrogram"].allSatisfy { name in
            let marker = folder.appending(path: "\(name).mlmodelc/coremldata.bin")
            return FileManager.default.fileExists(atPath: marker.path)
        }
    }

    /// Decoding options for a clip.
    /// - Language: a chosen language code is passed through with detection off, so a short phrase can't be
    ///   mistaken for another language. With `nil`, detection is on: WhisperKit's defaults would start every
    ///   decode with `<|en|>`, making a multilingual model translate Japanese or Italian into English instead
    ///   of transcribing it. English-only models skip detection themselves.
    /// - End trim: WhisperKit only decodes while more than `windowClipTime` (default 1 s) remains, so a clip
    ///   of 1 s or less would be skipped. The trim also stops a trailing sliver after the last timestamp
    ///   being decoded alone (where Whisper invents "Thank you."), so it's only shrunk for clips too short
    ///   to decode, to just under the clip length.
    static func decodeOptions(forDurationSeconds duration: Double?, language: String? = nil) -> DecodingOptions {
        var options = DecodingOptions()
        options.language = language
        options.detectLanguage = language == nil
        if let duration, duration < 1.1 {
            options.windowClipTime = Float(max(0, duration - 0.1))
        }
        return options
    }

    /// UserDefaults key for the multilingual model's dictation language: a Whisper language code, or absent for Auto-detect.
    static let dictationLanguageKey = "dictationLanguage"

    /// The languages Whisper supports, by display name, one entry per code (the table has aliases).
    static let dictationLanguages: [(name: String, code: String)] = {
        var seen = Set<String>()
        var result: [(name: String, code: String)] = []
        let byName: [(key: String, value: String)] = Constants.languages.sorted { $0.key < $1.key }
        for (name, code) in byName where seen.insert(code).inserted {
            result.append((name: name.capitalized, code: code))
        }
        return result
    }()

    /// Transcript text from WhisperKit's window text — which keeps the original spacing, so scripts without
    /// spaces aren't split — with non-speech annotations removed, including segments that are only a
    /// parenthesised annotation such as "(clears throat)".
    static func assembleText(windowTexts: [String], segmentTexts: [String]) -> String {
        var text = windowTexts.map(stripTokens).joined(separator: " ")
        for segment in segmentTexts.map(stripTokens)
        where segment.range(of: annotationOnly, options: .regularExpression) != nil {
            if let range = text.range(of: segment) { text.removeSubrange(range) }
        }
        return stripNonSpeech(text)
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
        if collapsed.range(of: annotationOnly, options: .regularExpression) != nil { return "" }
        return collapsed
    }

    /// Text that is only a sound description, like "(silence)" or "*thud*". Only whole segments go:
    /// parentheses and asterisks inside real speech ("I *really* mean it") stay.
    private static let annotationOnly = #"^(\([^)]*\)|\*[^*]*\*)$"#

    static func deleteTempFile(_ url: URL) {
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
