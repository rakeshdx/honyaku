import XCTest

/// Settings > Vocabulary: add a term and see it listed. The app runs with `-HonyakuUITestSetupComplete YES`,
/// so the word list lives in a temporary folder, never the developer's own vocabulary.json.
final class VocabularyUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-HonyakuUITestSetupComplete", "YES"]
        app.launch()
        // Keep the menu bar icon out from behind the notch (see MenuBarUITests)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testAddingATermListsIt() throws {
        let item = app.statusItems["Honyaku"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Honyaku menu bar icon should exist")
        XCTAssertTrue(item.isHittable, "Honyaku menu bar icon should be on screen")
        item.click()

        let tab = app.toolbars.buttons["Vocabulary"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Settings should have a Vocabulary tab")
        tab.click()

        let add = app.buttons["Add term"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()

        let term = app.textFields["vocabulary.term"]
        XCTAssertTrue(term.waitForExistence(timeout: 3), "The add sheet should open")
        term.click()
        term.typeText("Paramount+")
        let heardAs = app.textFields["vocabulary.heardAs"]
        heardAs.click()
        heardAs.typeText("paramount plus")
        app.buttons["Add"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Paramount+"].waitForExistence(timeout: 3), "The new term should be listed")
        XCTAssertTrue(app.staticTexts["Heard as paramount plus"].exists)
    }
}
