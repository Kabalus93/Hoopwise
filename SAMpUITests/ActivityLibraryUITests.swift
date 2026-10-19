import XCTest

/// The drills page built on the activity library: age → block → type,
/// "include earlier ages", and rule options under Game (not drills).
final class ActivityLibraryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "drillsLibrary"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-library.age", "U8"]
        app.launch()
    }

    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "library.row") }

    /// U8 alone has 22 routine activities; with U6 and U7 included, 51.
    /// The switch is remembered, so start from whichever state it is in.
    func testAgeBlockAndEarlierAges() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
        let alone = app.staticTexts["Routine · 22"], together = app.staticTexts["Routine · 51"]
        XCTAssertTrue(alone.exists || together.exists, "U8 routine: 22 alone, 51 with earlier ages")
        let wasAlone = alone.exists
        app.switches["library.includeEarlier"].switches.firstMatch.tap()
        XCTAssertTrue((wasAlone ? together : alone).waitForExistence(timeout: 5),
                      "the switch adds or removes U6 and U7")
    }

    func testRuleOptionsLiveUnderGame() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
        app.buttons["Game"].tap()
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rule options'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Game offers a Rule options chip")
        chip.tap()
        let rule = app.descendants(matching: .any).matching(identifier: "library.rule").firstMatch
        XCTAssertTrue(rule.waitForExistence(timeout: 5), "rule options are listed under Game")
        rule.tap()
        XCTAssertTrue(app.staticTexts["SOURCE"].waitForExistence(timeout: 5) || app.staticTexts["Source"].exists)
    }

    func testDetailShowsHowItRunsAndSource() {
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["HOW IT RUNS"].waitForExistence(timeout: 8)
                      || app.staticTexts["How it runs"].exists)
    }
}
