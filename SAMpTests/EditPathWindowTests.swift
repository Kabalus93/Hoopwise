import XCTest
import CoreGraphics
@testable import Hoopwise

/// A2 — PATHS APPEAR WITH THEIR ACTION, AND ONLY THEN.
///
/// Edit mode used to draw every movement path of the whole play at every
/// playhead position, which is why a play with more than two actions in it read
/// as a bowl of spaghetti. The rule now: a path is on screen from `lead`
/// seconds before its segment starts until `linger` seconds after it ends.
///
/// Two exemptions, both deliberate and both tested here:
///   - PINNED tracks (the selected entity, the one being dragged or bent) show
///     their whole route regardless of the playhead — that is what you are
///     editing.
///   - `editPathWindow == nil` disables windowing entirely: the "Show all
///     paths" escape hatch, and presentation, which windows through
///     consumption instead and must not be gated twice.
final class EditPathWindowTests: XCTestCase {

    private let entityId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    /// One action: a cut from 1.0s to 2.0s. Nothing else in the read, so
    /// anything on screen at another time is the bug.
    private func steps() -> [PlayDiagram.BranchStep] {
        let track = Track(entityId: entityId, keyframes: [
            Keyframe(t: 1.0, position: CGPoint(x: 6, y: 24)),
            Keyframe(t: 2.0, position: CGPoint(x: 19, y: 12))])
        return [PlayDiagram.BranchStep(node: ReadNode(title: "Base", tracks: [track]),
                                       startsAt: 0)]
    }

    private func pathCount(at time: Double,
                           style: RenderStyle = .edit,
                           pinned: Set<UUID> = []) -> Int {
        PathConsumption.visibleTrackPaths(steps: steps(), at: time, style: style,
                                          pinnedTracks: pinned).pieces.count
    }

    func testWindowIsClosedBeforeTheAnnouncement() {
        // Window opens at 1.0 - 0.3 = 0.7.
        XCTAssertEqual(pathCount(at: 0.0), 0)
        XCTAssertEqual(pathCount(at: 0.65), 0)
    }

    func testWindowOpensJustBeforeTheAction() {
        XCTAssertEqual(pathCount(at: 0.75), 1)
        XCTAssertEqual(pathCount(at: 1.5), 1, "mid-action the path is obviously up")
    }

    func testWindowLingersThenCloses() {
        // Closes at 2.0 + 0.2 = 2.2.
        XCTAssertEqual(pathCount(at: 2.1), 1)
        XCTAssertEqual(pathCount(at: 2.35), 0)
        XCTAssertEqual(pathCount(at: 9.0), 0)
    }

    /// The selection exception. Without it, editing a route you cannot see is
    /// the trade the window would have cost.
    func testPinnedTrackIgnoresTheWindow() {
        XCTAssertEqual(pathCount(at: 5.0), 0)
        XCTAssertEqual(pathCount(at: 5.0, pinned: [entityId]), 1)
        XCTAssertEqual(pathCount(at: 0.0, pinned: [entityId]), 1)
    }

    /// The escape hatch: no window configured, no gating.
    func testShowAllPathsDisablesTheWindow() {
        var style = RenderStyle.edit
        style.editPathWindow = nil
        XCTAssertEqual(pathCount(at: 5.0, style: style), 1)
        XCTAssertEqual(pathCount(at: 0.0, style: style), 1)
    }

    /// Presentation is untouched: it consumes paths ahead of motion and carries
    /// no edit window at all. Double-gating it would delete the draw-on lead.
    func testPresentationCarriesNoEditWindow() {
        XCTAssertNil(RenderStyle.presentation.editPathWindow)
        XCTAssertNotNil(RenderStyle.edit.editPathWindow)
    }

    /// The predicate the flight lines share with track segments — one rule, so
    /// a pass arc and a cut cannot disagree about what "now" means.
    func testFlightLinesUseTheSamePredicate() {
        let style = RenderStyle.edit
        // A release at 1.0 arriving at 1.4.
        XCTAssertFalse(PathConsumption.withinEditWindow(0.5, start: 1.0, end: 1.4, style: style))
        XCTAssertTrue(PathConsumption.withinEditWindow(0.8, start: 1.0, end: 1.4, style: style))
        XCTAssertTrue(PathConsumption.withinEditWindow(1.55, start: 1.0, end: 1.4, style: style))
        XCTAssertFalse(PathConsumption.withinEditWindow(1.7, start: 1.0, end: 1.4, style: style))
    }

    /// Windowing must not smuggle in a second read's paths: the read-boundary
    /// gate still owns that, and it is stricter.
    func testReadBoundaryStillWins() {
        let track = Track(entityId: entityId, keyframes: [
            Keyframe(t: 0.0, position: CGPoint(x: 6, y: 24)),
            Keyframe(t: 3.0, position: CGPoint(x: 19, y: 12))])
        let first = ReadNode(title: "Base", tracks: [track])
        let second = ReadNode(title: "Reject")
        let steps = [PlayDiagram.BranchStep(node: first, startsAt: 0),
                     PlayDiagram.BranchStep(node: second, startsAt: 1.0)]
        // At 1.2 the first read's window has ended even though its own segment
        // runs to 3.0 — the arriving read owns the moment.
        let visible = PathConsumption.visibleTrackPaths(steps: steps, at: 1.2, style: .edit,
                                                        pinnedTracks: [entityId])
        XCTAssertTrue(visible.pieces.filter { $0.stepIndex == 0 }.isEmpty,
                      "a pin must not defeat the read-boundary gate")
    }
}
