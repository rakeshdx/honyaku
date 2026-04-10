import Foundation
import SpeakerKit

enum DiarizationError: Error {
    case modelNotFound
    case inferenceError(Error)
}

actor DiarizationService: DiarizationServiceProtocol {
    private let store = ModelStore.shared
    // In-memory speaker embedding registry for cross-recording label consistency
    private var speakerLabelMap: [String: String] = [:]
    private var nextSpeakerIndex: Int = 1

    func diarize(audioArray: [Float]) async throws -> [DiarizedSegment] {
        guard !audioArray.isEmpty else { return [] }

        let kit: SpeakerKit
        do {
            kit = try await SpeakerKit(PyannoteConfig())
        } catch {
            throw DiarizationError.inferenceError(error)
        }

        let result: DiarizationResult
        do {
            result = try await kit.diarize(audioArray: audioArray, options: nil, progressCallback: nil)
        } catch {
            throw DiarizationError.inferenceError(error)
        }

        return result.segments.map { seg in
            DiarizedSegment(
                startSeconds: Double(seg.startTime),
                endSeconds: Double(seg.endTime),
                speakerID: stableLabel(for: String(seg.speaker.speakerId ?? 0)),
                text: seg.text
            )
        }
    }

    // MARK: - Session-stable speaker label assignment

    private func stableLabel(for rawID: String) -> String {
        if let existing = speakerLabelMap[rawID] { return existing }
        let label = "Speaker \(nextSpeakerIndex)"
        speakerLabelMap[rawID] = label
        nextSpeakerIndex += 1
        return label
    }

    func resetSession() {
        speakerLabelMap.removeAll()
        nextSpeakerIndex = 1
    }
}

// MARK: - Segment merging helper

extension DiarizationService {
    /// Assign each WhisperKit timed segment to a speaker by finding the diarization
    /// segment with the greatest time overlap, then group consecutive same-speaker
    /// segments into labeled blocks.
    /// Falls back to rawText if diarization or timed segments are empty.
    static func mergeWithTranscript(
        rawText: String,
        timedSegments: [TimedSegment],
        diarizedSegments: [DiarizedSegment]
    ) -> String {
        guard !diarizedSegments.isEmpty, !timedSegments.isEmpty else { return rawText }

        // Assign each WhisperKit segment to the speaker with most overlap
        var labeled: [(speaker: String, text: String)] = []
        for tSeg in timedSegments {
            let text = tSeg.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }

            // Find diarization segment with the most overlap
            let best = diarizedSegments.max { a, b in
                overlap(tSeg, a) < overlap(tSeg, b)
            }
            labeled.append((speaker: best?.speakerID ?? "Speaker 1", text: text))
        }

        guard !labeled.isEmpty else { return rawText }

        // Group consecutive same-speaker chunks
        var result = ""
        var currentSpeaker = labeled[0].speaker
        var currentText = labeled[0].text

        for item in labeled.dropFirst() {
            if item.speaker == currentSpeaker {
                currentText += " " + item.text
            } else {
                result += "[\(currentSpeaker)] \(currentText) "
                currentSpeaker = item.speaker
                currentText = item.text
            }
        }
        result += "[\(currentSpeaker)] \(currentText)"
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func overlap(_ timed: TimedSegment, _ diarized: DiarizedSegment) -> Double {
        let start = max(timed.startSeconds, diarized.startSeconds)
        let end   = min(timed.endSeconds,   diarized.endSeconds)
        return max(0, end - start)
    }
}
