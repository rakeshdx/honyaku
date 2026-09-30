import XCTest
@testable import Honyaku

@MainActor
final class TranscriptStoreRedesignTests: XCTestCase {
    private func entry(_ text: String) -> TranscriptEntry {
        TranscriptEntry(rawText: text, cleanedText: text, modelTier: "test", durationSeconds: 1)
    }

    func testDeleteRemovesOnlyThatEntry() {
        let a = entry("first"), b = entry("second")
        let store = TranscriptStore(inMemory: [a, b])
        store.delete(a.id)
        XCTAssertEqual(store.entries.map(\.id), [b.id])
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let entries = [entry("Send the Invoice today"), entry("Book the café"), entry("Call Mum")]
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "invoice").map(\.cleanedText), ["Send the Invoice today"])
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "cafe").map(\.cleanedText), ["Book the café"])
    }

    func testBlankSearchReturnsEverything() {
        let entries = [entry("one"), entry("two")]
        XCTAssertEqual(TranscriptStore.filter(entries, matching: "  ").count, 2)
    }

    func testInMemoryStoreNeverTouchesHistoryFile() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honyaku/history.json")
        let before = try? Data(contentsOf: file)
        let store = TranscriptStore(inMemory: [])
        store.save(entry("never persisted"))
        store.clearAll()
        XCTAssertEqual(try? Data(contentsOf: file), before)
    }
}

final class InputLevelTests: XCTestCase {
    func testSilenceIsZeroAndFullScaleIsOne() {
        let silence = [Float](repeating: 0, count: 480)
        let loud = [Float](repeating: 1, count: 480)
        silence.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 0) }
        loud.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 1, accuracy: 0.001) }
    }

    func testQuietSpeechIsInTheMiddle() {
        // RMS 0.03 ≈ −30 dBFS → 0.4 on the −50…0 scale
        let quiet = [Float](repeating: 0.03, count: 480)
        quiet.withUnsafeBufferPointer { XCTAssertEqual(AudioCaptureService.level(samples: $0), 0.4, accuracy: 0.02) }
    }
}

final class KeycapStateTests: XCTestCase {
    func testStatusMapsToKeyState() {
        XCTAssertEqual(KeycapView.KeyState(.idle), .idle)
        XCTAssertEqual(KeycapView.KeyState(.recording), .recording)
        XCTAssertEqual(KeycapView.KeyState(.transcribing), .busy)
        XCTAssertEqual(KeycapView.KeyState(.processing), .busy)
        XCTAssertEqual(KeycapView.KeyState(.error("x")), .error)
    }
}

final class StatusCopyTests: XCTestCase {
    func testStateLinesCoverEveryStatus() {
        XCTAssertEqual(StatusCopy.stateLine(for: .idle), "Hold Control to talk")
        XCTAssertEqual(StatusCopy.stateLine(for: .recording), "Listening…")
        XCTAssertEqual(StatusCopy.stateLine(for: .transcribing), "Transcribing…")
        XCTAssertEqual(StatusCopy.stateLine(for: .processing), "Cleaning up…")
        XCTAssertEqual(StatusCopy.stateLine(for: .error("Microphone disconnected.")), "Microphone disconnected.")
    }

    func testIdleDetailExplainsDictationAndNamesTheModels() {
        let line = StatusCopy.detailLine(for: .idle, speechModelID: "parakeet-tdt-v2", cleanupEnabled: true)
        XCTAssertTrue(line.hasPrefix("Let go to paste"))
        XCTAssertTrue(line.contains("cleanup on"))
    }

    func testBusyDetailOnlyNamesTheModels() {
        let line = StatusCopy.detailLine(for: .recording, speechModelID: "parakeet-tdt-v2", cleanupEnabled: false)
        XCTAssertFalse(line.contains("Let go"))
        XCTAssertTrue(line.hasSuffix("cleanup off"))
    }

    func testDownloadLineRoundsThePercentage() {
        XCTAssertTrue(StatusCopy.downloadLine(modelID: "qwen3-1.7b", fraction: 0.426).hasSuffix(", 43%"))
        XCTAssertEqual(StatusCopy.downloadLine(modelID: "unknown", fraction: 1), "Downloading unknown, 100%")
    }
}

final class StatusItemSymbolTests: XCTestCase {
    func testSymbolFollowsStatus() {
        XCTAssertEqual(StatusItemController.symbol(for: .idle), "waveform")
        XCTAssertEqual(StatusItemController.symbol(for: .recording), "waveform.circle.fill")
        XCTAssertEqual(StatusItemController.symbol(for: .transcribing), "ellipsis.circle")
        XCTAssertEqual(StatusItemController.symbol(for: .processing), "ellipsis.circle")
        XCTAssertEqual(StatusItemController.symbol(for: .error("x")), "exclamationmark.circle")
    }

