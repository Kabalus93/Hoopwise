import XCTest

/// Tracked shooting in the plan (20 Nov 2026; redesigned 23 Nov 2026): a
/// tracked drill's plan row carries one tracker line; Log opens the shooting
/// station (the whole tracker as a page); a tap on a cell pops the floating
/// number pad out of it — the keys alone — and ✓ logs and opens the next cell.
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

    /// A key of the open number pad (it may be moving to the next cell).
    private func key(_ app: XCUIApplication, _ pad: String, _ k: String) {
        let b = app.buttons["\(pad).key.\(k)"]
        if !b.waitForExistence(timeout: 5) { attach("missing \(k)") }
        XCTAssertTrue(b.exists, "\(pad) key \(k)")
        b.tap()
    }

    /// A tap outside closes the popup.
    private func closePad(_ app: XCUIApplication) {
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.97)).tap()
        sleep(1)
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
        key(app, "shooting.keys", "7")
        attach("pad")
        XCTAssertFalse(app.buttons["shooting.pad.athlete"].exists, "the popup is the keys alone")
        key(app, "shooting.keys", "confirm")
        // Free throws have one spot: the pad opens on the next athlete.
        key(app, "shooting.keys", "5")
        key(app, "shooting.keys", "confirm")
        closePad(app)
        XCTAssertTrue(addon.staticTexts["70%"].waitForExistence(timeout: 5), "7 of 10")
        XCTAssertTrue(addon.staticTexts["50%"].exists, "5 of 10")
        attach("logged")
        app.buttons["shooting.station.done"].tap()
        let line = app.buttons["shooting.tracker.freeThrows"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("2/") || line.label.contains("logged"), line.label)
        attach("plan after")
    }

    /// Rounds (23 Nov 2026): the same drill run again in the session — the
    /// second round compares with the first, the plan line follows it.
    func testASecondRoundComparesWithTheFirst() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = openStation(app, "freeThrows")
        XCTAssertFalse(app.buttons["round.add"].exists, "nothing to run again yet")
        let cells = addon.buttons.matching(identifier: "shooting.cell")
        cells.element(boundBy: 0).tap()
        key(app, "shooting.keys", "4")
        key(app, "shooting.keys", "confirm")
        closePad(app)
        XCTAssertTrue(addon.staticTexts["40%"].waitForExistence(timeout: 5))
        let add = app.buttons["round.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "a logged round can be run again")
        add.tap()
        XCTAssertTrue(app.buttons["round.2"].waitForExistence(timeout: 5))
        let again = app.descendants(matching: .any).matching(identifier: "shooting.addon.freeThrows").firstMatch
        XCTAssertFalse(again.staticTexts["40%"].exists, "round 2 starts empty")
        again.buttons.matching(identifier: "shooting.cell").element(boundBy: 0).tap()
        key(app, "shooting.keys", "8")
        key(app, "shooting.keys", "confirm")
        closePad(app)
        XCTAssertTrue(again.staticTexts["80%"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.staticTexts.matching(NSPredicate(format: "label CONTAINS 'round 1 40%'")).firstMatch.exists,
                      "compared with round 1")
        attach("round 2")
        app.buttons["round.1"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "shooting.addon.freeThrows").firstMatch
            .staticTexts["40%"].waitForExistence(timeout: 5), "round 1 is still there")
        app.buttons["shooting.station.done"].tap()
        let line = app.buttons["shooting.tracker.freeThrows"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("Round 2"), line.label)
        XCTAssertTrue(line.label.contains("40% → 80%"), line.label)
        attach("plan after")
    }

    func testFiveSpotsLogAthleteByAthleteFromLogMakes() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = openStation(app, "twos")
        addon.buttons["shooting.log"].tap()
        // One athlete's five spots: 3, ✓ — the pad walks the spots.
        for i in 0..<5 {
            key(app, "shooting.keys", "3")
            if i == 0 { attach("pad") }
            key(app, "shooting.keys", "confirm")
        }
        attach("next athlete")
        closePad(app)
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
        key(app, "shotchart.keys", "4")          // made
        key(app, "shotchart.keys", "next")       // → attempted
        key(app, "shotchart.keys", "9")          // of 9
        attach("pad")
        key(app, "shotchart.keys", "confirm")
        // The pad moves on to the athlete's next empty zone.
        XCTAssertTrue(app.buttons["shotchart.keys.key.4"].waitForExistence(timeout: 5), "the next zone opens")
        closePad(app)
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
