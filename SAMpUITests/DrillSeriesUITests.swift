import XCTest

/// Drill series (18 Nov 2026, Luther), in order: create a series with two
/// levels on the drills page; spread it over a phase from Edit Phase (and
/// take its drills out again); delete it. Demo store only.
final class DrillSeriesUITests: XCTestCase {
    static let name = "UITest series"

    private func launch(_ shot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_SHOT"] = shot
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        self.add(shot)
    }

    func testA_CreateASeriesWithTwoLevels() {
        continueAfterFailure = false
        let app = launch("drillsLibrary")
        let entry = app.buttons["library.series"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the drills page has a Series row")
        entry.tap()
        app.buttons["series.new"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.name)
        app.alerts.buttons["Create"].tap()

        let addLevel = app.buttons["series.addLevel"]
        XCTAssertTrue(addLevel.waitForExistence(timeout: 8), "the new series opens")
        for i in 0..<2 {
            addLevel.tap()
            let pick = app.buttons.matching(identifier: "drillPicker.add").element(boundBy: i)
            XCTAssertTrue(pick.waitForExistence(timeout: 10))
            pick.tap()
            XCTAssertTrue(addLevel.waitForExistence(timeout: 8))
        }
        let levels = app.descendants(matching: .any).matching(identifier: "series.level")
        XCTAssertEqual(levels.count, 2, "two levels, easiest first")
        attach(app, "series page")
    }

    func testB_SpreadTheSeriesOverAPhase() throws {
        continueAfterFailure = false
        let app = launch("programDetail")
        XCTAssertTrue(app.buttons["program.managePhases"].waitForExistence(timeout: 30))
        app.buttons["program.managePhases"].tap()
        let phases = app.cells
        XCTAssertTrue(phases.firstMatch.waitForExistence(timeout: 8))
        let menu = app.buttons["phase.series.add"]
        var found = false
        for i in 0..<phases.count {
            phases.element(boundBy: i).tap()
            XCTAssertTrue(app.buttons["phase.edit"].waitForExistence(timeout: 8))
            app.buttons["phase.edit"].tap()
            if menu.waitForExistence(timeout: 4) { found = true; break }
            app.buttons["Cancel"].firstMatch.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(phases.firstMatch.waitForExistence(timeout: 8))
        }
        guard found else { throw XCTSkip("No phase has upcoming sessions, or no series exists") }
        let before = app.buttons.matching(identifier: "phase.drill.remove").count
        if !menu.isHittable { app.swipeUp() }
        menu.tap()
        let choice = app.buttons.matching(identifier: "phase.series.choice")
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the series is offered")
        choice.tap()
        let apply = app.buttons["series.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 8), "the spread preview opens")
        attach(app, "spread preview")
        apply.tap()
        let rows = app.buttons.matching(identifier: "phase.drill.remove")
        let deadline = Date().addingTimeInterval(6)
        while rows.count <= before, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertGreaterThan(rows.count, before, "its levels are in the phase's plans")
        attach(app, "after spreading")

        // Take the series' drills out again (they were added last, so they
        // are the rows past `before` once sorted by use — remove until back).
        var guardCount = 0
        while rows.count > before, guardCount < 4 {
            rows.element(boundBy: rows.count - 1).tap()
            let remove = app.buttons["phase.chooser.apply"]
            XCTAssertTrue(remove.waitForExistence(timeout: 6))
            remove.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            guardCount += 1
        }
    }

    func testC_DeleteTheSeries() {
        continueAfterFailure = false
        let app = launch("drillsLibrary")
        XCTAssertTrue(app.buttons["library.series"].waitForExistence(timeout: 30))
        app.buttons["library.series"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.name)).firstMatch
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
        let delete = app.buttons["Delete Series"].firstMatch
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete Series'")).element(boundBy: 1)
        if confirm.waitForExistence(timeout: 4) { confirm.tap() } else { app.buttons["Delete Series"].firstMatch.tap() }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.name)).firstMatch.waitForExistence(timeout: 3))
    }
}
