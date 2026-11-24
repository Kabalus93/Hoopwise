import XCTest

/// The session's reminders box (20 Nov 2026, Luther: "kind of intimidating"):
/// one quiet line; the options appear while writing; Return saves and folds.
final class SessionRemindersUITests: XCTestCase {
    func testQuietLineOpensAndFolds() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "3"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let field = app.textFields["reminders.quickAdd"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "the add line")
        XCTAssertEqual(field.placeholderValue, "Add a reminder")
        // By identifier: its words depend on the data ("Before next class"
        // only when the program has a later class; else "Tomorrow").
        let due = app.descendants(matching: .any).matching(identifier: "reminders.due").firstMatch
        XCTAssertFalse(due.exists, "no options until writing")
        let quiet = XCTAttachment(screenshot: app.screenshot()); quiet.name = "quiet"; quiet.lifetime = .keepAlways; add(quiet)

        field.tap()
        XCTAssertTrue(due.waitForExistence(timeout: 5), "the options appear while writing")
        field.typeText("Call Maya's parents")
        let open = XCTAttachment(screenshot: app.screenshot()); open.name = "writing"; open.lifetime = .keepAlways; add(open)
        field.typeText("\n")
        let row = app.staticTexts["Call Maya's parents"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "saved")
        XCTAssertFalse(due.waitForExistence(timeout: 2), "the options fold away")
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "saved"; saved.lifetime = .keepAlways; add(saved)

        // Clean up the demo store — also what earlier failed runs left.
        let delete = app.buttons["Delete"].firstMatch
        let rows = app.descendants(matching: .any).matching(identifier: "reminders.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Call Maya"))
        for _ in 0..<8 where rows.firstMatch.exists {
            let target = rows.firstMatch
            if !target.isHittable { app.swipeUp() }
            target.press(forDuration: 1.6)
            if delete.waitForExistence(timeout: 4) { delete.tap() } else { app.tap() }
            _ = row.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(row.waitForExistence(timeout: 3))
    }
}
