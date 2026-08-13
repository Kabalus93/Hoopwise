import XCTest
import CoreGraphics
@testable import Hoopwise

/// A1 — THE BALL RIDES ITS OWN PATH.
///
/// The defect these pin: the flight resolver interpolated between TUCK-ADJUSTED
/// endpoints (holder centre + `ballHeldOffsetFeet`) while the canvas drew the
/// arc CENTRE-to-CENTRE, so the ball flew a constant ~1.9 ft off the line the
/// coach was looking at. A third copy inside the frame exporter re-lerped the
/// endpoints and lost the shot parabola entirely.
///
/// The fix is structural — one `BallFlight` feeds both — so these tests are
/// worth having only because they fail the moment someone re-derives either
/// side independently again. They sample through the two PUBLIC entry points a
/// renderer would actually use:
///
///   position  →  ReadNode.ballPosition(at:)      (what the canvas places)
///   curve     →  ReadNode.releases(...).flight   (what the canvas strokes)
final class PlayFlightGeometryTests: XCTestCase {

    private let passSpeed: Double = 34
    private let shotSpeed: Double = 26
    private let tuck: CGFloat = 1.9      // CourtLookParameters.ballHeldOffsetFeet

    // MARK: - Fixtures

    private struct Fixture {
        var node: ReadNode
        var positionOf: (UUID, Double) -> CGPoint
    }

    /// O1 dribbles up and passes to O2, who is cutting. Both players MOVE, so
    /// the holder-direction tuck is non-zero at each end — the condition the
    /// bug needed.
    private func passFixture() -> Fixture {
        let passer = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let receiver = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let passerTrack = Track(entityId: passer, keyframes: [
            Keyframe(t: 0, position: CGPoint(x: 25, y: 30)),
            Keyframe(t: 1.0, position: CGPoint(x: 22, y: 24)),
            Keyframe(t: 2.0, position: CGPoint(x: 20, y: 22))])
        let receiverTrack = Track(entityId: receiver, keyframes: [
            Keyframe(t: 0, position: CGPoint(x: 6, y: 26)),
            Keyframe(t: 1.6, position: CGPoint(x: 9, y: 14))])
        // Release at 1.0; the receiver's attach at 1.4 IS the arrival.
        let node = ReadNode(title: "Base",
                            tracks: [passerTrack, receiverTrack],
                            possessions: [
                                Possession(holderId: passer, start: 0, end: 1.0,
                                           release: .pass(toId: receiver)),
                                Possession(holderId: receiver, start: 1.4)])
        return Fixture(node: node) { id, t in
            if id == passer { return passerTrack.position(at: t) ?? .zero }
            if id == receiver { return receiverTrack.position(at: t) ?? .zero }
            return .zero
        }
    }

    /// O2 rises into a shot at the rim — the parabola case.
    private func shotFixture() -> Fixture {
        let shooter = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let rim = CGPoint(x: 25, y: 5.25)
        let track = Track(entityId: shooter, keyframes: [
            Keyframe(t: 0, position: CGPoint(x: 18, y: 20)),
            Keyframe(t: 1.2, position: CGPoint(x: 21, y: 14))])
        let node = ReadNode(title: "Base",
                            tracks: [track],
                            possessions: [
                                Possession(holderId: shooter, start: 0, end: 1.2,
                                           release: .shot(target: rim))])
        return Fixture(node: node) { id, t in
            id == shooter ? (track.position(at: t) ?? .zero) : .zero
        }
    }

    // MARK: - Geometry helpers

