import XCTest

/// Home search (16 Nov 2026, Luther): pulling Home down opens a Spotlight-like
/// search; results are grouped by kind and open the item. Demo store.
final class HomeSearchUITests: XCTestCase {

    func testPullDownSearchesAndOpensAResult() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()

        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))
        home.tap()
        sleep(2)

        // A short pull and let go, as on the iPhone's home screen.
        pull(app)

        let field = app.textFields["home.search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "pulling Home down did not open the search")
        add(XCTAttachment(screenshot: app.screenshot()).keepingAlways)

        field.typeText("a")
        let result = app.buttons["home.search.result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "no results for “a”")
        XCTAssertTrue(app.staticTexts["ATHLETES"].firstMatch.exists, "athletes are not among the results")
        add(XCTAttachment(screenshot: app.screenshot()).keepingAlways)

        result.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "opening a result did not close the search")
        sleep(1)
        add(XCTAttachment(screenshot: app.screenshot()).keepingAlways)
    }

    func testCancelClosesTheSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))
        home.tap()
        sleep(2)
        pull(app)
        let field = app.textFields["home.search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["home.search.cancel"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }
}

/// A thumb's short pull down Home (15 % of the screen, normal speed).
private func pull(_ app: XCUIApplication) {
    let window = app.windows.firstMatch
    window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
}

private extension XCTAttachment {
    var keepingAlways: XCTAttachment {
        lifetime = .keepAlways
        return self
    }
}
