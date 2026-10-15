import XCTest
import UIKit
@testable import Hoopwise

/// The profile camera's crop: the circle's square, mapped to the sensor image,
/// becomes a 1024px square avatar. The preview→sensor mapping
/// (`metadataOutputRectConverted`) needs a real camera; this pins the part
/// after it — the crop and the orientation — on a synthetic sensor image.
final class ProfilePhotoCropTests: XCTestCase {

    /// A 400×300 "sensor" image: left half red, right half blue.
    private func sensorImage() -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 300))
        }.cgImage!
    }

    /// The centre pixel, read through an explicit RGBA context so channel
    /// order cannot depend on the renderer's native format.
    private func centerColor(_ image: UIImage) -> (r: CGFloat, b: CGFloat) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: -image.size.width / 2 + 0.5, y: -image.size.height / 2 + 0.5,
                              width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[2]) / 255)
    }

    func testCropTakesTheRequestedRegionAsA1024Square() throws {
        // The left (red) half's centred square.
        let red = try XCTUnwrap(ProfileCameraModel.cropped(
            sensorImage(), normalized: CGRect(x: 0.05, y: 0.1, width: 0.4, height: 0.533),
            orientationRaw: 1))
        XCTAssertEqual(red.size, CGSize(width: 1024, height: 1024))
        XCTAssertGreaterThan(centerColor(red).r, 0.9)
        XCTAssertLessThan(centerColor(red).b, 0.1)

        let blue = try XCTUnwrap(ProfileCameraModel.cropped(
            sensorImage(), normalized: CGRect(x: 0.55, y: 0.1, width: 0.4, height: 0.533),
            orientationRaw: 1))
        XCTAssertGreaterThan(centerColor(blue).b, 0.9)
    }

    func testOrientationIsAppliedAndTheResultStaysSquare() throws {
        // Portrait capture: sensor data is landscape, orientation .right (6).
        let image = try XCTUnwrap(ProfileCameraModel.cropped(
            sensorImage(), normalized: CGRect(x: 0.25, y: 0, width: 0.75, height: 1),
            orientationRaw: 6))
        XCTAssertEqual(image.size.width, image.size.height)
    }

    func testAnOutOfBoundsRectIsClampedNotCrashed() {
        XCTAssertNotNil(ProfileCameraModel.cropped(
            sensorImage(), normalized: CGRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5),
            orientationRaw: 1))
    }
}
