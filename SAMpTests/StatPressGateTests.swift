import XCTest
@testable import Hoopwise

/// One touch on a live-game stat button does ONE thing. A hold removed a
/// point and the release re-added it (October 2026, field report).
final class StatPressGateTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testATapAdds() {
        XCTAssertTrue(StatPressGate().tap(at: t0))
    }

    func testTheReleaseOfAHoldDoesNotAdd() {
        var gate = StatPressGate()
        XCTAssertTrue(gate.hold(at: t0))
        XCTAssertFalse(gate.tap(at: t0.addingTimeInterval(0.3)), "lifting the finger after a removal must not re-add")
    }

    func testTheNextTouchAddsAgain() {
        var gate = StatPressGate()
        _ = gate.hold(at: t0)
        XCTAssertTrue(gate.tap(at: t0.addingTimeInterval(StatPressGate.releaseWindow + 0.1)))
    }
}
