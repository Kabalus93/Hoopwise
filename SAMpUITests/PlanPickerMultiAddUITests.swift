import XCTest

/// The plan's + opens the library at once, several drills can be added
/// before Done, and a drill's page has an add-to-session button
/// (23 Nov 2026). Everything added here is taken back, so the demo plan
/// is left as it was.
final class PlanPickerMultiAddUITests: XCTestCase {
    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testPlusOpensTheLibraryAndSeveralDrillsAreAdded() {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "0"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let plus = app.buttons["plan.add.warmup"]
        for _ in 0..<6 where !plus.exists || !plus.isHittable { app.swipeUp() }
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let done = app.buttons["drillPicker.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "the library opens straight away")
        XCTAssertFalse(app.buttons["From Library"].exists)
        XCTAssertEqual(done.label, "Done")

        let toAdd = app.buttons.matching(NSPredicate(format: "label == 'Add'"))
        XCTAssertTrue(toAdd.firstMatch.waitForExistence(timeout: 10), "rows with an add button")
        XCTAssertGreaterThan(toAdd.count, 2)
        toAdd.element(boundBy: 0).tap()
        XCTAssertTrue(done.exists, "the library stays open after an add")
        toAdd.element(boundBy: 0).tap()   // the next one still to add
        XCTAssertTrue(app.buttons["Done · 2 added"].waitForExistence(timeout: 5))
        attach("two added")

        // The drill's page: add to the session beside Edit and Favourite.
        let row = app.buttons.matching(NSPredicate(format: "label == 'Add'")).element(boundBy: 0)
        row.coordinate(withNormalizedOffset: CGVector(dx: -6, dy: 0.5)).tap()
        let add = app.buttons["drill.addToSession"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "the drill page offers add to session")
        XCTAssertEqual(add.label, "Add to session")
        add.tap()
        XCTAssertEqual(add.label, "In the session")
        attach("drill page")
        add.tap()   // take it back
        XCTAssertEqual(add.label, "Add to session")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Take the two back: a second tap on what was added in this visit.
        let added = app.buttons.matching(NSPredicate(format: "label == 'Added' AND enabled == true"))
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(added.count, 2)
        added.element(boundBy: 0).tap()
        added.element(boundBy: 0).tap()
        XCTAssertEqual(done.label, "Done")
        done.tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
    }
}
