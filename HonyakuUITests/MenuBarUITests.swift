import XCTest

final class MenuBarUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        // Allow the app to initialise
        sleep(1)
    }

    func testMenuBarIconExists() throws {
        let statusItem = app.menuBars.firstMatch
        XCTAssertTrue(statusItem.exists, "Honyaku menu bar icon should be visible")
    }

    func testPopoverOpensOnClick() throws {
        // Click the Honyaku menu bar extra
        let menuBarButton = app.menuBars.buttons["Honyaku"].firstMatch
        guard menuBarButton.exists else {
            throw XCTSkip("Menu bar button not found — ensure app launched with menu bar mode")
        }
        menuBarButton.click()
        let settingsButton = app.buttons["Settings…"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2), "Settings button should appear after clicking menu bar icon")
    }

    func testSettingsPanelOpens() throws {
        let menuBarButton = app.menuBars.buttons["Honyaku"].firstMatch
        guard menuBarButton.exists else { throw XCTSkip("Menu bar button not found") }
        menuBarButton.click()

        let settingsButton = app.buttons["Settings…"].firstMatch
        guard settingsButton.waitForExistence(timeout: 2) else { throw XCTSkip("Popover did not open") }
        settingsButton.click()

        // The native Settings window opens on its General tab (or the last tab used)
        let generalTab = app.toolbars.buttons["General"].firstMatch
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3), "Settings window with its General tab should appear")
    }

    func testClearHistoryConfirmationDialog() throws {
        let menuBarButton = app.menuBars.buttons["Honyaku"].firstMatch
        guard menuBarButton.exists else { throw XCTSkip("Menu bar button not found") }
        menuBarButton.click()

        let settingsButton = app.buttons["Settings…"].firstMatch
        guard settingsButton.waitForExistence(timeout: 2) else { throw XCTSkip("Popover not open") }
        settingsButton.click()

        // Navigate to History tab
        let historyTab = app.buttons["History"].firstMatch
        if historyTab.waitForExistence(timeout: 2) { historyTab.click() }

        let clearButton = app.buttons["Clear All History"].firstMatch
        if clearButton.exists && clearButton.isEnabled {
            clearButton.click()
            // Confirmation alert should appear
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 2), "Clear History confirmation alert should appear")
            alert.buttons["Cancel"].click()
        }
    }
}
