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
        // A long menu from the app in front can push the icon behind the notch. Finder's menu bar is short,
        // so the icon is on screen whatever the developer was using.
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Fails the test, rather than skipping it, when the icon can't be found.
    private func statusItem() -> XCUIElement {
        let item = app.statusItems["Honyaku"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Honyaku menu bar icon should exist")
        XCTAssertTrue(item.isHittable, "Honyaku menu bar icon should be on screen, not hidden behind the notch")
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
        // The icon's own menu, not the app's main menu (which also has "Quit Honyaku")
        let quit = app.menuItems["statusMenu.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 2), "Right-click should open the icon's menu")
        XCTAssertEqual(quit.title, "Quit Honyaku")
        XCTAssertEqual(app.menuItems["statusMenu.settings"].title, "Settings…")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testRightClickMenuHasRewriteAs() throws {
        statusItem().rightClick()
        let rewriteAs = app.menuItems["statusMenu.rewrite"]
        XCTAssertTrue(rewriteAs.waitForExistence(timeout: 2), "The icon's menu should have Rewrite as")
        XCTAssertEqual(rewriteAs.title, "Rewrite as")
        rewriteAs.hover()
        let automatic = app.menuItems["statusMenu.rewrite.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 2))
        XCTAssertEqual(automatic.title, "Automatic (by app)")
        let templates = ["jiraTicket": "Jira ticket", "chatMessage": "Chat message", "email": "Email",
                         "commitMessage": "Commit message", "prDescription": "PR description",
                         "agentPrompt": "Coding-agent prompt", "standupUpdate": "Standup update"]
        for (id, title) in templates {
            XCTAssertEqual(app.menuItems["statusMenu.rewrite.\(id)"].title, title)
        }
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    func testSettingsHasARewriteTab() throws {
        statusItem().click()
        let rewriteTab = app.toolbars.buttons["Rewrite"].firstMatch
        XCTAssertTrue(rewriteTab.waitForExistence(timeout: 3), "Settings should have a Rewrite tab")
        rewriteTab.click()
        let intro = app.staticTexts["Hold Control+Shift to rewrite what you say in a format for where it's going."]
        XCTAssertTrue(intro.waitForExistence(timeout: 3), "The Rewrite tab should explain Control+Shift")
    }
}
