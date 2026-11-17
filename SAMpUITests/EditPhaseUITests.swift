import XCTest

/// Program page → Manage → a phase → Edit Phase → rename → Save, and the
/// phase page shows the new name (18 Nov 2026, Luther: tapping a phase in
/// Manage Phases showed nothing to modify). Puts the name back after.
final class EditPhaseUITests: XCTestCase {
    func testAPhaseCanBeEditedFromManagePhases() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_SHOT"] = "programDetail"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let manage = app.buttons["program.managePhases"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let firstPhase = app.cells.firstMatch
        XCTAssertTrue(firstPhase.waitForExistence(timeout: 8))
        firstPhase.tap()

        let edit = app.buttons["phase.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), "the phase page offers Edit Phase")
        edit.tap()
        let field = app.textFields["phase.edit.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = (field.value as? String) ?? ""
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("UITest phase")
        app.buttons["phase.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["UITest phase"].firstMatch.waitForExistence(timeout: 5), "the page shows the new name")

        // Put it back.
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText(original)
        app.buttons["phase.edit.save"].tap()
    }

    /// Edit Phase → Add a recurring drill → pick one → every upcoming session
    /// → Add; then the drill is listed and Remove takes it out again.
    func testARecurringDrillGoesInAndComesOut() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "programDetail"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["program.managePhases"].waitForExistence(timeout: 30))
        app.buttons["program.managePhases"].tap()
        // Find a phase that still has upcoming sessions.
        let phases = app.cells
        XCTAssertTrue(phases.firstMatch.waitForExistence(timeout: 8))
        let add = app.buttons["phase.drill.add"]
        var found = false
        for i in 0..<phases.count {
            phases.element(boundBy: i).tap()
            XCTAssertTrue(app.buttons["phase.edit"].waitForExistence(timeout: 8))
            app.buttons["phase.edit"].tap()
            // The section sits under Focus: scroll the form to it.
            for _ in 0..<4 where !add.exists { app.swipeUp() }
            if add.waitForExistence(timeout: 2) { found = true; break }
            app.buttons["Cancel"].firstMatch.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(phases.firstMatch.waitForExistence(timeout: 8))
        }
        guard found else { throw XCTSkip("No phase has upcoming sessions in the demo store") }
        let before = app.buttons.matching(identifier: "phase.drill.remove").count
        add.tap()
        let pickAdd = app.buttons["drillPicker.add"].firstMatch
        XCTAssertTrue(pickAdd.waitForExistence(timeout: 10), "the drill library opens to pick from")
        pickAdd.tap()
        let apply = app.buttons["phase.chooser.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 8), "the session chooser opens")
        apply.tap()
        let rows = app.buttons.matching(identifier: "phase.drill.remove")
        let deadline = Date().addingTimeInterval(6)
        while rows.count <= before, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertGreaterThan(rows.count, before, "the recurring drill is listed")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "drills in this phase"
        shot.lifetime = .keepAlways
        self.add(shot)

        // Take it out again: it was added at the end of the plans, so it is
        // in every upcoming session — the first row now.
        if !rows.firstMatch.isHittable { app.swipeDown() }
        rows.firstMatch.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 8))
        apply.tap()
        let back = Date().addingTimeInterval(6)
        while rows.count > before, Date() < back { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(rows.count, before, "removed from every session again")
    }
}
