import XCTest

/// Generate Plan on a real session page fills the plan and says why.
final class PlanGeneratorUITests: XCTestCase {

    func testGenerateFillsThePlanAndExplainsIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en"]
        app.launch()

        let plan = app.buttons["Plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 30))
        plan.tap()
        let generate = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Generate Plan' OR label CONTAINS 'Regenerate'")).firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 8))
        generate.tap()
        let why = app.descendants(matching: .any).matching(identifier: "plan.rationale").firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 8), "the plan explains itself")
        XCTAssertTrue(why.label.contains("level"), why.label)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "generated-plan"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("RATIONALE: \(why.label)")
    }
}
