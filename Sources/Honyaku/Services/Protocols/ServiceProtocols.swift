import Foundation

// MARK: - ASR

protocol ASRService: Sendable {
    func transcribe(audioURL: URL, modelID: String) async throws -> TranscriptionResult
}

// MARK: - Cleanup

protocol CleanupServiceProtocol: Sendable {
    func clean(_ rawText: String, prompt: String) async throws -> String
}

// MARK: - Diarization

protocol DiarizationServiceProtocol: Sendable {
    func diarize(audioArray: [Float]) async throws -> [DiarizedSegment]
}

// MARK: - Hotkey

protocol HotkeyServiceProtocol: AnyObject {
    var onRecordingStarted: (() -> Void)? { get set }
    var onRecordingEnded: (() -> Void)? { get set }
    func start() throws
    func stop()
}

// MARK: - Paste

protocol PasteServiceProtocol: Sendable {
    func paste(_ text: String) async throws
}

// MARK: - Model downloading

protocol ModelDownloading: Sendable {
    func download(model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws
    func isDownloaded(_ model: ModelInfo) -> Bool
    func delete(_ model: ModelInfo) throws
}
