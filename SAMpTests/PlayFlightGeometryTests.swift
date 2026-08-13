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
        var passerId: UUID = UUID()
    }

    /// The crooked-path configuration: passer and receiver last moved in
    /// UNRELATED directions, so their hand offsets point different ways. This
    /// is the ordinary case in a real play, and it is what put a 32.8° hook in
    /// the drawn line when the offset was blended along the flight instead of
    /// living in its endpoints.
    private func crossingPassFixture() -> Fixture {
        let passer = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let receiver = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let passerTrack = Track(entityId: passer, keyframes: [
            Keyframe(t: 0, position: CGPoint(x: 25, y: 34)),
            Keyframe(t: 1.0, position: CGPoint(x: 25, y: 28))])       // toward the rim
        let receiverTrack = Track(entityId: receiver, keyframes: [
            Keyframe(t: 0, position: CGPoint(x: 4, y: 20)),
            Keyframe(t: 1.2, position: CGPoint(x: 10, y: 20))])       // across
        let node = ReadNode(title: "Base",
                            tracks: [passerTrack, receiverTrack],
                            possessions: [
                                Possession(holderId: passer, start: 0, end: 1.0,
                                           release: .pass(toId: receiver)),
                                Possession(holderId: receiver, start: 1.5)])
        return Fixture(node: node, positionOf: { id, t in
            if id == passer { return passerTrack.position(at: t) ?? .zero }
            if id == receiver { return receiverTrack.position(at: t) ?? .zero }
            return .zero
        }, passerId: passer)
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
        return Fixture(node: node, positionOf: { id, t in
            if id == passer { return passerTrack.position(at: t) ?? .zero }
            if id == receiver { return receiverTrack.position(at: t) ?? .zero }
            return .zero
        }, passerId: passer)
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
        return Fixture(node: node, positionOf: { id, t in
            id == shooter ? (track.position(at: t) ?? .zero) : .zero
        }, passerId: shooter)
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

    // MARK: - Curve smoothness

    /// Worst turn between consecutive polyline segments, in degrees, and the
    /// worst bow away from the chord, in feet.
    private func crookedness(_ points: [CGPoint]) -> (turn: Double, bow: CGFloat) {
        var worstTurn: Double = 0
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            let v1 = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            guard hypot(v1.dx, v1.dy) > 0.0001, hypot(v2.dx, v2.dy) > 0.0001 else { continue }
            let cross = Double(v1.dx * v2.dy - v1.dy * v2.dx)
            let dot = Double(v1.dx * v2.dx + v1.dy * v2.dy)
            worstTurn = max(worstTurn, abs(atan2(cross, dot)) * 180 / .pi)
        }
        let first = points[0], last = points[points.count - 1]
        var worstBow: CGFloat = 0
        for point in points {
            worstBow = max(worstBow, distance(point, toSegment: first, last))
        }
        return (worstTurn, worstBow)
    }

    /// A PASS IS A STRAIGHT LINE.
    ///
    /// This is the test that exists because it once failed. Holding the ball
    /// beside its holder means the release point is off the centre line, and an
    /// earlier revision resolved that by blending the offset away over 0.1s at
    /// each end — which put a hook in the DRAWN path: 32.8° of turn and 1.54 ft
    /// of bow on this configuration, two players who last moved in unrelated
    /// directions. The offset lives in the endpoints now, so the line between
    /// two hands is straight.
    func testPassPathIsStraight() {
        let fixture = crossingPassFixture()
        guard let flight = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                 heldOffsetFeet: tuck,
                                                 positionOf: fixture.positionOf).first?.flight
        else { return XCTFail("no pass authored") }
        let measured = crookedness(flight.polyline())
        XCTAssertLessThan(measured.turn, 1.0,
                          String(format: "pass path turns %.1f° — it must be straight",
                                 measured.turn))
        XCTAssertLessThan(measured.bow, 0.01,
                          String(format: "pass path bows %.2f ft off its own chord",
                                 measured.bow))
    }

    /// A SHOT ARCS, SMOOTHLY. It is the one flight allowed to curve, so the
    /// test cannot just demand straightness — it demands that the curvature is
    /// gentle and never reverses, which is what separates a parabola from a
    /// hook at the hand.
    func testShotArcIsSmoothAndNeverReverses() {
        let fixture = shotFixture()
        guard let flight = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                 heldOffsetFeet: tuck,
                                                 positionOf: fixture.positionOf).first?.flight
        else { return XCTFail("no shot authored") }
        let points = flight.polyline()
        XCTAssertLessThan(crookedness(points).turn, 12.0, "shot arc has a kink in it")

        var sign = 0
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 0.0001 else { continue }
            let now = cross > 0 ? 1 : -1
            if sign == 0 { sign = now }
            XCTAssertEqual(now, sign, "the shot arc changes direction — that is a hook, not an arc")
        }
    }

    /// The hand offset is REAL and is what the endpoints carry — without it the
    /// straightness test above would pass trivially on a fixture that never
    /// exercised the offset at all.
    func testFlightRunsHandToHandNotCentreToCentre() {
        let fixture = passFixture()
        guard let flight = fixture.node.releases(passSpeed: passSpeed, shotSpeed: shotSpeed,
                                                 heldOffsetFeet: tuck,
                                                 positionOf: fixture.positionOf).first?.flight
        else { return XCTFail("no release authored") }
        let passerCentre = fixture.positionOf(fixture.passerId, 1.0)
        let offset = hypot(flight.from.x - passerCentre.x, flight.from.y - passerCentre.y)
        XCTAssertEqual(Double(offset), Double(tuck), accuracy: 0.001,
                       "the flight must start at the hand, one held-offset from the centre")
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
