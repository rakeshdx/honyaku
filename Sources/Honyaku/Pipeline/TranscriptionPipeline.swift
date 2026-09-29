import Foundation

/// Orchestrates: AudioCapture → WhisperKit → SpeakerKit → CleanupLLM → PasteService
@MainActor
final class TranscriptionPipeline {
    private let audioCapture = AudioCaptureService()
    private let transcription = TranscriptionService()
    private let diarization = DiarizationService()
    private let cleanup = CleanupService()
    private let paste = PasteService()
    private let transcriptStore: TranscriptStore
    private let appState: AppState

    init(appState: AppState, transcriptStore: TranscriptStore) {
        self.appState = appState
        self.transcriptStore = transcriptStore
        audioCapture.prepare()
        audioCapture.onDeviceDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Stop the live engine first; otherwise key-up bails on the error state and the tap leaks
                self.cancelRecording()
                self.appState.setError("Microphone disconnected — switched to system default.")
            }
        }
    }

    /// Loads the models in the background so the first dictation after launch isn't slower than the rest.
    /// Failures are ignored here; a real dictation reports them.
    func warmUp() {
        let modelID = appState.selectedSpeechModelID
        let cleanupEnabled = appState.cleanupEnabled
        Task {
            try? await transcription.prepare(modelID: modelID)
            if cleanupEnabled { try? await cleanup.prepare() }
        }
    }

    // MARK: - Recording lifecycle

    func startRecording() {
        guard !appState.status.isBusy else { return }
        // Clear any prior error so Control key works again after a failed pipeline run
        appState.clearError()
        do {
            try audioCapture.startCapture()
            appState.status = .recording
        } catch {
            appState.setError("Could not start microphone: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndProcess() {
        guard appState.status == .recording else { return }
        appState.status = .transcribing

        Task {
            do {
                let (audioURL, floatArray) = try audioCapture.stopCaptureAndFlushBoth()
                try await run(audioURL: audioURL, floatArray: floatArray)
            } catch AudioCaptureError.noMicrophonePermission {
                appState.setError("Microphone permission required.")
            } catch {
                appState.setError(error.localizedDescription)
                await paste.clearTranscriptFromPasteboard(after: pasteboardClearDelay)
            }
            if case .error = appState.status {} else {
                appState.status = .idle
            }
        }
    }

    func cancelRecording() {
        // Only an active recording is cancelled — never overwrite an error or an in-flight pipeline run
        guard appState.status == .recording else { return }
        audioCapture.cancelCapture()
        appState.status = .idle
    }

    // MARK: - Private pipeline

    private let pasteboardClearDelay: Double = 5.0

    private func run(audioURL: URL, floatArray: [Float]) async throws {
        // Step 1: ASR (WhisperKit consumes audioURL and deletes it on return)
        let modelID = appState.selectedSpeechModelID
        let result = try await transcription.transcribe(audioURL: audioURL, modelID: modelID)

        // Empty / silence → discard
        guard !result.rawText.trimmingCharacters(in: .whitespaces).isEmpty else {
            appState.status = .idle
            return
        }

        appState.status = .processing

        // Step 2: Diarization (optional, after ASR, before cleanup)
        // Uses the pre-captured float array — no dependency on audioURL which is already deleted.
        var labeledText = result.rawText
        var segments: [DiarizedSegment] = []
        if appState.diarizationEnabled {
            segments = (try? await diarization.diarize(audioArray: floatArray)) ?? []
            let uniqueSpeakers = Set(segments.map(\.speakerID))
            if uniqueSpeakers.count > 1 {
                labeledText = DiarizationService.mergeWithTranscript(
                    rawText: result.rawText,
                    timedSegments: result.timedSegments,
                    diarizedSegments: segments
                )
            }
        }

        // Step 3: Cleanup (optional)
        let cleanupPrompt = UserDefaults.standard.string(forKey: "cleanupPrompt") ?? CleanupService.defaultPrompt
        var finalText = labeledText
        if appState.cleanupEnabled {
            do {
                let cleaned = try await cleanup.clean(labeledText, prompt: cleanupPrompt)
                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? labeledText : trimmed
            } catch {
                // Timeout, model not loaded, or any other error — fall back to labeled text
                finalText = labeledText
            }
        }

        // Step 4: Paste
        do {
            try await paste.paste(finalText)
        } catch {
            await paste.clearTranscriptFromPasteboard(after: pasteboardClearDelay)
            throw error
        }

        // Step 5: Persist to history (no content in log messages)
        let entry = TranscriptEntry(
            rawText: result.rawText,
            cleanedText: finalText,
            modelTier: modelID,
            durationSeconds: result.durationSeconds,
            hasSpeakerLabels: !segments.isEmpty
        )
        transcriptStore.save(entry)
    }
}
