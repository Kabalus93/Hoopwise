import XCTest
import PencilKit
@testable import Hoopwise

/// The Coach board's editor additions (19 Nov 2026, Luther): defenders move
/// with the Cut tool, the five lanes, and annotations kept with a step.
final class BoardDrawingExtrasTests: XCTestCase {

    private func board() -> JournalPlayDiagram {
        var d = JournalPlayMath.defaultAlignment(.half)
        d.defense = [.init(at: JournalCourtPoint(5, 5)), .init(at: JournalCourtPoint(10, 5))]
        d.defenseMode = nil
        return d
    }

    func testACutCanStartFromAHandDrawnDefender() throws {
        let d = board()
        XCTAssertNil(JournalPlayMath.lineStart(at: JournalCourtPoint(10, 5), in: d, radius: 0.8),
                     "only the Cut tool asks for defenders")
        let start = try XCTUnwrap(JournalPlayMath.lineStart(at: JournalCourtPoint(10, 5), in: d, radius: 0.8, defenders: true))
        XCTAssertEqual(start.player, JournalPlayDiagram.defenderActor(1))
        let cut = try XCTUnwrap(JournalPlayMath.adding(.cut, by: start.player,
                                                       along: [start.from, JournalCourtPoint(10, 9)], to: d, radius: 0.8))
        // Playback runs it, and the next step starts with him there.
        XCTAssertEqual(JournalPlayMath.frame(cut, at: 1).defense[1], JournalCourtPoint(10, 9))
        XCTAssertEqual(JournalPlayMath.frame(cut, at: 1).defense[0], JournalCourtPoint(5, 5))
        XCTAssertEqual(JournalPlayMath.startOfNextStep(after: cut).defense[1].at, JournalCourtPoint(10, 9))
        // Auto defense places defenders itself: no lines from them then.
        var auto = d
        auto.defenseMode = .man
        XCTAssertNil(JournalPlayMath.lineStart(at: JournalCourtPoint(10, 5), in: auto, radius: 0.8, defenders: true))
        let applied = JournalPlayMath.applyingDefense(.man, to: [cut], court: .half)
        XCTAssertFalse(applied[0].actions.contains { JournalPlayDiagram.defenderIndex($0.player) != nil })
    }

    func testRemovingADefenderKeepsTheOthersLines() throws {
        var d = board()
        d = try XCTUnwrap(JournalPlayMath.adding(.cut, by: JournalPlayDiagram.defenderActor(0),
                                                 along: [JournalCourtPoint(5, 5), JournalCourtPoint(5, 9)], to: d, radius: 0.8))
        d = try XCTUnwrap(JournalPlayMath.adding(.cut, by: JournalPlayDiagram.defenderActor(1),
                                                 along: [JournalCourtPoint(10, 5), JournalCourtPoint(10, 9)], to: d, radius: 0.8))
        let out = JournalPlayMath.removing(defender: 0, from: d)
        XCTAssertEqual(out.defense.count, 1)
        let lines = out.actions.filter { JournalPlayDiagram.defenderIndex($0.player) != nil }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].player, JournalPlayDiagram.defenderActor(0), "the second defender is now the first")
        XCTAssertEqual(lines[0].path.last, JournalCourtPoint(10, 9))
        // Dragging a defender takes his line's start with him.
        let moved = JournalPlayMath.moving(defender: 0, to: JournalCourtPoint(11, 5), in: out)
        XCTAssertEqual(moved.actions.first { $0.player == JournalPlayDiagram.defenderActor(0) }?.path.first,
                       JournalCourtPoint(11, 5))
    }

    func testLanesAndInkRoundTripAndOnlyWhenUsed() throws {
        var d = board()
        let plain = String(data: try JSONEncoder().encode(d), encoding: .utf8) ?? ""
        XCTAssertFalse(plain.contains("lanes") || plain.contains("ink"), "a drawing without them writes nothing new")
        d.lanes = true
        d.ink = Data([1, 2, 3])
        let back = try JSONDecoder().decode(JournalPlayDiagram.self, from: JSONEncoder().encode(d))
        XCTAssertTrue(back.lanes)
        XCTAssertEqual(back.ink, Data([1, 2, 3]))
        let next = JournalPlayMath.startOfNextStep(after: back)
        XCTAssertTrue(next.lanes, "lanes stay on")
        XCTAssertNil(next.ink, "a step's annotations are its own")
    }

    /// Ink kept with a step lands on the same spot of the court at any size.
    func testKeptInkFollowsTheCourtSize() throws {
        let points = (0...10).map { i in
            PKStrokePoint(location: CGPoint(x: 100 + Double(i) * 10, y: 200 + Double(i) * 5), timeOffset: Double(i) * 0.02,
                          size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let drawn = PKDrawing(strokes: [stroke])
        let data = try XCTUnwrap(PlayInkImages.data(drawn, scale: 30))
        let back = PlayInkImages.drawing(data, scale: 30)
        XCTAssertEqual(back.bounds.midX, drawn.bounds.midX, accuracy: 1)
        XCTAssertEqual(back.bounds.width, drawn.bounds.width, accuracy: 1)
        let bigger = PlayInkImages.drawing(data, scale: 60)
        XCTAssertEqual(bigger.bounds.midX, drawn.bounds.midX * 2, accuracy: 2, "twice the court, twice as far")
        XCTAssertNil(PlayInkImages.data(PKDrawing(), scale: 30), "no ink, nothing kept")
    }
}
