import XCTest

/// Hub → Organization, redesigned November 2026: one grouped page (coaches,
/// venues, schools, age categories, share & import) with one search.
/// Demo store only.
final class OrganizationUITests: XCTestCase {

    func testOnePageWithOneSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "organization"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["Add Coach"].waitForExistence(timeout: 20), "coaches are on the page")
        XCTAssertTrue(app.buttons["Add Venue"].exists, "so are venues")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "no tabs any more")

        // Share & import is at the end of the page.
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Share organization data'")).firstMatch
        for _ in 0..<8 where !share.exists { app.swipeUp() }
        XCTAssertTrue(share.exists, "share is on the page")

        // One search finds a venue and leaves out the rest.
        let search = app.searchFields.firstMatch
        for _ in 0..<8 where !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("Main")
        XCTAssertTrue(app.staticTexts["Main Court"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Coach"].exists, "searching shows matches only")
    }
}
