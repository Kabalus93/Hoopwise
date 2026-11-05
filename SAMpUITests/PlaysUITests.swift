import XCTest

/// Hub → Plays (HoopWise Journal's Plays tab, November 2026) clicks through:
/// the library opens a play, the play opens its steps and a wrinkle, and the
/// pencil opens the step editor. Luther found the first port inert — a
/// play row did nothing — so this runs the real taps. Isolated demo store.
final class PlaysUITests: XCTestCase {

    func testPlaysClickThrough() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()

        let hub = app.buttons["Hub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 30))
        hub.tap()

        let plays = app.buttons["hub.plays"].firstMatch
        XCTAssertTrue(plays.waitForExistence(timeout: 10))
        plays.tap()

        // A library emptied earlier offers the starters back (the Journal's
        // empty state) — that is part of the feature too.
        let addStarters = app.buttons["Add the starter plays"].firstMatch
        if addStarters.waitForExistence(timeout: 3) {
            addStarters.tap()
            app.buttons["OK"].firstMatch.tap()
        }

        let horns = app.buttons["plays.row.horns"].firstMatch
        if !horns.waitForExistence(timeout: 10) { print("HIERARCHY\n" + app.debugDescription) }
        XCTAssertTrue(horns.exists, "the starter plays are not in the library")
        horns.tap()

        let hero = app.buttons["plays.hero"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "the play did not open")
        hero.tap()

        let step = app.staticTexts["Step 1 of 3"].firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 10), "the concept's steps did not open")
        app.buttons["Next step"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Draw this step"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Erase"].firstMatch.waitForExistence(timeout: 5), "the step editor did not open")
        app.buttons["Cancel"].firstMatch.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let wrinkle = app.buttons["plays.part.wrinkle.0"].firstMatch
        XCTAssertTrue(wrinkle.waitForExistence(timeout: 10))
        wrinkle.tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].firstMatch.waitForExistence(timeout: 10), "the wrinkle did not open")
    }

    /// The other Hub cards open too: a glassEffect inside each card's label
    /// swallowed every tap (League, Coach and Organization never opened).
    func testHubCardsOpen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        let hub = app.buttons["Hub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 30))
        hub.tap()
        for prefix in ["Coach", "Organization"] {
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            let back = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "\(prefix) did not open")
            back.tap()
        }
    }
}