    func testVoiceOverValueNamesTheState() {
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .idle), "Ready")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .recording), "Recording")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .transcribing), "Transcribing")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .processing), "Cleaning up")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .error("Mic unplugged.")), "Error: Mic unplugged.")
    }
}

final class DictationDestinationTests: XCTestCase {
    private func destination(_ recorded: Int?, _ current: Int?, front: Bool = false) -> DictationDestination {
        TranscriptionPipeline.destination(recordedInTest: recorded, currentTest: current, honyakuIsFrontmost: front)
    }

    func testOrdinaryDictationPastes() {
        XCTAssertEqual(destination(nil, nil), .paste)
    }

    func testTestDictationGoesToTheWindowWhileItsTestRuns() {
        // Honyaku is always in front during Try it; that must not turn the result into "save only"
        XCTAssertEqual(destination(3, 3, front: true), .firstRunTest)
    }

    func testTestDictationIsDiscardedOnceTheWindowCloses() {
        XCTAssertEqual(destination(3, nil), .discard)
        XCTAssertEqual(destination(3, nil, front: true), .discard)
    }

    func testTestDictationFromAnEarlierTestIsDiscarded() {
        XCTAssertEqual(destination(3, 4, front: true), .discard)
    }

    func testDictationStartedBeforeTheTestStillPastes() {
        // Recording began elsewhere, then Try it opened: not a test, so it isn't shown in the window
        XCTAssertEqual(destination(nil, 4), .paste)
    }

    func testHonyakuInFrontSavesWithoutPasting() {
        XCTAssertEqual(destination(nil, nil, front: true), .saveOnly)
        XCTAssertEqual(destination(nil, 4, front: true), .saveOnly)
    }
}

@MainActor
final class FirstRunTestSessionTests: XCTestCase {
    func testEachTestGetsANewSessionAndEndingClearsTheResult() {
        let state = AppState()
        state.beginFirstRunTest()
        let first = state.firstRunTestSession
        XCTAssertNotNil(first)
        state.firstRunTestTranscript = "hello"
        state.endFirstRunTest()
        XCTAssertNil(state.firstRunTestSession)
        XCTAssertNil(state.firstRunTestTranscript)
        XCTAssertFalse(state.firstRunTestActive)
        state.beginFirstRunTest()
        XCTAssertNotEqual(state.firstRunTestSession, first)
    }
}

final class FirstRunStepTests: XCTestCase {
    func testMissingPermissionComesFirstEvenAfterSetup() {
        XCTAssertEqual(FirstRunView.firstIncompleteStep(setupComplete: true, microphoneGranted: true, accessibilityGranted: false), .permissions)
        XCTAssertEqual(FirstRunView.firstIncompleteStep(setupComplete: true, microphoneGranted: false, accessibilityGranted: true), .permissions)
        XCTAssertEqual(FirstRunView.firstIncompleteStep(setupComplete: false, microphoneGranted: false, accessibilityGranted: false), .permissions)
    }

    func testModelsThenTryIt() {
        XCTAssertEqual(FirstRunView.firstIncompleteStep(setupComplete: false, microphoneGranted: true, accessibilityGranted: true), .models)
        XCTAssertEqual(FirstRunView.firstIncompleteStep(setupComplete: true, microphoneGranted: true, accessibilityGranted: true), .tryIt)
    }

    func testNeededUntilEverythingIsDone() {
        XCTAssertFalse(FirstRunView.isNeeded(setupComplete: true, microphoneGranted: true, accessibilityGranted: true))
        XCTAssertTrue(FirstRunView.isNeeded(setupComplete: false, microphoneGranted: true, accessibilityGranted: true))
        XCTAssertTrue(FirstRunView.isNeeded(setupComplete: true, microphoneGranted: false, accessibilityGranted: true))
        XCTAssertTrue(FirstRunView.isNeeded(setupComplete: true, microphoneGranted: true, accessibilityGranted: false))
    }
}

final class ModelCopyTests: XCTestCase {
    func testLargerCleanupModelSaysItNeeds16GB() throws {
        let model = try XCTUnwrap(ModelRegistry.model(id: "qwen3-4b-2507"))
        XCTAssertEqual(ModelCopy.summary(for: model), "Most accurate, needs 16 GB of memory")
    }

    func testEveryOfferedTierHasItsOwnCopy() {
        // ModelCopy covers exactly the tiers the registry offers
        let tiers = Set((ModelRegistry.speechModels + ModelRegistry.cleanupModels).map(\.tier))
        XCTAssertEqual(tiers, ["recommended", "multilingual", "fast", "best"])
    }
}
