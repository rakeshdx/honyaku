import XCTest

/// Settings > Apps. UI-test launches keep feature files in a temporary folder, so the developer's own
/// app-profiles.json is never read or changed.
final class AppsSettingsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-HonyakuUITestSetupComplete", "YES"]
        app.launch()
        // Keeps the menu bar icon clear of the notch (see MenuBarUITests)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func openApps() {
        let item = app.statusItems["Honyaku"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Honyaku menu bar icon should exist")
        XCTAssertTrue(item.isHittable, "Honyaku menu bar icon should be on screen")
        item.click()
        let appsTab = app.toolbars.buttons["Apps"].firstMatch
        XCTAssertTrue(appsTab.waitForExistence(timeout: 3), "Settings should have an Apps tab")
        appsTab.click()
    }

    /// Any element showing `text`: a disclosure row exposes its label differently from a plain text.
    private func element(showing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@ OR value == %@", text, text, text))
            .firstMatch
    }

    func testAppsTabListsTheCategories() throws {
        openApps()
        XCTAssertTrue(element(showing: "Formatting only. Honyaku never changes your words here.").waitForExistence(timeout: 3))
        // Rows further down are built lazily, once scrolled into view; the first ones are enough here
        XCTAssertTrue(element(showing: "Terminals").waitForExistence(timeout: 3))
        XCTAssertTrue(element(showing: "Code editors").exists)
    }

    func testAddingARunningAppListsIt() throws {
        openApps()
        let add = app.descendants(matching: .any)["apps.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3), "the + menu should exist")
        add.click()
        // Finder is always running, so it's always offered
        let finder = app.menuItems["Finder"].firstMatch
        XCTAssertTrue(finder.waitForExistence(timeout: 3), "the + menu should list running apps")
        finder.click()
        XCTAssertTrue(app.descendants(matching: .any)["apps.override.com.apple.finder"].firstMatch
            .waitForExistence(timeout: 3), "Finder should be listed under apps with their own rules")
    }
}
