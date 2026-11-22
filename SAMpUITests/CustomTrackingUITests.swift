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

    /// The type drives the form (24 Nov 2026): Shooting sets made-of-10 with
    /// Shooting MAIN and Footwork SOME, and offers the shot map.
    func testTheNewDrillFormIsDrivenByTheType() {
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
        let shooting = app.buttons["newDrill.track.kind.shooting"]
        XCTAssertTrue(shooting.waitForExistence(timeout: 5), "turned on, the types appear")
        shooting.tap()
        let skill = app.buttons["newDrill.track.skill.shooting"]
        for _ in 0..<5 where !skill.exists || !skill.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(skill.value as? String, "main", "Shooting is the main skill")
        XCTAssertEqual(app.buttons["newDrill.track.skill.footwork"].value as? String, "some")
        XCTAssertEqual(app.buttons["newDrill.track.skill.passing"].value as? String, "off")
        attach("shooting")
        // Two zones on the shot map.
        let corner = app.descendants(matching: .any).matching(identifier: "zonepicker.zone.7").firstMatch
        for _ in 0..<4 where !corner.exists || !corner.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(corner.waitForExistence(timeout: 5), "the shot map")
        corner.tap()
        app.descendants(matching: .any).matching(identifier: "zonepicker.zone.0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'One number a zone (2)'")).firstMatch
            .waitForExistence(timeout: 5), "two zones chosen")
        attach("zones")
        // Conditioning: a time over a course, athleticism mainly.
        let conditioning = app.buttons["newDrill.track.kind.conditioning"]
        for _ in 0..<4 where !conditioning.exists || !conditioning.isHittable { app.swipeDown(velocity: .slow) }
        conditioning.tap()
        XCTAssertTrue(app.buttons["newDrill.track.course"].waitForExistence(timeout: 5), "a course to run")
        let footwork = app.buttons["newDrill.track.skill.footwork"]
        for _ in 0..<5 where !footwork.exists || !footwork.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(footwork.value as? String, "main")
        XCTAssertEqual(app.buttons["newDrill.track.skill.defense"].value as? String, "some")
        // A tap moves Defense from Some to off; another to Main.
        app.buttons["newDrill.track.skill.defense"].tap()
        XCTAssertEqual(app.buttons["newDrill.track.skill.defense"].value as? String, "off")
        app.buttons["newDrill.track.skill.defense"].tap()
        XCTAssertEqual(app.buttons["newDrill.track.skill.defense"].value as? String, "main")
        attach("conditioning")
    }

    /// A shooting drill that names its zones shows the court in its station;
    /// a zone opens that cell's pad, and the result colours the zone.
    func testAShootingDrillLogsOnTheShotMap() {
        let app = launchSession("zones")
        defer { _ = launchSession("clear") }
        let line = app.buttons["track.line"]
        for _ in 0..<10 where !line.exists || !line.isHittable { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(line.label.contains("3 zones"), line.label)
        line.tap()
        let top = app.descendants(matching: .any).matching(identifier: "shotchart.zone.7").firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 5), "the court shows in the station")
        attach("station")
        top.tap()
        for k in ["6", "confirm"] {
            let b = app.buttons["track.keys.key.\(k)"]
            XCTAssertTrue(b.waitForExistence(timeout: 5), "key \(k)")
            b.tap()
        }
        sleep(1)
        // The pad moves on to the athlete's next zone; close it.
        if app.buttons["track.keys.key.confirm"].exists { app.buttons["track.keys.key.confirm"].tap(); sleep(1) }
        XCTAssertTrue(top.label.contains("60%"), "6 of 10 from the top: \(top.label)")
        attach("logged")
    }
}
