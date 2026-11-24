import XCTest

/// The Mac's film room (25 Nov 2026): a sidebar over glass instead of the tab
/// bar. The DEBUG flag HOOPWISE_FILM_ROOM=1 shows the same shell and layer
/// code on the iPad simulator in landscape (the glass itself is the Mac's).
/// Demo store. Small tests on purpose: the simulator is shared and slow.
final class FilmRoomUITests: XCTestCase {
    private func shot(_ name: String) {
        // The whole screen: an app screenshot comes back cut in landscape.
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launch() throws -> XCUIApplication {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the shell is a wide-window layout")
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_FILM_ROOM"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "filmRoom.sidebar").firstMatch
        if !sidebar.waitForExistence(timeout: 20) { app.terminate(); app.launch() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 20), "the sidebar replaces the tab bar")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        return app
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func go(_ app: XCUIApplication, _ place: Int) {
        let row = app.buttons["filmRoom.place.\(place)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(2)
    }

    func testA_EveryPlace() throws {
        let app = try launch()
        XCTAssertFalse(app.tabBars.firstMatch.exists, "no tab bar in the film room")
        shot("0 home")
        let names = ["1 sessions", "2 athletes", "3 revenue", "4 plays", "5 drills", "6 lexicon", "7 teams", "8 organization"]
        for (i, name) in names.enumerated() {
            go(app, i + 1)
            XCTAssertTrue(app.buttons["filmRoom.place.\(i + 1)"].isSelected, "\(name) is the place on screen")
            shot(name)
        }
        XCTAssertTrue(app.buttons["filmRoom.board"].exists, "the board opens in its own window")
    }

    /// A class opens as a workspace — the plan beside the roster — whether it
    /// comes from the calendar or from the sidebar's clipboard.
    func testB_ClassWorkspace() throws {
        let app = try launch()
        go(app, 1)
        // The calendar's row (the sidebar may list the same class).
        let rows = app.staticTexts.matching(NSPredicate(format: "label == %@", "Hoopwise Hawks Practice"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 6), "the demo class is on today's calendar")
        rows.element(boundBy: rows.count - 1).tap()
        let workspace = app.descendants(matching: .any).matching(identifier: "session.workspace").firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8), "the class opens as a workspace in the window")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "session.workspace.roster").firstMatch.exists)
        sleep(1); shot("B1 workspace plan")
        app.buttons["session.workspace.tab.2"].tap(); sleep(1); shot("B2 workspace games")
        app.buttons["session.workspace.tab.3"].tap(); sleep(1); shot("B3 workspace notes")
    }

    func testC_AthleteAndDrill() throws {
        let app = try launch()
        go(app, 2)
        let athlete = app.buttons.matching(identifier: "athletes.row").firstMatch
        XCTAssertTrue(athlete.waitForExistence(timeout: 6))
        athlete.tap(); sleep(2)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "athlete.macHeader").firstMatch.exists,
                      "the Mac profile opens on the glass header, not the trading card")
        shot("C1 athlete")
        go(app, 5)
        let drill = app.buttons.matching(identifier: "library.tracked").firstMatch
        if drill.waitForExistence(timeout: 5) { drill.tap(); sleep(2); shot("C2 drill page") }
        go(app, 7)
        let team = app.buttons.matching(identifier: "teams.row").firstMatch
        if team.waitForExistence(timeout: 5) { team.tap(); sleep(2); shot("C3 team page") }
        go(app, 4)
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plays.row.'")).firstMatch
        if play.waitForExistence(timeout: 5) { play.tap(); sleep(2); shot("C4 play page") }
    }

    func testD_PopupAndProgram() throws {
        let app = try launch()
        go(app, 1)
        let add = app.buttons["Add Session"].firstMatch
        if add.waitForExistence(timeout: 5) {
            add.tap(); sleep(2); shot("D1 add session popup")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap(); sleep(1) }
        }
        let programs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Programs'")).firstMatch
        if programs.waitForExistence(timeout: 4) {
            programs.tap(); sleep(2); shot("D2 programs")
            let program = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Elite'")).firstMatch
            if program.waitForExistence(timeout: 4) { program.tap(); sleep(2); shot("D3 program page") }
        }
    }

    /// A play dragged onto a class in the sidebar joins its plan. Needs a
    /// class that can still be planned (the demo store's is in the past by
    /// night): skipped when the clipboard is empty.
    func testE_DragOntoAClass() throws {
        let app = try launch()
        let target = app.buttons["filmRoom.today"].firstMatch
        try XCTSkipUnless(target.waitForExistence(timeout: 4), "no upcoming class in the demo store right now")
        go(app, 4)
        let playRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plays.row.'")).firstMatch
        XCTAssertTrue(playRow.waitForExistence(timeout: 5), "a play to drag")
        playRow.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(app.staticTexts.matching(identifier: "filmRoom.dropNote").firstMatch.waitForExistence(timeout: 3),
                      "the drop says what it did")
        shot("E1 dropped on a class")
    }
}