    /// Shortest distance from a point to a polyline, in court feet.
    private func distance(_ point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return .greatestFiniteMagnitude }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            best = min(best, distance(point, toSegment: points[index], points[index + 1]))
        }
        return best
    }

    private func distance(_ point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        return hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t))
    }

    /// Ten evenly spaced samples across a flight, measured against the drawn
    /// curve for that same release.
    private func assertBallRidesCurve(_ fixture: Fixture,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let releases = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                             heldOffsetFeet: tuck,
                                             positionOf: fixture.positionOf)
        XCTAssertEqual(releases.count, 1, "fixture should author exactly one release",
                       file: file, line: line)
        guard let release = releases.first else { return }
        let drawn = release.flight.polyline()          // exactly what is stroked

        for step in 0...9 {
            let progress = Double(step) / 9
            let time = release.departure + (release.arrival - release.departure) * progress
            let ball = fixture.node.ballPosition(at: time,
                                                 passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                 ballHome: .zero, heldOffsetFeet: tuck,
                                                 positionOf: fixture.positionOf)
            let off = distance(ball, toPolyline: drawn)
            XCTAssertLessThan(off, 0.1,
                              String(format: "ball is %.3f ft off its drawn arc at progress %.2f",
                                     off, progress),
                              file: file, line: line)
        }
    }

    // MARK: - The acceptance criterion

    func testBallRidesItsDrawnArcThroughAPass() {
        assertBallRidesCurve(passFixture())
    }

    func testBallRidesItsDrawnArcThroughAShot() {
        assertBallRidesCurve(shotFixture())
    }

    /// The tuck is a HELD-state affectation: past the blend, the ball is on the
    /// centre line, not beside it. This is the half a "compensating nudge" fix
    /// would have got wrong — it would have moved the drawn line to the ball
    /// instead of the ball to the line.
    func testTuckIsGoneThroughTheMiddleOfAFlight() {
        let fixture = passFixture()
        guard let release = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                  heldOffsetFeet: tuck,
                                                  positionOf: fixture.positionOf).first
        else { return XCTFail("no release authored") }
        let flight = release.flight
        XCTAssertGreaterThan(hypot(flight.releaseTuck.dx, flight.releaseTuck.dy), 0.5,
                             "fixture must actually carry a tuck, or it proves nothing")

        let middle = flight.position(atProgress: 0.5)
        let centreLine = CGPoint(x: flight.from.x + (flight.to.x - flight.from.x) * 0.5,
                                 y: flight.from.y + (flight.to.y - flight.from.y) * 0.5)
        XCTAssertLessThan(hypot(middle.x - centreLine.x, middle.y - centreLine.y), 0.01,
                          "mid-flight the ball belongs on the centre line")
    }

    /// …and the ball still LEAVES A HAND. Dropping the tuck outright would pop
    /// the ball sideways by 1.9 ft at the release and again at the catch, which
    /// is the regression the previous shape was written to avoid.
    func testNoPopAtReleaseOrCatch() {
        let fixture = passFixture()
        func ball(_ t: Double) -> CGPoint {
            fixture.node.ballPosition(at: t, passSpeed: passSpeed, shotSpeed: shotSpeed,
                                      ballHome: .zero, heldOffsetFeet: tuck,
                                      positionOf: fixture.positionOf)
        }
        let epsilon = 0.001
        let atRelease = hypot(ball(1.0 + epsilon).x - ball(1.0 - epsilon).x,
                              ball(1.0 + epsilon).y - ball(1.0 - epsilon).y)
        let atCatch = hypot(ball(1.4 + epsilon).x - ball(1.4 - epsilon).x,
                            ball(1.4 + epsilon).y - ball(1.4 - epsilon).y)
        XCTAssertLessThan(atRelease, 0.05, "ball jumped at the release")
        XCTAssertLessThan(atCatch, 0.05, "ball jumped at the catch")
    }

    /// A shot's arc is REAL: the parabola lifts the ball off the straight line
    /// between hand and rim. Pinned because the exporter used to draw the
    /// straight line while the canvas drew the arc.
    func testShotArcLeavesTheStraightLine() {
        let fixture = shotFixture()
        guard let flight = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                 heldOffsetFeet: tuck,
                                                 positionOf: fixture.positionOf).first?.flight
        else { return XCTFail("no shot authored") }
        let middle = flight.position(atProgress: 0.5)
        let chord = CGPoint(x: flight.from.x + (flight.to.x - flight.from.x) * 0.5,
                            y: flight.from.y + (flight.to.y - flight.from.y) * 0.5)
        XCTAssertGreaterThan(chord.y - middle.y, 1.0, "the shot should rise off its chord")
        // …and the remaining-path helper the exporter uses starts at the ball.
        let progress = 0.4
        let remaining = flight.remainingPolyline(from: progress)
        let at = flight.position(atProgress: progress)
        XCTAssertLessThan(hypot(remaining[0].x - at.x, remaining[0].y - at.y), 0.001)
        XCTAssertLessThan(distance(flight.position(atProgress: 0.7), toPolyline: remaining), 0.1)
    }

    /// ARRIVAL IS AUTHORED. The drawn line, the ball, and the timeline's
    /// arrival all take the receiver's attach — they used to split, with the
    /// line drawn to a distance ÷ speed estimate the ball never honoured.
    func testArrivalFollowsTheReceiversAttach() {
        let fixture = passFixture()
        guard let release = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                  heldOffsetFeet: tuck,
                                                  positionOf: fixture.positionOf).first
        else { return XCTFail("no release authored") }
        XCTAssertEqual(release.arrival, 1.4, accuracy: 0.0001)

        let possession = fixture.node.sortedPossessions[0]
        let arrival = fixture.node.arrivalTime(of: possession, passSpeed: passSpeed,
                                               shotSpeed: shotSpeed,
                                               positionOf: fixture.positionOf)
        XCTAssertEqual(arrival ?? 0, 1.4, accuracy: 0.0001,
                       "arrivalTime must agree with the flight it describes")
    }
}
