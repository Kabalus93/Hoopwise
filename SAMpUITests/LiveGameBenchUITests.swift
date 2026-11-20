import XCTest

/// Starters on the floor, subs from the bench, and Next Game (20 Nov 2026,
/// Luther): the live screen shows only who is playing; a bench player comes
/// on by a drag onto a floor player or a tap ("in for…"); Next Game finishes
/// this game and opens the next with the same teams — choosing who plays
/// when more than two teams are waiting.
final class LiveGameBenchUITests: XCTestCase {

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "liveGame"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        env.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testOnlyStartersPlayAndTheBenchSubsIn() {
        let app = launch(["HOOPWISE_LIVE_BENCH": "1"])
        let rows = app.descendants(matching: .any).matching(identifier: "live.row")
        let bench = app.descendants(matching: .any).matching(identifier: "live.bench.player")
        XCTAssertTrue(bench.firstMatch.waitForExistence(timeout: 20), "no bench")
        // The demo roster can arrive a moment after the screen.
        let four = expectation(for: NSPredicate(format: "count == 4"), evaluatedWith: bench)
        wait(for: [four], timeout: 10)
        attach("bench")
        XCTAssertEqual(rows.count, 6, "three on the floor per team")
        XCTAssertEqual(bench.count, 4, "two on each bench")

        // Tap: in for whom?
        let benchName = bench.firstMatch.label
        bench.firstMatch.tap()
        let out = app.buttons.matching(identifier: "live.sub.out").firstMatch
        XCTAssertTrue(out.waitForExistence(timeout: 3), "the tap asks who comes off")
        attach("chooser")
        out.tap()
        sleep(1)
        XCTAssertFalse(bench.allElementsBoundByIndex.contains { $0.label == benchName }, "he is on the floor now")
        XCTAssertEqual(rows.count, 6)

        // Drag: onto a floor row.
        let second = bench.element(boundBy: 1)
        let draggedName = second.label
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: rows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
        sleep(1)
        XCTAssertFalse(bench.allElementsBoundByIndex.contains { $0.label == draggedName }, "dragged on")
        XCTAssertEqual(bench.count, 4)
        attach("subbed")
    }

    func testNextGameWithTwoTeamsOpensTheNextOne() {
        let app = launch(["HOOPWISE_LIVE_BENCH": "1"])
        let next = app.buttons["live.nextGame"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        next.tap()
        XCTAssertTrue(app.staticTexts["Game 2"].waitForExistence(timeout: 5), "the next game is open")
        attach("game2")
    }

    func testNextGameWithThreeTeamsAsksWhoPlays() {
        let app = launch(["HOOPWISE_LIVE_TEAMS": "3", "HOOPWISE_LIVE_BENCH": "1"])
        let next = app.buttons["live.nextGame"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        next.tap()
        let teams = app.buttons.matching(identifier: "live.next.team")
        XCTAssertTrue(teams.firstMatch.waitForExistence(timeout: 3), "asks who plays next")
        XCTAssertEqual(teams.count, 3)
        attach("chooser")
        app.buttons["live.next.start"].tap()
        XCTAssertTrue(app.staticTexts["Game 2"].waitForExistence(timeout: 5), "the next game is open")
        XCTAssertTrue(app.staticTexts["Yellow"].exists || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Yellow'")).count > 0,
                      "the waiting team plays")
        attach("game2")
    }
}
