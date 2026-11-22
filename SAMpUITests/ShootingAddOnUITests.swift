import XCTest

/// Tracked shooting in the plan (20 Nov 2026; redesigned 23 Nov 2026): a
/// tracked drill's plan row carries one tracker line; Log opens the shooting
/// station (the whole tracker as a page); a number pad writes each athlete's
/// self-reported makes and moves on.
final class ShootingAddOnUITests: XCTestCase {

    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "0"
        app.launchEnvironment["HOOPWISE_DEMO_SHOOTING"] = mode
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    /// The tracker line on the drill's plan row → the station.
    private func openStation(_ app: XCUIApplication, _ drill: String) -> XCUIElement {
        let line = app.buttons["shooting.tracker.\(drill)"]
        for _ in 0..<8 where !line.exists || !line.isHittable { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the tracker line shows on the plan row")
        attach("plan")
        line.tap()
        let addon = app.descendants(matching: .any).matching(identifier: "shooting.addon.\(drill)").firstMatch
        XCTAssertTrue(addon.waitForExistence(timeout: 5), "the station opens")
        return addon
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testFreeThrowsLogFromThePad() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = openStation(app, "freeThrows")
        attach("station")
        let cells = addon.buttons.matching(identifier: "shooting.cell")
        XCTAssertGreaterThan(cells.count, 1, "one cell per athlete")
        cells.element(boundBy: 0).tap()
        let seven = app.buttons["shooting.pad.7"]
        XCTAssertTrue(seven.waitForExistence(timeout: 5), "the pad opens")
        attach("pad")
        seven.tap()
        // Free throws have one spot: the pad moves to the next athlete.
        app.buttons["shooting.pad.5"].tap()
        // After the last athlete the pad closes itself.
        if app.buttons["shooting.pad.done"].waitForExistence(timeout: 1) { app.buttons["shooting.pad.done"].tap() }
        XCTAssertTrue(addon.staticTexts["70%"].waitForExistence(timeout: 5), "7 of 10")
        XCTAssertTrue(addon.staticTexts["50%"].exists, "5 of 10")
        attach("logged")
        app.buttons["shooting.station.done"].tap()
        let line = app.buttons["shooting.tracker.freeThrows"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("2/") || line.label.contains("logged"), line.label)
        attach("plan after")
    }

    func testFiveSpotsLogAthleteByAthleteFromLogMakes() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = openStation(app, "twos")
        addon.buttons["shooting.log"].tap()
        let grid = app.buttons["shooting.pad.6"], log = app.buttons["shooting.pad.log"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5) || log.exists, "Log makes opens the pad")
        attach("pad")
        // One athlete's five spots, one action each: a grid tap (≤ 10 shots)
        // or, on the wheel, a number near the start then Log.
        for _ in 0..<5 {
            if grid.exists {
                grid.tap()
            } else {
                let start = Int(log.label.filter(\.isNumber)) ?? 0
                let near = app.buttons["shooting.wheel.\(max(0, start - 1))"]
                if near.exists { near.tap(); sleep(1) }
                log.tap()
            }
        }
        attach("next athlete")
        XCTAssertGreaterThan(app.buttons.matching(identifier: "shooting.pad.athlete").count, 1, "everyone as photos")
        app.buttons["shooting.pad.done"].tap()
        // Five cells of the first athlete are in.
        let filled = addon.buttons.matching(NSPredicate(format: "identifier == 'shooting.cell' AND label MATCHES '.* [0-9]+$'"))
        XCTAssertGreaterThanOrEqual(filled.count, 5, "five spots logged")
        attach("logged")
    }

    func testShotChartLogsAZoneFromTheMap() {
        let app = launch("chart")
        defer { _ = launch("clear") }
        let addon = openStation(app, "shotChart")
        let leftWing = addon.descendants(matching: .any).matching(identifier: "shotchart.zone.6").firstMatch
        XCTAssertTrue(leftWing.exists)
        attach("map")
        // The zone is L-shaped: its frame's centre lies in mid-range, so tap
        // inside the wing itself (high on the left).
        // A coordinate tap does not scroll: bring the whole map on screen.
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where leftWing.frame.maxY > window.maxY - 120 { app.swipeUp(velocity: .slow) }
        let rim = addon.descendants(matching: .any).matching(identifier: "shotchart.zone.0").firstMatch
        for _ in 0..<6 where rim.frame.maxY > window.maxY - 60 { app.swipeUp(velocity: .slow) }
        leftWing.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4)).tap()
        let four = app.buttons["shotchart.made.4"]
        XCTAssertTrue(four.waitForExistence(timeout: 5), "tapping a zone opens the pad with its wheels")
        four.tap()                               // made
        sleep(1)
        app.buttons["shotchart.att.9"].tap()     // of 9
        sleep(1)
        XCTAssertTrue(app.buttons["shotchart.log"].label.contains("4/9"), app.buttons["shotchart.log"].label)
        app.buttons["shotchart.log"].tap()
        attach("pad")
        app.buttons["shotchart.pad.done"].tap()
        let zone = addon.descendants(matching: .any).matching(identifier: "shotchart.zone.6").firstMatch
        XCTAssertTrue(zone.label.contains("44%"), "4 of 9 in the left wing: \(zone.label)")
        attach("logged")
    }

    /// The setup sheet goes past the old 3-minute cap.
    func testSetupSheetTakesLongTimes() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = openStation(app, "twos")
        addon.buttons["shooting.setup"].tap()
        let mode = app.segmentedControls["shootingSetup.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "the setup sheet opens")
        mode.buttons.element(boundBy: 1).tap()           // makes in a time
        app.buttons["shootingSetup.chip.300"].tap()      // 5 min
        let summary = app.descendants(matching: .any).matching(identifier: "shootingSetup.summary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("5 min"), summary.label)
        attach("setup")
        app.buttons["shootingSetup.done"].tap()
        XCTAssertTrue(addon.staticTexts.matching(NSPredicate(format: "label CONTAINS '5 min'")).firstMatch
            .waitForExistence(timeout: 5), "the station shows the new setup")
        attach("station after")
    }
}
