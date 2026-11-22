import XCTest

/// The coach's own tracked drills (23 Nov 2026): the New Drill form's
/// Tracking section, and a tracked drill logged from its plan row.
final class CustomTrackingUITests: XCTestCase {

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchSession(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "0"
        app.launchEnvironment["HOOPWISE_DEMO_TRACKED"] = mode
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    func testACoachsTrackedDrillLogsFromItsPlanRow() {
        let app = launchSession("1")
        defer { _ = launchSession("clear") }
        let line = app.buttons["track.line"]
        for _ in 0..<10 where !line.exists || !line.isHittable { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the tracker line shows on the drill's row")
        XCTAssertTrue(line.label.contains("passes"), line.label)
        attach("plan")
        line.tap()
        let log = app.buttons["track.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "the station opens")
        attach("station")
        log.tap()
        let save = app.buttons["track.pad.log"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the pad opens with the number pad")
        // 30 seconds of passes: type 12 on the floating number pad, then Log.
        let one = app.buttons["track.wheel.key.1"]
        if one.exists {
            one.tap()
            app.buttons["track.wheel.key.2"].tap()
            XCTAssertTrue(app.staticTexts["track.wheel.value"].label.hasPrefix("12"), "the first key replaces, the next appends")
        }
        attach("pad")
        let athletes = app.buttons.matching(identifier: "track.pad.athlete").count
        for _ in 0..<athletes where save.exists { save.tap(); sleep(1) }
        if app.buttons["track.pad.done"].exists { app.buttons["track.pad.done"].tap() }
        let filled = app.buttons.matching(NSPredicate(format: "identifier == 'track.cell' AND NOT (label ENDSWITH '—')"))
        XCTAssertTrue(filled.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(filled.count, athletes, "everyone logged")
        attach("logged")
        app.buttons["track.station.done"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("\(athletes)/\(athletes)"), line.label)
        attach("plan after")
    }

    func testTheNewDrillFormSetsUpTracking() {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "newDrill"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let toggle = app.switches["newDrill.track"]
        for _ in 0..<8 where !toggle.exists || !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Tracking section")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let measure = app.buttons["newDrill.track.measure"]
        XCTAssertTrue(measure.waitForExistence(timeout: 5), "turned on, the measure appears")
        measure.tap()
        app.buttons["Time to finish"].firstMatch.tap()
        let passing = app.buttons["newDrill.track.skill.ballHandling"]
        for _ in 0..<4 where !passing.isHittable { app.swipeUp() }
        passing.tap()
        let footer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'faster is better'")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "the footer says how it will be logged")
        attach("tracking")
    }
}
