import XCTest

/// Adding an athlete opens the same page as editing one (October 2026,
/// Luther), and Save on it creates the athlete. Runs the real path —
/// Athletes → + → Add Student — in the isolated demo store.
final class AddStudentUITests: XCTestCase {

    func testAddStudentUsesTheEditPageAndSaves() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The simulators are signed into the coach's iCloud: this must write
        // to the isolated demo store, never the synced one.
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()

        let athletes = app.buttons["Athletes"].firstMatch
        XCTAssertTrue(athletes.waitForExistence(timeout: 30))
        athletes.tap()

        let add = app.buttons["athletes.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let addItem = app.buttons["Add Student"].firstMatch
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()

        // The edit page's own rows: one School Grade menu, no Date of Birth tab.
        XCTAssertTrue(app.staticTexts["New Athlete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["School Grade"].exists)
        XCTAssertFalse(app.buttons["Date of Birth"].exists)

        let unique = "Zed Uitest \(Int(Date().timeIntervalSince1970) % 100000)"
        let nameField = app.textFields["Full name"].firstMatch
        nameField.tap()
        nameField.typeText(unique)
        app.buttons["Save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["New Athlete"].waitForNonExistence(timeout: 5), "sheet stayed open")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(unique)
        }
        XCTAssertTrue(app.staticTexts[unique].firstMatch.waitForExistence(timeout: 10),
                      "the new athlete is not in the list")
    }
}
