import XCTest

/// Clicking the menu bar icon opens Settings directly; there's no popover.
final class MenuBarUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        // Allow the app to initialise
        sleep(1)
    }

    private var statusItem: XCUIElement { app.statusItems["Honyaku"].firstMatch }

    func testMenuBarIconExists() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 2), "Honyaku menu bar icon should be visible")
    }

    func testClickOpensSettings() throws {
        guard statusItem.waitForExistence(timeout: 2) else { throw XCTSkip("Menu bar icon not found") }
        statusItem.click()
        // Settings opens on its General tab, or the last tab used (first run instead if setup isn't done)
        let generalTab = app.toolbars.buttons["General"].firstMatch
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3), "Settings window should open straight from the icon")
    }

    func testClickingAgainKeepsOneSettingsWindow() throws {
        guard statusItem.waitForExistence(timeout: 2) else { throw XCTSkip("Menu bar icon not found") }
        statusItem.click()
        statusItem.click()
        XCTAssertLessThanOrEqual(app.windows.count, 1, "Only one Settings window")
    }

    func testRightClickShowsQuit() throws {
        guard statusItem.waitForExistence(timeout: 2) else { throw XCTSkip("Menu bar icon not found") }
        statusItem.rightClick()
        XCTAssertTrue(app.menuItems["Quit Honyaku"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
