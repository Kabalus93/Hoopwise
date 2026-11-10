import XCTest

/// Hub → Teams: create a team, add an athlete and a coach, put a play in its
/// base offense, see it all on the team page, delete the team. Demo store.
final class TeamsUITests: XCTestCase {

    func testATeamHoldsItsRosterAndItsPlays() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "teams"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let new = app.buttons["teams.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 20))
        // A team left by an earlier, failed run.
        let stale = app.buttons.matching(identifier: "teams.row").matching(NSPredicate(format: "label CONTAINS 'UITest Ballers'"))
        while stale.firstMatch.exists {
            stale.firstMatch.tap()
            XCTAssertTrue(app.buttons["team.menu"].waitForExistence(timeout: 5))
            app.buttons["team.menu"].tap()
            app.buttons["Delete Team"].tap()
            app.alerts.buttons["Delete"].tap()
            _ = new.waitForExistence(timeout: 5)
        }
        new.tap()
        let name = app.textFields["team.form.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UITest Ballers")
        app.buttons["team.form.save"].tap()

        let row = app.buttons.matching(identifier: "teams.row").matching(NSPredicate(format: "label CONTAINS 'UITest Ballers'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the team is listed")
        row.tap()

        // An athlete and a coach.
        let addPlayers = app.buttons["team.addPlayers"]
        XCTAssertTrue(addPlayers.waitForExistence(timeout: 5))
        addPlayers.tap()
        XCTAssertTrue(app.staticTexts["Coaches"].waitForExistence(timeout: 5), "coaches are offered too")
        app.staticTexts["Coach"].firstMatch.tap()
        app.staticTexts["Maya Chen"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ('")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "team.athlete").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "team.coach").firstMatch.exists)

        // A play in the base offense, through "Add a section".
        app.buttons["team.addSection"].tap()
        app.buttons["Base offense"].firstMatch.tap()
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan.plays.pick.'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        app.buttons["plan.plays.done"].tap()
        let section = app.buttons["team.section.baseOffense"]
        XCTAssertTrue(section.waitForExistence(timeout: 5), "the section is a tile on the team page")
        attach(app, "team page")

        // Break the play down: role 1 needs shooting, a drill, and Maya.
        section.tap()
        let play = app.buttons["team.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let start = app.buttons["breakdown.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let role = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'breakdown.role.'")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 5), "roles come from the play's numbers")
        attach(app, "breakdown")
        role.tap()
        XCTAssertTrue(app.buttons["Shooting"].waitForExistence(timeout: 5))
        app.buttons["Shooting"].tap()
        app.buttons["role.addDrills"].tap()
        let drill = app.buttons["drillPick.row"].firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 5))
        drill.tap()
        app.buttons["drillPick.done"].tap()
        let maya = app.buttons.matching(identifier: "role.player").matching(NSPredicate(format: "label CONTAINS 'Maya'")).firstMatch
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap()
        attach(app, "role")
        app.buttons["role.save"].tap()

        // Back on the team page: the standard and Maya's workout.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["team.standards"].waitForExistence(timeout: 5), "the system's demands add up")
        let workout = app.buttons.matching(identifier: "team.workout").matching(NSPredicate(format: "label CONTAINS '1 drills'")).firstMatch
        XCTAssertTrue(workout.exists, "Maya's workout has the drill")
        attach(app, "team page with standards")

        // Leave the demo store as it was.
        app.buttons["team.menu"].tap()
        app.buttons["Delete Team"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 3), "the team is gone")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
