import XCTest

/// Hub → Lexicon: search finds a term by another name and opens its entry;
/// a section lists its terms. Read-only, no cleanup needed.
final class LexiconUITests: XCTestCase {

    func testSearchOpensATermByAnotherName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "lexicon"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let section = app.buttons.matching(identifier: "lexicon.section").firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("PnR")
        let result = app.buttons.matching(identifier: "lexicon.result")
            .matching(NSPredicate(format: "label BEGINSWITH 'Pick-and-roll'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "another name finds the term")
        result.tap()
        XCTAssertTrue(app.staticTexts["A teammate screens the ball handler's defender, then rolls to the basket for a pass."]
            .waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }
}
