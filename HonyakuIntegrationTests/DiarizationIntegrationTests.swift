import XCTest
import WhisperKit
@testable import Honyaku

final class DiarizationIntegrationTests: IntegrationTestBase {

    func testTwoSpeakersFixtureProducesAtLeastTwoSpeakerIDs() async throws {
        let audioURL = try fixtureURL(named: "two_speakers.wav")
        let service = DiarizationService()
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let segments = try await service.diarize(audioArray: audio)
        let speakerIDs = Set(segments.map(\.speakerID))
        XCTAssertGreaterThanOrEqual(speakerIDs.count, 2,
                                    "two_speakers.wav should produce ≥2 distinct speaker IDs")
    }

    func testSingleSpeakerFixtureProducesNoLabelsOrOneLabel() async throws {
        let audioURL = try fixtureURL(named: "single_speaker.wav")
        let service = DiarizationService()
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let segments = try await service.diarize(audioArray: audio)
        let speakerIDs = Set(segments.map(\.speakerID))
        XCTAssertLessThanOrEqual(speakerIDs.count, 1,
                                  "single_speaker.wav should produce ≤1 distinct speaker ID")
    }

    func testTempFileDeletionAfterTranscription() async throws {
        let audioURL = try fixtureURL(named: "filler_heavy.wav")
        // Copy to temp dir to simulate pipeline temp file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("honyaku_\(UUID()).wav")
        try FileManager.default.copyItem(at: audioURL, to: tempURL)

        let service = TranscriptionService()
        _ = try? await service.transcribe(audioURL: tempURL, modelID: ModelRegistry.defaultSpeechModelID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "Temp WAV file must be deleted after TranscriptionService returns")
    }
}
