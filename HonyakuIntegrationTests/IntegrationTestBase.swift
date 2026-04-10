import XCTest

/// Base class for all integration tests.
/// Tests only run when INTEGRATION_TESTS=1 is set in the environment.
class IntegrationTestBase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set INTEGRATION_TESTS=1 to run integration tests")
        }
    }

    /// URL of a test fixture in the bundle.
    func fixtureURL(named name: String) throws -> URL {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: nil) else {
            throw XCTSkip("Fixture '\(name)' not found — record audio fixtures per tasks.md 13.10")
        }
        return url
    }
}
