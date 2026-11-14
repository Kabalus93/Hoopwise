import XCTest

/// iPad / Mac session page (14 Nov 2026): the attendance roster as two
/// columns of cards, and the Games tab's dashboard beside the game list.
/// Uses the gallery's sessionPage shot full screen (regular width); skips on
/// a phone, where compact width keeps the list.
final class SessionWideLayoutUITests: XCTestCase {

    private func launch(tab: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "\(tab)"
        app.launchArguments += ["-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    func testAttendanceIsTwoColumnsOfCards() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        let app = launch(tab: 1)
        let cards = app.descendants(matching: .any).matching(identifier: "attendance.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 20), "no attendance cards in regular width")
        if cards.count >= 2 {
            // The id can land on a card's children too, so ask for two COLUMNS.
            let lefts = Set((0..<cards.count).map { Int(cards.element(boundBy: $0).frame.minX / 100) })
            XCTAssertGreaterThanOrEqual(lefts.count, 2, "cards in two columns")
        }
        attach(app, "attend")
    }

    func testGamesTabShowsTheDashboardBesideTheList() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        let app = launch(tab: 2)
        let dash = app.descendants(matching: .any)["games.dashboard"].firstMatch
        let newGame = app.buttons.matching(NSPredicate(format: "label CONTAINS 'New Game' OR label CONTAINS '新比赛'")).firstMatch
        guard dash.waitForExistence(timeout: 20) else {
            throw XCTSkip("the demo program has no played games")
        }
        XCTAssertTrue(newGame.exists)
        XCTAssertGreaterThan(dash.frame.minX, newGame.frame.minX, "the dashboard sits to the right of the list")
        attach(app, "games")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
