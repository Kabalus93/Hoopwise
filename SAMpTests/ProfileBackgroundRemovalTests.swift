import XCTest
import CoreImage
import ImageIO
@testable import Hoopwise

/// Profile photo background removal (ProfileBackgroundRemoval). The choice of
/// subject and the composite are pinned on synthetic data; the Vision cut-out
/// runs on drawn stills in Resources/BackgroundRemoval (no real photos —
/// exported from ProfileBackgroundTestScene). Edge quality on a real child in
/// gym light needs a real device.
final class ProfileBackgroundRemovalTests: XCTestCase {

    // MARK: Helpers

    private func still(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "bg-\(name)", withExtension: "png"),
                                "bg-\(name).png is not in the test bundle")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// RGBA at a normalized point (top-left origin), 0–255.
    private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // CG is y-up: the requested row from the top sits at h - y*h.
        ctx.draw(image, in: CGRect(x: -x * w, y: -(h - y * h), width: w, height: h))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    private func assertClose(_ a: (Int, Int, Int), _ b: (Int, Int, Int), tolerance: Int = 12,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssert(abs(a.0 - b.0) <= tolerance && abs(a.1 - b.1) <= tolerance && abs(a.2 - b.2) <= tolerance,
                  "\(a) is not \(b)", file: file, line: line)
    }

    private let blue = (47, 111, 222)          // #2F6FDE

    // MARK: Which subject

    /// A 10×10 label map from rows of digits.
    private func map(_ rows: [String]) -> [UInt8] {
        rows.flatMap { $0.map { UInt8(String($0))! } }
    }

    func testTheInstanceUnderTheCentreWins() {
        let labels = map([
            "1100000000",
            "1100000000",
            "1100000000",
            "1100222200",
            "1100222200",
            "1100222200",
            "1100222200",
            "0000222200",
            "0000222200",
            "0000000000",
        ])
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: labels, width: 10, height: 10,
                                                                focus: CGPoint(x: 0.5, y: 0.5)), [2])
    }

    func testWithNothingUnderTheCentreTheNearestWins() {
        let labels = map([
            "1000000000",
            "0000000000",
            "0000000000",
            "0000000000",
            "0000000000",
            "0000000330",
            "0000000330",
            "0000000000",
            "0000000000",
            "0000000000",
        ])
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: labels, width: 10, height: 10,
                                                                focus: CGPoint(x: 0.5, y: 0.5)), [3])
    }

    func testASmallInstanceTouchingTheSubjectJoinsIt() {
        // 2 is the child; 4 a ball against their side; 1 a person apart.
        let labels = map([
            "1000000000",
            "1000000000",
            "1002222000",
            "1002222000",
            "1002222440",
            "1002222440",
            "1002222000",
            "1002222000",
            "0002222000",
            "0000000000",
        ])
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: labels, width: 10, height: 10,
                                                                focus: CGPoint(x: 0.5, y: 0.5)), [2, 4])
    }

    func testASecondPersonTouchingTheSubjectStaysOut() {
        // 5 stands shoulder to shoulder with 2 and is as big: not a ball.
        let labels = map([
            "0000000000",
            "0022225550",
            "0022225550",
            "0022225550",
            "0022225550",
            "0022225550",
            "0022225550",
            "0022225550",
            "0022225550",
            "0000000000",
        ])
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: labels, width: 10, height: 10,
                                                                focus: CGPoint(x: 0.45, y: 0.5)), [2])
    }

    func testAnEmptyMapChoosesNothing() {
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: [UInt8](repeating: 0, count: 100),
                                                                width: 10, height: 10,
                                                                focus: CGPoint(x: 0.5, y: 0.5)), [])
        XCTAssertEqual(ProfileBackgroundRemoval.chooseInstances(labels: [1, 2], width: 10, height: 10,
                                                                focus: .zero), [], "a map of the wrong size")
    }

    // MARK: Composite

    func testTheCompositeKeepsTheMaskedPartAndPaintsTheRest() throws {
        // A red photo; the mask keeps its left half.
        let side = 64
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let photo = try XCTUnwrap(ctx.makeImage())
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: side / 2, height: side))
            .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: side, height: side)))
        let cutout = ProfileBackgroundRemoval.Cutout(image: photo, mask: mask)

        let out = try XCTUnwrap(ProfileBackgroundRemoval.composite(cutout, hex: "#2F6FDE"))
        XCTAssertEqual(out.width, side)
        XCTAssertEqual(out.height, side)
        assertClose(pixel(out, 0.2, 0.5), (255, 0, 0))
        assertClose(pixel(out, 0.8, 0.5), blue)
    }

    func testHexColours() {
        let (r, g, b) = ProfileBackgroundRemoval.rgb("#2F6FDE")
        XCTAssertEqual(Int((r * 255).rounded()), 47)
        XCTAssertEqual(Int((g * 255).rounded()), 111)
        XCTAssertEqual(Int((b * 255).rounded()), 222)
        XCTAssertEqual(ProfileBackgroundRemoval.rgb("FFFFFF").0, 1)
        // Nonsense falls back to the default blue, never crashes.
        XCTAssertEqual(ProfileBackgroundRemoval.rgb("nope").2, ProfileBackgroundRemoval.rgb("#2F6FDE").2, accuracy: 0.01)
    }

    func testThePaletteIsValidAndOnByDefault() {
        XCTAssertFalse(ProfileBackgroundRemoval.palette.isEmpty)
        for hex in ProfileBackgroundRemoval.palette {
            XCTAssertNotNil(UInt32(hex.dropFirst(), radix: 16), hex)
            XCTAssertEqual(hex.count, 7, hex)
        }
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: ProfileBackgroundRemoval.enabledKey)
        defer { defaults.set(saved, forKey: ProfileBackgroundRemoval.enabledKey) }
        defaults.removeObject(forKey: ProfileBackgroundRemoval.enabledKey)
        XCTAssertTrue(ProfileBackgroundRemoval.isEnabled, "on unless the coach switches it off")
        defaults.set(false, forKey: ProfileBackgroundRemoval.enabledKey)
        XCTAssertFalse(ProfileBackgroundRemoval.isEnabled)
    }

    // MARK: Vision on the stills

    /// Vision's foreground model needs the Neural Engine / GPU path; if the
    /// simulator cannot run it, say so instead of failing.
    private func requireVision() throws -> ProfileBackgroundRemoval.Cutout {
        let image = try still("single")
        guard let cutout = ProfileBackgroundRemoval.cutOut(image) else {
            #if targetEnvironment(simulator)
            throw XCTSkip("Vision's foreground instance mask does not run on this simulator — checked on the Mac build instead")
            #else
            XCTFail("no subject found in the single-player still")
            throw XCTSkip()
            #endif
        }
        return cutout
    }

    func testTheSinglePlayerIsCutOutWithTheBall() throws {
        let cutout = try requireVision()
        let out = try XCTUnwrap(ProfileBackgroundRemoval.composite(cutout, hex: "#2F6FDE"))
        XCTAssertEqual(out.width, cutout.image.width)
        // Corners were gym; now the colour.
        assertClose(pixel(out, 0.05, 0.05), blue)
        assertClose(pixel(out, 0.95, 0.6), blue)
        // The ball held in front of the body is kept (orange, not blue).
        let ball = pixel(out, 0.47, 0.6)
        XCTAssertGreaterThan(ball.0, 180, "ball kept: \(ball)")
        XCTAssertLessThan(ball.2, 100, "ball kept: \(ball)")
        // The face is kept.
        let face = pixel(out, 0.5, 0.33)
        XCTAssertGreaterThan(face.0, 150, "face kept: \(face)")
        XCTAssertLessThan(face.2, 160, "face kept: \(face)")
    }

    func testOnlyThePlayerAtTheCentreIsKept() throws {
        _ = try requireVision()
        let out = try XCTUnwrap(ProfileBackgroundRemoval.process(try still("twoPeople"), hex: "#2F6FDE"))
        // The other person's green jersey at the left edge is painted over.
        assertClose(pixel(out, 0.127, 0.58), blue)
        // The centre player's red jersey stays.
        let jersey = pixel(out, 0.5, 0.43)
        XCTAssertGreaterThan(jersey.0, 170, "centre player kept: \(jersey)")
        XCTAssertLessThan(jersey.2, 90, "centre player kept: \(jersey)")
    }

    func testNoSubjectGivesNothingSoThePlainPhotoIsKept() throws {
        _ = try requireVision()
        XCTAssertNil(ProfileBackgroundRemoval.cutOut(try still("empty")))
    }

    #if DEBUG
    func testTheBundledStillsMatchTheirScenes() throws {
        // The stills were exported from ProfileBackgroundTestScene at 768 px.
        for scene in ProfileBackgroundTestScene.allCases {
            let drawn = try XCTUnwrap(scene.render(side: 768))
            let bundled = try still(scene.rawValue)
            XCTAssertEqual(bundled.width, drawn.width, scene.rawValue)
            assertClose(pixel(bundled, 0.5, 0.48), pixel(drawn, 0.5, 0.48), tolerance: 3)
        }
    }
    #endif
}
