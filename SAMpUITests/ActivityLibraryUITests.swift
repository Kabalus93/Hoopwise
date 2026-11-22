import XCTest

/// The drills page built on the activity library: skill chips, then Age,
/// Block, Type and Source as removable filters (16 Nov 2026), "include
/// earlier ages", and rule options under Game (not drills).
final class ActivityLibraryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "drillsLibrary"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-library.ageFilter", "U8", "-library.skill", "",
                                "-library.sort", "suggested"]   // pinned for these tests
        app.launch()
    }

    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "library.row") }

    /// The page is up. (Not "a library row exists": the list is lazy and the
    /// rows sit under the Tracked shooting section — 24 Nov 2026.)
    private func waitForPage() {
        XCTAssertTrue(app.buttons["Add Drill"].firstMatch.waitForExistence(timeout: 30), "the drills page")
    }

    /// Scrolls the list until one of the elements is built.
    @discardableResult
    private func reach(_ elements: XCUIElement...) -> Bool {
        for _ in 0..<12 where !elements.contains(where: \.exists) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        return elements.contains(where: \.exists)
    }

    /// U8 alone has 22 routine activities; with U6 and U7 included, 51. The
    /// switch lives in the ⓘ guidance sheet and is remembered, so start from
    /// whichever state it is in.
    private func choose(_ filter: String, _ value: String) {
        app.buttons[filter].firstMatch.tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", value)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(filter) offers \(value)")
        item.tap()
    }

    func testAgeBlockAndEarlierAges() {
        waitForPage()
        choose("library.filter.block", "Routine")
        let alone = app.staticTexts["Routine · 22"], together = app.staticTexts["Routine · 51"]
        XCTAssertTrue(reach(alone, together), "U8 routine: 22 alone, 51 with earlier ages")
        let wasAlone = alone.exists
        app.buttons["library.info"].tap()
        let toggle = app.switches["library.includeEarlier"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the switch is in the guidance sheet")
        toggle.switches.firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue((wasAlone ? together : alone).waitForExistence(timeout: 5),
                      "the switch adds or removes U6 and U7")
        let note = app.descendants(matching: .any).matching(identifier: "library.earlierNote").firstMatch
        // The note sits with the filters at the top of the list.
        for _ in 0..<12 where !app.buttons["library.filter.block"].firstMatch.isHittable {
            app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(note.exists, wasAlone, "a visible note says when earlier ages are included")
    }

    func testRuleOptionsLiveUnderGame() {
        waitForPage()
        choose("library.filter.block", "Game")
        choose("library.filter.type", "Rule options")
        let rule = app.descendants(matching: .any).matching(identifier: "library.rule").firstMatch
        XCTAssertTrue(reach(rule), "rule options are listed under Game")
        rule.tap()
        XCTAssertTrue(app.staticTexts["SOURCE"].waitForExistence(timeout: 5) || app.staticTexts["Source"].exists)
    }

    func testDetailShowsHowItRunsAndSource() {
        waitForPage()
        XCTAssertTrue(reach(rows.firstMatch), "a library drill")
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["HOW IT RUNS"].waitForExistence(timeout: 8)
                      || app.staticTexts["How it runs"].exists)
    }

    /// Searching covers the WHOLE library, not the chosen age and block: from
    /// U8 · Routine, "keeping off" finds the U7 small game, words in any order.
    func testSearchCoversTheWholeLibrary() {
        waitForPage()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("off keeping")
        XCTAssertTrue(app.staticTexts["20 Passes, Keeping Off"].waitForExistence(timeout: 5),
                      "a U7 small game is found from U8 · Routine")
        XCTAssertFalse(app.buttons["library.filter.block"].exists, "the filters step aside while searching")
    }

    /// Skill first (Luther: "which are ball handling, passing or shooting"),
    /// age optional: Passing lists drills strong on it; removing the age keeps
    /// the skill and widens the list; Clear all removes both. Launched without
    /// the age argument — a launch argument pins a setting the app cannot
    /// change.
    func testSkillFilterWithOptionalAge() {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "drillsLibrary"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        waitForPage()
        let clear = app.buttons["library.filter.clear"].firstMatch
        if clear.exists { clear.tap() }
        choose("library.filter.age", "U8")

        app.buttons["library.skill.passing"].firstMatch.tap()
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Strong on passing · '")).firstMatch
        XCTAssertTrue(reach(header), "Passing lists the drills strong on it")
        let atU8 = header.label
        for _ in 0..<12 where !app.buttons["library.filter.age.clear"].firstMatch.isHittable {
            app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        }
        app.buttons["library.filter.age.clear"].firstMatch.tap()
        XCTAssertTrue(reach(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Strong on passing · ' AND label != %@", atU8))
            .firstMatch), "every age has more passing drills than U8 alone")
        for _ in 0..<12 where !app.buttons["library.filter.clear"].firstMatch.isHittable {
            app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        }
        app.buttons["library.filter.clear"].firstMatch.tap()
        XCTAssertTrue(reach(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Drills · '")).firstMatch),
                      "Clear all shows every drill")
    }
}
