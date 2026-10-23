import XCTest

/// The expanded notification card (HoopwiseNotifications content extension)
/// and the Live Activity card, checked on the simulator. Both tests are
/// skipped unless the runner gets their variable, because the notification
/// is fired from OUTSIDE the runner: a notification scheduled by an app the
/// runner launched never reached the banner here. Recipe: start the test,
/// then `SIMCTL_CHILD_HOOPWISE_SCREENSHOT_STORE=1
/// SIMCTL_CHILD_HOOPWISE_NOTIFY_DEMO=<kind> xcrun simctl launch … OKTO.SAMp`
/// (or HOOPWISE_LIVE_ACTIVITY_DEMO=1), then open another app.
final class NotificationCardUITests: XCTestCase {

    /// Presses a banner fired from outside the runner
    /// (`simctl launch` with HOOPWISE_NOTIFY_DEMO) — skipped unless the runner
    /// gets HW_PRESS_HEADLINE, so ⌘U never waits on it.
    func testPressDeliveredBanner() throws {
        guard let headline = ProcessInfo.processInfo.environment["HW_PRESS_HEADLINE"] else {
            throw XCTSkip("set TEST_RUNNER_HW_PRESS_HEADLINE")
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", headline)).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 120), "no banner")
        banner.press(forDuration: 1.2)
        sleep(2)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "pressed"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Pulls down Notification Center, where a running Live Activity shows
    /// its lock-screen card — skipped unless the runner gets HW_SHOW_NC.
    func testShowNotificationCenter() throws {
        guard ProcessInfo.processInfo.environment["HW_SHOW_NC"] != nil else {
            throw XCTSkip("set TEST_RUNNER_HW_SHOW_NC")
        }
        sleep(25)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        sleep(3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "nc"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
