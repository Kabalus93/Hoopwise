import XCTest
import AVFoundation
@testable import Hoopwise

/// The profile camera prefers the virtual multi-lens cameras (they switch to
/// the macro-capable ultra-wide by themselves) and frames them like the wide
/// lens at 1×.
@MainActor
final class ProfileCameraLensTests: XCTestCase {

    func testBackPrefersVirtualCamerasThenWide() {
        XCTAssertEqual(ProfileCameraModel.deviceTypes(for: .back),
                       [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera])
        XCTAssertEqual(ProfileCameraModel.deviceTypes(for: .back).last, .builtInWideAngleCamera)
        XCTAssertEqual(ProfileCameraModel.deviceTypes(for: .front).last, .builtInWideAngleCamera)
    }

    func testWideFramingOnCamerasWithUltraWide() {
        // Triple / dual-wide: zoom 1 is the ultra-wide; the first switch-over is the wide.
        XCTAssertEqual(ProfileCameraModel.wideZoomFactor(
            constituents: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            switchOvers: [2, 6]), 2)
        XCTAssertEqual(ProfileCameraModel.wideZoomFactor(
            constituents: [.builtInUltraWideCamera, .builtInWideAngleCamera], switchOvers: [2]), 2)
    }

    func testNoZoomWhenWideIsAlreadyFirst() {
        // Dual (wide + tele) and plain wide: zoom 1 is already the wide.
        XCTAssertEqual(ProfileCameraModel.wideZoomFactor(
            constituents: [.builtInWideAngleCamera, .builtInTelephotoCamera], switchOvers: [2]), 1)
        XCTAssertEqual(ProfileCameraModel.wideZoomFactor(constituents: [], switchOvers: []), 1)
    }
}
