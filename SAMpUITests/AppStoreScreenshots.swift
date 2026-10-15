import XCTest

/// App Store screenshots, captured from the REAL app on the isolated demo
/// store (HOOPWISE_SCREENSHOT_STORE=1: CloudKit off, pruned to demo data —
/// see Hoopwise/ScreenshotStore.swift). Skipped unless the runner is given
/// HOOPWISE_SCREENSHOTS=1, so ⌘U never runs it:
///
///   TEST_RUNNER_HOOPWISE_SCREENSHOTS=1 TEST_RUNNER_HOOPWISE_LANG=en \
///   xcodebuild test-without-building … -only-testing:HoopwiseUITests/AppStoreScreenshots
///
/// Each screen is a kept attachment named NN-name; pull them out of the
/// .xcresult with `xcrun xcresulttool export attachments`.
final class AppStoreScreenshots: XCTestCase {

    private var app: XCUIApplication!
    private var language = "en"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HOOPWISE_SCREENSHOTS"] == "1", "screenshot run only")
        language = env["HOOPWISE_LANG"] ?? "en"
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", language]
        app.launch()
    }

    private func shot(_ name: String, dumpTree: Bool = false) {
        sleep(2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if dumpTree {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(language)-\(name)-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    private func tab(_ en: String, _ zh: String) {
        let label = language == "zh" ? zh : en
        let button = app.tabBars.buttons[label]
        for _ in 0..<4 {
            guard button.waitForExistence(timeout: 5) else { break }
            button.tap()
            sleep(1)
            if button.isSelected { return }
        }
    }

    /// Taps the first element whose label contains `text`.
    @discardableResult
    private func tapContaining(_ text: String, timeout: TimeInterval = 5) -> Bool {
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard match.waitForExistence(timeout: timeout), match.isHittable else { return false }
        match.tap()
        return true
    }

    private func back() {
        let button = app.buttons["BackButton"].firstMatch
        if button.exists, button.isHittable { button.tap() } else {
            app.swipeDown(velocity: .fast)   // dismiss a sheet
        }
        sleep(1)
    }

    private var zh: Bool { language == "zh" }

    // One fresh launch per section (setUp launches): navigation never has
    // to find its way back out of a pushed page or a sheet.

    func test1Home() throws {
        sleep(5)
        shot("01-home")
    }

    func test2CalendarAndAttendance() throws {
        sleep(4)
        tab("Sessions", "课程")
        tapContaining(zh ? "日历" : "Calendar")
        shot("03-calendar")
        if tapContaining("Elite U8") { sleep(2); shot("02-attendance") }
    }

    func test3ProgramAndParentGuide() throws {
        sleep(4)
        tab("Sessions", "课程")
        tapContaining(zh ? "计划" : "Programs")
        guard tapContaining("Elite U8") else { return }
        shot("04-program")
        app.buttons["More"].firstMatch.tap()
        if tapContaining(zh ? "分享给家长" : "Share with Parents") {
            sleep(4)
            shot("05-parent-guide")
        }
    }

    func test4Athletes() throws {
        sleep(4)
        tab("Athletes", "学员")
        shot("07-athletes")
        if tapContaining("Maya Chen") { shot("06-athlete") }
    }

    func test5Hub() throws {
        sleep(4)
        tab("Hub", "中心")
        shot("08-hub")
    }
}
