import XCTest

/// The game setup page as slots (20 Nov 2026, Luther): a format 2v2–5v5,
/// each team's starters then bench as photo slots, the roster as a grid —
/// drag and drop everywhere, a tap on a player for options.
final class CreateGameSlotsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "createGame"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testFormatSlotsDragAndTap() {
        XCTAssertTrue(app.buttons["3v3"].waitForExistence(timeout: 20), "no format picker")
        app.buttons["3v3"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All'")).firstMatch.tap()

        app.swipeUp()
        let rosterPlayer = app.buttons.matching(identifier: "setup.roster.player").firstMatch
        XCTAssertTrue(rosterPlayer.waitForExistence(timeout: 5), "the roster shows players")
        let rosterBefore = app.buttons.matching(identifier: "setup.roster.player").count
        attach("before")

        // Drag a roster player onto Black's second starter slot.
        let target = any("setup.slot.0.1")
        XCTAssertTrue(target.exists)
        rosterPlayer.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(1)
        XCTAssertEqual(app.buttons.matching(identifier: "setup.roster.player").count, rosterBefore - 1, "dropped onto the team")
        XCTAssertTrue(app.staticTexts["2/3 starters · 0 bench"].waitForExistence(timeout: 3), "Black has two starters")
        attach("dragged")

        // Tap the player: options, move him to the bench.
        any("setup.slot.0.1").tap()
        let bench = app.buttons["Move to the bench"]
        XCTAssertTrue(bench.waitForExistence(timeout: 3), "tap shows options")
        attach("menu")
        bench.tap()
        XCTAssertTrue(app.staticTexts["1/3 starters · 1 bench"].waitForExistence(timeout: 3), "now on the bench")

        // Drag him back to the roster.
        any("setup.slot.0.3").press(forDuration: 1.0, thenDragTo: rosterPlayer, withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(1)
        XCTAssertEqual(app.buttons.matching(identifier: "setup.roster.player").count, rosterBefore, "back in the roster")
        attach("after")
    }
}
