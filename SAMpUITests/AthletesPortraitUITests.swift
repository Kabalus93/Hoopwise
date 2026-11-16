import XCTest

/// iPad upright: the Athletes tab shows its list beside the profile column
/// (16 Nov 2026, Luther: the page opened empty and the list hid behind the
/// sidebar button). Skips on a phone. Demo store.
final class AthletesPortraitUITests: XCTestCase {

    func testListIsVisibleUpright() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")

        let tab = app.buttons["Athletes"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()

        let atOpen = XCTAttachment(screenshot: app.screenshot())
        atOpen.lifetime = .keepAlways
        add(atOpen)
        XCTAssertTrue(app.staticTexts["Choose an athlete"].firstMatch.waitForExistence(timeout: 10))
        let firstRow = app.buttons["athletes.row"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "no athlete rows on screen")
        XCTAssertTrue(firstRow.isHittable, "the athletes list is hidden upright")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)

        // Opening an athlete keeps the list beside the profile.
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["Choose an athlete"].firstMatch.waitForNonExistence(timeout: 10),
                      "the athlete did not open")
        sleep(1)
        XCTAssertTrue(firstRow.isHittable, "the list closed when an athlete opened")
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.lifetime = .keepAlways
        add(opened)
    }
}
