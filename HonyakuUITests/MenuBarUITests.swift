import XCTest

/// Clicking the menu bar icon opens Settings directly; there's no popover.
/// The app runs with `-HonyakuUITestSetupComplete YES` (Debug only): setup counts as done for this launch,
/// so the tests never depend on, or change, the developer's own setup, and no listener or model starts.
final class MenuBarUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-HonyakuUITestSetupComplete", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Fails the test, rather than skipping it, when the icon can't be found.
    private func statusItem() -> XCUIElement {
        let item = app.statusItems["Honyaku"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Honyaku menu bar icon should be visible")
        return item
    }

    private var generalTab: XCUIElement { app.toolbars.buttons["General"].firstMatch }

    func testMenuBarIconExists() throws {
        _ = statusItem()
    }

    func testClickOpensSettings() throws {
        statusItem().click()
        // Settings opens on its General tab, or the last tab used; the toolbar always has General
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3), "Settings window should open straight from the icon")
    }

    func testClickingAgainKeepsOneSettingsWindow() throws {
        let item = statusItem()
        item.click()
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3))
        item.click()
        // Give a second window, if one were made, time to appear
        XCTAssertFalse(app.windows.element(boundBy: 1).waitForExistence(timeout: 1))
        XCTAssertEqual(app.windows.count, 1, "Exactly one Settings window")
    }

    func testRightClickShowsQuit() throws {
        statusItem().rightClick()
        XCTAssertTrue(app.menuItems["Quit Honyaku"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
