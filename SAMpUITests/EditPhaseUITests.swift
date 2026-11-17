import XCTest

/// Program page → Manage → a phase → Edit Phase → rename → Save, and the
/// phase page shows the new name (18 Nov 2026, Luther: tapping a phase in
/// Manage Phases showed nothing to modify). Puts the name back after.
final class EditPhaseUITests: XCTestCase {
    func testAPhaseCanBeEditedFromManagePhases() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_SHOT"] = "programDetail"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let manage = app.buttons["program.managePhases"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let firstPhase = app.cells.firstMatch
        XCTAssertTrue(firstPhase.waitForExistence(timeout: 8))
        firstPhase.tap()

        let edit = app.buttons["phase.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), "the phase page offers Edit Phase")
        edit.tap()
        let field = app.textFields["phase.edit.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = (field.value as? String) ?? ""
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("UITest phase")
        app.buttons["phase.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["UITest phase"].firstMatch.waitForExistence(timeout: 5), "the page shows the new name")

        // Put it back.
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText(original)
        app.buttons["phase.edit.save"].tap()
    }
}
