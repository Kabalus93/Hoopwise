import XCTest

/// Editing an evaluation leaves unrated skills unrated (26 Nov 2026 — Edit
/// used to fill every unrated skill with 5 and Save stored all eight).
final class EvaluationEditUITests: XCTestCase {

    private var app: XCUIApplication!
    private let axes = ["ballHandling", "passing", "shooting", "finishing", "playmaking", "gameIQ", "defense", "footwork"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "quickPeep"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func unrated() -> [String] {
        axes.filter { any("peep.skill.value.\($0)").label == "—" }
    }

    private func openEditor() {
        let button = any("peep.evaluate")
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 20), "no Evaluate / Edit button")
        button.tap()
        XCTAssertTrue(any("peep.skill.slider.shooting").waitForExistence(timeout: 5), "the sliders did not open")
    }

    func testUnratedSkillsStayUnratedAfterSaving() throws {
        openEditor()
        let before = unrated()
        attach("editing")
        try XCTSkipIf(before.count < 2, "the demo athlete is rated on nearly everything")
        // Rate ONE of the unrated skills, save.
        let picked = before[0]
        let slider = any("peep.skill.slider.\(picked)")
        for _ in 0..<8 where !slider.isHittable { app.swipeUp() }
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertNotEqual(any("peep.skill.value.\(picked)").label, "—", "moving the slider rates the skill")
        let save = any("peep.evaluate")
        for _ in 0..<8 where !save.isHittable { app.swipeDown() }
        save.tap()   // Save
        sleep(1)
        // Open again: only the one that was moved gained a rating.
        let edit = any("peep.evaluate")
        for _ in 0..<8 where !edit.isHittable { app.swipeDown() }
        edit.tap()
        XCTAssertTrue(any("peep.skill.slider.shooting").waitForExistence(timeout: 5))
        XCTAssertEqual(unrated(), Array(before.dropFirst()), "the skills nobody touched are still unrated")
        attach("after saving")
    }
}
