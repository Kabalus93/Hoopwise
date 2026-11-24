import XCTest

/// Game day (23 Nov 2026): the team page schedules and plans a game; the
/// game is a session whose Plan shows the plan and whose Games tab plays it
/// against the opponent's score. Demo store; the team and its game are
/// deleted at the end (and at the start, after a failed run).
final class GameDayUITests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_SHOT"] = "teams"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        // The first launch of a run can come up without its environment.
        if !app.buttons["teams.new"].waitForExistence(timeout: 12) {
            app.terminate()
            app.launch()
        }
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Removes the test team and its game.
    private func cleanUp(_ app: XCUIApplication) {
        let rows = app.buttons.matching(identifier: "teams.row").matching(NSPredicate(format: "label CONTAINS 'UITest Gamers'"))
        while rows.firstMatch.waitForExistence(timeout: 3) {
            rows.firstMatch.tap()
            let plan = app.buttons["team.gameDay.plan"]
            while plan.waitForExistence(timeout: 3) {
                for _ in 0..<3 where !plan.isHittable { app.swipeUp() }
                plan.tap()
                let delete = app.buttons["gameDay.delete"]
                for _ in 0..<6 where !delete.exists || !delete.isHittable { app.swipeUp() }
                delete.tap()
                app.buttons["Delete"].firstMatch.tap()
                sleep(1)
            }
            app.buttons["team.menu"].tap()
            app.buttons["Delete Team"].tap()
            app.alerts.buttons["Delete"].tap()
            _ = app.buttons["teams.new"].waitForExistence(timeout: 5)
        }
    }

    func testAGameIsScheduledPlannedAndPlayed() {
        continueAfterFailure = false
        var app = launch()
        XCTAssertTrue(app.buttons["teams.new"].waitForExistence(timeout: 20))
        cleanUp(app)

        app.buttons["teams.new"].tap()
        let name = app.textFields["team.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("UITest Gamers")
        app.buttons["team.form.save"].tap()
        let row = app.buttons.matching(identifier: "teams.row").matching(NSPredicate(format: "label CONTAINS 'UITest Gamers'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["team.addPlayers"].tap()
        XCTAssertTrue(app.staticTexts["Maya Chen"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Maya Chen"].firstMatch.tap()
        app.staticTexts["Leo Martin"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ('")).firstMatch.tap()

        // Schedule and plan.
        let schedule = app.buttons["team.gameDay.schedule"]
        for _ in 0..<4 where !schedule.exists || !schedule.isHittable { app.swipeUp() }
        XCTAssertTrue(schedule.waitForExistence(timeout: 5), "the team page has a Game day block")
        schedule.tap()
        let opponent = app.textFields["gameDay.opponent"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))
        opponent.tap(); opponent.typeText("Tigers\n")
        let players = app.buttons.matching(identifier: "gameDay.player")
        XCTAssertEqual(players.count, 2, "the team's athletes")
        players.element(boundBy: 0).tap()
        XCTAssertTrue(players.element(boundBy: 0).label.contains("Starter 1"), players.element(boundBy: 0).label)
        // Rotation, defense and a matchup (24 Nov 2026).
        func reach(_ id: String) -> XCUIElement {
            let e = any(app, id)
            for _ in 0..<8 where !e.exists || !e.isHittable { app.swipeUp(velocity: .slow) }
            return e
        }
        reach("gameDay.addSub").tap()
        let when = reach("gameDay.sub.when")
        when.tap(); when.typeText("Mid first half\n")
        reach("gameDay.defense").tap()
        app.buttons["2-3 zone"].firstMatch.tap()
        let key = reach("gameDay.key")
        key.tap(); key.typeText("Box out on every shot")
        reach("gameDay.addThreat").tap()
        let number = reach("gameDay.threat.number")
        number.tap(); number.typeText("7")
        let note = any(app, "gameDay.threat.note")
        note.tap(); note.typeText("Left hand")
        attach(app, "schedule sheet")
        app.buttons["gameDay.save"].tap()

        let next = any(app, "team.gameDay.next")
        XCTAssertTrue(next.waitForExistence(timeout: 5), "the next game shows on the team page")
        XCTAssertTrue(app.staticTexts["vs Tigers"].firstMatch.exists)
        attach(app, "team page")

        // The game is a session: its plan on the Plan tab.
        app.buttons["team.gameDay.open"].tap()
        let card = any(app, "gameDay.planCard")
        XCTAssertTrue(card.waitForExistence(timeout: 8), "the session opens on the game plan")
        XCTAssertTrue(app.staticTexts["Box out on every shot"].firstMatch.exists)
        attach(app, "session plan")
        // The page is about the game: lineup and rotation, the defense, the
        // matchup — and none of a training plan's cards.
        XCTAssertTrue(any(app, "game.lineup").exists, "lineup and rotation")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'comes in'")).firstMatch.exists,
                      "the planned sub")
        XCTAssertTrue(app.staticTexts["Mid first half"].firstMatch.exists)
        XCTAssertTrue(any(app, "game.threat").exists, "their player")
        XCTAssertTrue(any(app, "game.calls.defense").label.contains("2-3 zone"), any(app, "game.calls.defense").label)
        XCTAssertFalse(app.staticTexts["PLAN BALANCE"].exists)
        XCTAssertFalse(app.staticTexts["SKILLS"].exists)
        for _ in 0..<3 where !app.staticTexts["PRE-GAME WARM-UP"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["PRE-GAME WARM-UP"].exists)
        attach(app, "session plan lower")
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["gameDay.sheet"].firstMatch.tap()
        XCTAssertTrue(any(app, "gameSheet.preview").waitForExistence(timeout: 8), "the game sheet")
        XCTAssertTrue(app.buttons["gameSheet.pdf"].exists)
        attach(app, "game sheet")
        app.buttons["Done"].firstMatch.tap()

        // Played against the opponent's score.
        app.buttons["Games"].firstMatch.tap()
        let start = app.buttons.matching(NSPredicate(format: "label == 'Start the game'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let plus2 = app.buttons["live.opponent.add.2"]
        XCTAssertTrue(plus2.waitForExistence(timeout: 8), "the opponent has a score pad")
        plus2.tap()
        app.buttons["live.opponent.add.3"].tap()
        XCTAssertEqual(any(app, "live.opponent.score").label, "5")
        attach(app, "live game")

        // Clean up from a fresh launch (the live screen is a cover).
        app.terminate()
        app = launch()
        XCTAssertTrue(app.buttons["teams.new"].waitForExistence(timeout: 20))
        cleanUp(app)
    }
}
