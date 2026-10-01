import Foundation

// MARK: - ASR

protocol ASRService: Sendable {
    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult
    func transcribe(audioURL: URL, samples16k: [Float]?, modelID: String, hints: SpeechHints) async throws -> TranscriptionResult
    /// Loads the model ahead of the first dictation if it's on disk; never downloads.
    func prepareIfDownloaded(modelID: String) async throws
}

extension ASRService {
    func transcribe(audioURL: URL, samples16k: [Float]?, modelID: String) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, samples16k: samples16k, modelID: modelID, hints: .none)
    }
}

// MARK: - Audio capture

/// The microphone, for one recording at a time.
protocol AudioCapturing: AnyObject {
    /// Called when the selected microphone is disconnected.
    var onDeviceDisconnected: (() -> Void)? { get set }
    /// 0–1 input level while recording, on the main queue.
    var onLevel: ((Double) -> Void)? { get set }
    func prepare()
    func startCapture() throws
    /// Stops recording and returns the audio as a temporary WAV file and as 16 kHz mono floats.
    func stopCaptureAndFlushBoth() throws -> (url: URL, floatArray: [Float])
    func cancelCapture()
}

// MARK: - Cleanup

protocol CleanupServiceProtocol: Sendable {
    func clean(_ rawText: String, request: CleanupRequest) async throws -> String
    /// `clean`, also saying how generation ended: rewrites use it to spot output cut off at the cap.
    func generate(_ rawText: String, request: CleanupRequest) async throws -> CleanupOutput
    /// Loads the selected model ahead of the first dictation.
    func prepare() async throws
}

extension CleanupServiceProtocol {
    func generate(_ rawText: String, request: CleanupRequest) async throws -> CleanupOutput {
        CleanupOutput(text: try await clean(rawText, request: request))
    }
}

// MARK: - Diarization

protocol DiarizationServiceProtocol: Sendable {
    func diarize(audioArray: [Float]) async throws -> [DiarizedSegment]
}

// MARK: - Hotkey

protocol HotkeyServiceProtocol: AnyObject {
    /// The mode the gesture started in.
    var onRecordingStarted: ((DictationMode) -> Void)? { get set }
    /// The mode the gesture ended in, which wins over the one it started in.
    var onRecordingEnded: ((DictationMode) -> Void)? { get set }
    var onRecordingCancelled: (() -> Void)? { get set }
    /// Shift joined a hold that started as dictation: it will end as a rewrite unless it's cancelled.
    var onRewriteHint: (() -> Void)? { get set }
    func start() throws
    func stop()
}

// MARK: - Paste

protocol PasteServiceProtocol: Sendable {
    func paste(_ text: String) async throws
    /// Clears a transcript left on the pasteboard after an error, after `delay` seconds.
    func clearTranscriptFromPasteboard(after delay: Double) async
}

// MARK: - Models

/// Whether the models a dictation needs are on disk, and the visible download when one isn't.
@MainActor
protocol ModelAvailability {
    func isInstalled(_ model: ModelInfo) -> Bool
    /// Starts downloading `model` in the background unless it's installed or already downloading.
    func startDownload(_ model: ModelInfo)
    /// "Downloading …, 42%. Dictation works once it finishes."
    func downloadMessage(for model: ModelInfo) -> String
    /// Fetches a cleanup model's missing chat template in the background, when that's all it's missing.
    /// `onRepaired` runs on the main actor once the template is in place.
    func repairChatTemplateIfNeeded(_ model: ModelInfo, onRepaired: @escaping @MainActor () -> Void)
    /// Why a dictation's cleanup was skipped because `model` isn't installed yet.
    func cleanupSkippedNotice(for model: ModelInfo) -> String
}

extension ModelAvailability {
    func repairChatTemplateIfNeeded(_ model: ModelInfo, onRepaired: @escaping @MainActor () -> Void) {}
    func cleanupSkippedNotice(for model: ModelInfo) -> String {
        "Cleanup is off until \(model.displayName) finishes downloading."
    }
}

// MARK: - Single instance

/// A running copy of the app. `NSRunningApplication` conforms; tests use fakes.
protocol RunningInstance: AnyObject {
    var processIdentifier: pid_t { get }
    var launchDate: Date? { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

protocol RunningInstanceProviding {
    func runningInstances(bundleIdentifier: String) -> [RunningInstance]
}

// MARK: - Model downloading

protocol ModelDownloading: Sendable {
    func download(model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws
    func isDownloaded(_ model: ModelInfo) -> Bool
    func delete(_ model: ModelInfo) throws
}
