import AVFoundation
import Foundation

enum AudioCaptureError: Error {
    case engineSetupFailed
    case noMicrophonePermission
    case deviceUnavailable
    case writeFailed(Error)
}

/// Captures audio only while explicitly started; tears down the tap on every stop.
/// The microphone access session is NEVER held open between recordings.
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var pcmBuffers: [AVAudioPCMBuffer] = []
    private var selectedDeviceID: AudioDeviceID?

    // Called when the selected microphone is disconnected
    var onDeviceDisconnected: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func startCapture() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.noMicrophonePermission
        }
        pcmBuffers.removeAll()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A second tap on the same bus raises an exception, so clear any tap a failed run left behind
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.pcmBuffers.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            pcmBuffers.removeAll()
            throw error
        }
    }

    /// Sets up the input device ahead of the next press without starting audio input (the mic
    /// indicator stays off). Otherwise the first press pays for creating the input and loses
    /// the start of the first word. `engine.stop()` releases this, so each stop path calls it again.
    func prepare() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        _ = engine.inputNode
        engine.prepare()
    }

    /// Stops capture, tears down the tap, writes to a temp WAV file, returns its URL.
    func stopCaptureAndFlush() throws -> URL {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)   // ← mic released here
        prepare()
        return try writeTempWAV()
    }

    /// Stops capture, tears down the tap, and returns both the WAV URL (for WhisperKit)
    /// and the raw mono float samples (for SpeakerKit). Float extraction happens before
    /// writeTempWAV() clears the buffer.
    func stopCaptureAndFlushBoth() throws -> (url: URL, floatArray: [Float]) {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)   // ← mic released here
        prepare()
        let floats = extractFloatArray()
        let url = try writeTempWAV()
        return (url, floats)
    }

    /// Discard buffered audio without writing (e.g. press < 300ms).
    func cancelCapture() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        pcmBuffers.removeAll()
        prepare()
    }

    /// True when no 100 ms window of 16 kHz audio rises above −45 dBFS RMS: the user held Control but
    /// didn't speak. Speech, even quiet speech, sits well above that; a mic's noise floor sits below.
    static func isSilent(samples16k samples: [Float], thresholdDBFS: Float = -45) -> Bool {
        let window = 1_600
        let threshold = powf(10, thresholdDBFS / 20)
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            if (sum / Float(end - start)).squareRoot() > threshold { return false }
            start = end
        }
        return true
    }

    // MARK: - Microphone enumeration

    static func availableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    // MARK: - Private

    private func writeTempWAV() throws -> URL {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("honyaku_\(UUID().uuidString).wav")

        guard let firstBuffer = pcmBuffers.first else {
            // Return empty file rather than crashing
            try Data().write(to: tempURL)
            return tempURL
        }

        let format = firstBuffer.format
        guard let file = try? AVAudioFile(forWriting: tempURL, settings: format.settings) else {
            throw AudioCaptureError.writeFailed(URLError(.cannotCreateFile))
        }
        for buffer in pcmBuffers {
            try file.write(from: buffer)
        }
        pcmBuffers.removeAll()
        return tempURL
    }

    /// Extracts mono float samples resampled to 16 kHz (SpeakerKit/Pyannote requirement).
    /// The native mic rate on Mac is typically 44.1 kHz or 48 kHz; passing that rate to
    /// SpeakerKit compresses the timeline and breaks speaker detection.
    private func extractFloatArray() -> [Float] {
        guard !pcmBuffers.isEmpty, let firstBuffer = pcmBuffers.first else { return [] }
        let inputFormat = firstBuffer.format
        let targetRate = 16_000.0

        // Concatenate all captured buffers into one
        let totalFrames = pcmBuffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalFrames > 0,
              let combined = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: totalFrames) else { return [] }
        combined.frameLength = totalFrames
        var offset = 0
        for buf in pcmBuffers {
            guard let src = buf.floatChannelData, let dst = combined.floatChannelData else { continue }
            let count = Int(buf.frameLength)
            for ch in 0..<Int(inputFormat.channelCount) {
                dst[ch].advanced(by: offset).update(from: src[ch], count: count)
            }
            offset += count
        }

        // Already correct format — return directly
        guard let mono16k = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: targetRate,
                                          channels: 1,
                                          interleaved: false) else { return [] }
        if inputFormat.sampleRate == targetRate && inputFormat.channelCount == 1 {
            guard let data = combined.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: data[0], count: Int(totalFrames)))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: mono16k) else { return [] }
        let outputCapacity = AVAudioFrameCount(Double(totalFrames) * targetRate / inputFormat.sampleRate + 128)
        guard let output = AVAudioPCMBuffer(pcmFormat: mono16k, frameCapacity: outputCapacity) else { return [] }

        var fed = false
        var err: NSError?
        converter.convert(to: output, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return combined
        }

        guard err == nil, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    @objc private func handleDeviceChange(_ notification: Notification) {
        // The notification fires for every AV device (webcams included); only audio inputs matter
        guard let device = notification.object as? AVCaptureDevice, device.hasMediaType(.audio) else { return }
        onDeviceDisconnected?()
    }
}
