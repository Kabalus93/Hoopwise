import XCTest

/// Who is up (19 Nov 2026, Luther): with a third team waiting, tapping a
/// team on the scoreboard before the round starts swaps a waiting team in;
/// once the clock has run, the scoreboard no longer offers it.
final class LiveGameLineupUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "liveGame"
        app.launchEnvironment["HOOPWISE_LIVE_TEAMS"] = "3"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en"]
        app.launch()
    }

    private func team(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "live.team.\(index)").firstMatch
    }

    func testAWaitingTeamCanBePutOnBeforeTheRoundStarts() {
        XCTAssertTrue(team(1).waitForExistence(timeout: 20), "no scoreboard")
        XCTAssertTrue(team(1).label.contains("White"), team(1).label)
        team(1).tap()
        let yellow = app.buttons["Yellow"]
        XCTAssertTrue(yellow.waitForExistence(timeout: 5), "the menu offers the waiting team")
        let menu = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: menu); shot.lifetime = .keepAlways; add(shot)
        yellow.tap()
        XCTAssertTrue(team(1).label.contains("Yellow"), "Yellow is on court: \(team(1).label)")
        XCTAssertTrue(app.staticTexts["White"].waitForExistence(timeout: 3), "White now waits")

        // Start the clock: the round is under way, no more swapping.
        app.buttons["Start timer"].tap()
        sleep(2)
        app.buttons["Pause timer"].tap()
        team(0).tap()
        XCTAssertFalse(app.buttons["White"].waitForExistence(timeout: 2), "no swap once the clock has run")
    }
}
