import XCTest

/// The media vault (26 Nov 2026): the profile's Media card shows the
/// athlete's photos from Photos; a photo opens, and "Make a post" puts their
/// stats on it. Needs Photos access for the simulator
/// (`xcrun simctl privacy <udid> grant photos OKTO.SAMp`) and photos in its
/// library — HOOPWISE_DEMO_VAULT=1 files the newest six under the athlete.
final class MediaVaultUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testAPhotoBecomesAPostWithTheAthletesStats() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "studentProfile"
        app.launchEnvironment["HOOPWISE_DEMO_VAULT"] = "1"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let photo = app.buttons.matching(identifier: "media.photo").firstMatch
        for _ in 0..<10 where !photo.exists || !photo.isHittable { app.swipeUp() }
        try XCTSkipUnless(photo.waitForExistence(timeout: 10), "no photos in this simulator's library, or no Photos access")
        attach("card")
        photo.tap()
        let make = app.buttons["media.makePost"]
        XCTAssertTrue(make.waitForExistence(timeout: 10), "the photo opens")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: make)
        wait(for: [enabled], timeout: 15)
        make.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "post.preview").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["post.share"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "post.consent").firstMatch.exists)
        attach("game line")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'post.template.'"))
        for t in ["statCard", "poster", "neon"] {
            let chip = app.buttons["post.template.\(t)"]
            // Swipe the strip on whichever chip is on screen (it scrolls itself on a tap).
            for _ in 0..<6 where !chip.isHittable {
                guard let visible = chips.allElementsBoundByIndex.first(where: { $0.isHittable }) else { break }
                visible.swipeLeft()
            }
            chip.tap()
            sleep(1)
            attach(t)
        }
    }
}
