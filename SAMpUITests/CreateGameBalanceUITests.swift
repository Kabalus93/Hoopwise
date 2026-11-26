import XCTest

/// Create Game: an octagon per team and "Balance teams" (26 Nov 2026,
/// Luther: "give each team an oct diagram to see the balance live … a button
/// that balances the teams based on data").
final class CreateGameBalanceUITests: XCTestCase {

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

    func testEachTeamHasAnOctagonAndBalanceSplitsEveryone() {
        let pool = app.buttons["setup.pool"]
        XCTAssertTrue(pool.waitForExistence(timeout: 20), "no players chip")
        pool.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All'")).firstMatch.tap()

        XCTAssertTrue(any("setup.team.0.octagon").waitForExistence(timeout: 5), "Black has its octagon")
        XCTAssertTrue(any("setup.team.1.octagon").exists, "White has its octagon")

        let roster = app.buttons.matching(identifier: "setup.roster.player")
        XCTAssertTrue(roster.firstMatch.waitForExistence(timeout: 5), "the others wait in the roster")
        attach("before")

        let balance = app.buttons["setup.balance"]
        XCTAssertTrue(balance.exists, "no Balance teams button")
        balance.tap()
        sleep(1)
        XCTAssertEqual(roster.count, 0, "everyone is on a team")
        XCTAssertTrue(app.buttons["setup.balance.undo"].waitForExistence(timeout: 3), "the split can be undone")
        attach("balanced")

        app.buttons["setup.balance.undo"].tap()
        XCTAssertTrue(roster.firstMatch.waitForExistence(timeout: 3), "undo puts them back in the roster")
        XCTAssertFalse(app.buttons["setup.balance.undo"].exists)
    }
}
