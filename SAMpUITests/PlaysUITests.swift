import XCTest

/// Hub → Plays (HoopWise Journal's Plays tab, November 2026) clicks through:
/// the library opens a play, the play plays its concept in place, the
/// pencil opens the step editor, and a wrinkle opens playing. Luther found the first port inert — a
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

        // The play page plays its concept in place (Luther, November 2026:
        // the hero's ▶ used to open a second screen where ▶ then played).
        let step = app.staticTexts["Step 1 of 3"].firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 10), "the play page does not show the concept's steps")
        app.buttons["Next step"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["plays.player.play"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 3), "Play did not play in place")
        XCTAssertTrue(app.buttons["plays.part.wrinkle.0"].firstMatch.exists, "Play left the play page")
        app.buttons["plays.player.play"].firstMatch.tap()

        app.buttons["Draw this step"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Erase"].firstMatch.waitForExistence(timeout: 5), "the step editor did not open")
        app.buttons["Cancel"].firstMatch.tap()

        // A wrinkle opens already playing.
        let wrinkle = app.buttons["plays.part.wrinkle.0"].firstMatch
        XCTAssertTrue(wrinkle.waitForExistence(timeout: 10))
        wrinkle.tap()
        let ofTwo = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "of 2")).firstMatch
        XCTAssertTrue(ofTwo.waitForExistence(timeout: 10), "the wrinkle did not open")
        XCTAssertTrue(app.buttons["Pause"].firstMatch.exists, "the wrinkle did not start playing")
    }

    /// A finger still swipes between steps across the court: the Pencil ink
    /// layer over it (PlayInkLayer, 16 Nov 2026) draws with the Pencil only.
    func testFingerSwipeStillPagesUnderTheInkLayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        let hub = app.buttons["Hub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 30))
        hub.tap()
        app.buttons["hub.plays"].firstMatch.tap()
        let addStarters = app.buttons["Add the starter plays"].firstMatch
        if addStarters.waitForExistence(timeout: 3) {
            addStarters.tap()
            app.buttons["OK"].firstMatch.tap()
        }
        let horns = app.buttons["plays.row.horns"].firstMatch
        XCTAssertTrue(horns.waitForExistence(timeout: 10))
        horns.tap()
        let step = app.staticTexts["Step 1 of 3"].firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 10))
        // The court sits under the "Step 1 of 3" line.
        let window = app.windows.firstMatch
        let below = step.frame.maxY + 160
        let start = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width * 0.8, dy: below))
        let end = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width * 0.2, dy: below))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].firstMatch.waitForExistence(timeout: 5),
                      "a finger swipe across the court no longer pages")
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
        for prefix in ["Drills", "Organization"] {
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            let back = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "\(prefix) did not open")
            back.tap()
        }
    }
}
