import XCTest

/// The October 2026 live-entry screen: one team, every player on screen,
/// tap a row to score, drag to a teammate for the assist, Undo reverses.
final class LiveGameAssistUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "liveGame"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en"]
        app.launch()
    }

    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "live.row") }
    private var last: XCUIElement { app.staticTexts["live.last"] }

    func testAllFivePlayersAreOnScreenWithoutScrolling() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(rows.count, 5)
        for i in 0..<5 { XCTAssertTrue(rows.element(boundBy: i).isHittable, "row \(i) must be visible") }
    }

    func testDragToTeammateCreditsTheAssistAndUndoReversesIt() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        let scorer = rows.element(boundBy: 0), passer = rows.element(boundBy: 2)
        scorer.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: passer.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
        XCTAssertTrue(last.label.hasPrefix("+2 "), last.label)
        XCTAssertTrue(last.label.contains("assist"), "drag onto a teammate = assist: \(last.label)")

        app.buttons["live.undo"].tap()
        XCTAssertTrue(last.label.hasPrefix("Tap a player"), "Undo leaves nothing logged: \(last.label)")
    }

    func testTapScoresWithoutAssistAndValueResetsToTwo() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        app.buttons["live.value.3"].tap()
        rows.element(boundBy: 1).tap()
        XCTAssertTrue(last.label.hasPrefix("+3 "), last.label)
        XCTAssertFalse(last.label.contains("assist"))
        rows.element(boundBy: 1).tap()
        XCTAssertTrue(last.label.hasPrefix("+2 "), "the value goes back to 2 after a basket: \(last.label)")
    }

    func testSwitchingTeamShowsTheOtherFive() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        let before = rows.element(boundBy: 0).label
        app.buttons["live.team.1"].tap()
        let switched = NSPredicate(format: "label != %@", before)
        expectation(for: switched, evaluatedWith: rows.element(boundBy: 0))
        waitForExpectations(timeout: 5)
        XCTAssertEqual(rows.count, 5)
    }
}
