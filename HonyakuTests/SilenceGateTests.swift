import XCTest
@testable import Honyaku

final class SilenceGateTests: XCTestCase {
    private func tone(amplitude: Float, seconds: Double = 1) -> [Float] {
        (0..<Int(16_000 * seconds)).map { amplitude * sinf(2 * .pi * 220 * Float($0) / 16_000) }
    }

    func testDigitalSilenceIsSilent() {
        XCTAssertTrue(AudioCaptureService.isSilent(samples16k: [Float](repeating: 0, count: 16_000)))
    }

    func testMicNoiseFloorIsSilent() {
        // Uniform noise of ±0.003 is about −55 dBFS RMS
        let noise = (0..<16_000).map { _ in Float.random(in: -0.003...0.003) }
        XCTAssertTrue(AudioCaptureService.isSilent(samples16k: noise))
    }

    func testQuietSpeechLevelIsNotSilent() {
        // A 0.02 sine is about −37 dBFS RMS
        XCTAssertFalse(AudioCaptureService.isSilent(samples16k: tone(amplitude: 0.02)))
    }

    func testOneLoudWindowIsEnough() {
        var samples = [Float](repeating: 0, count: 16_000)
        samples.replaceSubrange(8_000..<9_600, with: tone(amplitude: 0.1, seconds: 0.1))
        XCTAssertFalse(AudioCaptureService.isSilent(samples16k: samples))
    }
}
