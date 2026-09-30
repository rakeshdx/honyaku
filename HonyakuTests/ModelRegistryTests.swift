import XCTest
@testable import Honyaku

final class ModelRegistryTests: XCTestCase {
    private let gib: UInt64 = 1024 * 1024 * 1024

    func testRecommendationFor8GB() {
        let pick = ModelRegistry.recommended(forPhysicalMemory: 8 * gib)
        XCTAssertEqual(pick.speech, "parakeet-tdt-v2")
        XCTAssertEqual(pick.cleanup, "qwen3-1.7b")
    }

    func testRecommendationFor16And36GB() {
        XCTAssertEqual(ModelRegistry.recommended(forPhysicalMemory: 16 * gib).cleanup, "qwen3-4b-2507")
        XCTAssertEqual(ModelRegistry.recommended(forPhysicalMemory: 36 * gib).cleanup, "qwen3-4b-2507")
    }

    func testRecommendedModelsExist() {
        for memory in [8 * gib, 36 * gib] {
            let pick = ModelRegistry.recommended(forPhysicalMemory: memory)
            XCTAssertNotNil(ModelRegistry.model(id: pick.speech))
            XCTAssertNotNil(ModelRegistry.model(id: pick.cleanup))
        }
    }

    func testRetiredModelsMigrate() {
        XCTAssertEqual(ModelRegistry.migratedID("whisper-tiny-en"), "parakeet-tdt-v2")
        XCTAssertEqual(ModelRegistry.migratedID("whisper-small-en"), "parakeet-tdt-v2")
        XCTAssertEqual(ModelRegistry.migratedID("whisper-small-multilingual"), "whisper-large-v3-turbo")
        XCTAssertEqual(ModelRegistry.migratedID("qwen-1.5b-mlx"), "qwen3-1.7b")
        XCTAssertEqual(ModelRegistry.migratedID("qwen-3b-mlx"), "qwen3-4b-2507")
        XCTAssertEqual(ModelRegistry.migratedID("qwen-7b-mlx"), "qwen3-4b-2507")
        XCTAssertNil(ModelRegistry.migratedID("qwen3-1.7b"), "Current models don't migrate")
    }

    func testEveryMigrationTargetExists() {
        for old in ["whisper-tiny-en", "whisper-small-en", "whisper-small-multilingual",
                    "qwen-1.5b-mlx", "qwen-3b-mlx", "qwen-7b-mlx", "qwen-0.8b"] {
            let target = ModelRegistry.migratedID(old)
            XCTAssertNotNil(target.flatMap(ModelRegistry.model(id:)), old)
        }
    }

    func testResolvedIDKeepsCurrentMigratesRetiredAndFallsBack() {
        XCTAssertEqual(ModelRegistry.resolvedID("whisper-large-v3-turbo", fallback: "x"), "whisper-large-v3-turbo")
        XCTAssertEqual(ModelRegistry.resolvedID("qwen-3b-mlx", fallback: "x"), "qwen3-4b-2507")
        XCTAssertEqual(ModelRegistry.resolvedID("no-such-model", fallback: "qwen3-1.7b"), "qwen3-1.7b")
        XCTAssertEqual(ModelRegistry.resolvedID(nil, fallback: "qwen3-1.7b"), "qwen3-1.7b")
    }

    @MainActor
    func testSavedRetiredSelectionIsMigratedAndWrittenBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "honyaku-migration-test-\(UUID())"))
        defaults.set("qwen-3b-mlx", forKey: "selectedCleanupModelID")
        let resolved = AppState.resolvedSelection(key: "selectedCleanupModelID", fallback: "qwen3-1.7b", defaults: defaults)
        XCTAssertEqual(resolved, "qwen3-4b-2507")
        XCTAssertEqual(defaults.string(forKey: "selectedCleanupModelID"), "qwen3-4b-2507",
                       "CleanupService reads UserDefaults directly, so the migration must be saved")
    }

    func testEngineMatchesModelType() {
        XCTAssertTrue(ModelRegistry.speechModels.allSatisfy { [.parakeet, .whisperKit].contains($0.engine) })
        XCTAssertTrue(ModelRegistry.cleanupModels.allSatisfy { $0.engine == .mlx })
        XCTAssertEqual(ModelRegistry.model(id: "whisper-large-v3-turbo")?.whisperVariant,
                       "openai_whisper-large-v3-v20240930_626MB")
        XCTAssertEqual(ModelRegistry.model(id: "qwen3-1.7b")?.disablesThinking, true)
    }
}
