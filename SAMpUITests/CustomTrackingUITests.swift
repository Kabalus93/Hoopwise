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
        let athletes = app.buttons.matching(identifier: "track.cell").count
        log.tap()
        // 30 seconds of passes: 1, 2, ✓ for each athlete — the pad pops out of
        // each cell in turn, the keys alone.
        for i in 0..<athletes {
            for k in ["1", "2", "confirm"] {
                let b = app.buttons["track.keys.key.\(k)"]
                XCTAssertTrue(b.waitForExistence(timeout: 5), "key \(k)")
                b.tap()
                if i == 0 && k == "2" { attach("pad") }
            }
        }
        sleep(1)
        let filled = app.buttons.matching(NSPredicate(format: "identifier == 'track.cell' AND label ENDSWITH '12'"))
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
