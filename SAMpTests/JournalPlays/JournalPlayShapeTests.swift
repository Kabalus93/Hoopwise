import Foundation
import Testing
@testable import Hoopwise

/// Lines drawn straight or curved (November 2026: a line followed the hand
/// and came out wobbly with a mouse or on a small screen).
struct JournalPlayShapeTests {
    typealias P = JournalCourtPoint

    /// A hand drawing a straight run: up to 40 cm of shake either side.
    static let shaky: [P] = (0...40).map { i -> P in
        let side: Double = i % 2 == 0 ? 0.4 : -0.4
        let size: Double = i % 3 == 0 ? 0.5 : 1
        return P(2 + Double(i) * 0.25, 5 + side * size)
    }

    @Test func aShakyStraightLineComesOutStraight() {
        let path = JournalPlayMath.shaped(Self.shaky, .straight)
        #expect(path.count == 2)
        #expect(path.first == Self.shaky.first && path.last == Self.shaky.last)
    }

    @Test func aClearTurnKeepsItsCorner() {
        // Down the lane, then out to the corner: an L.
        let down: [P] = (0...20).map { P(7.5, 8 - Double($0) * 0.3) }
        let out: [P] = (1...20).map { P(7.5 + Double($0) * 0.3, 2) }
        let l = down + out
        let path = JournalPlayMath.shaped(l, .straight)
        #expect(path.count == 3)
        #expect(path[1].distance(to: P(7.5, 2)) < 0.5)
    }

    @Test func curvedKeepsAFewBendsAndIgnoresTheShake() {
        let arc = (0...40).map { i -> P in
            let a = Double(i) / 40 * .pi
            let shake: Double = i % 2 == 0 ? 0.15 : -0.15
            return P(7.5 - 4 * cos(a) + shake, 4 + 4 * sin(a))
        }
        let path = JournalPlayMath.shaped(arc, .curved)
        #expect(path.count >= 3 && path.count <= 4)
        let action = JournalPlayDiagram.Action(kind: .cut, player: 1, path: path, shape: .curved)
        #expect(!action.isStraight)
        #expect(JournalPlayMath.drawnPath(action).count > path.count)
    }

    @Test func aTapTurnsALineCurvedThenStraight() {
        var diagram = JournalPlayDiagram(offense: [.init(number: 1, at: P(2, 5))],
                                         actions: [.init(kind: .cut, player: 1, path: [P(2, 5), P(12, 5)], shape: .straight)])
        diagram = JournalPlayMath.toggledShape(of: 0, in: diagram)
        #expect(diagram.actions[0].shape == .curved)
        #expect(diagram.actions[0].path.count == 3)
        #expect(abs(diagram.actions[0].path[1].y - 5) >= 0.6)
        // Its bend is found by touch and dragged.
        let bend = diagram.actions[0].path[1]
        #expect(JournalPlayMath.hit(bend, in: diagram, radius: 0.5) == .actionBend(0, 1))
        diagram = JournalPlayMath.moving(bend: 1, of: 0, to: P(7, 9), in: diagram)
        #expect(diagram.actions[0].path[1] == P(7, 9))
        diagram = JournalPlayMath.toggledShape(of: 0, in: diagram)
        #expect(diagram.actions[0].path == [P(2, 5), P(12, 5)])
        #expect(diagram.actions[0].isStraight)
    }

    @Test func linesFromBeforeShapesStayCurved() throws {
        let old = #"{"kind":"cut","player":1,"path":[{"x":1,"y":1},{"x":3,"y":4},{"x":6,"y":2}]}"#
        let action = try JSONDecoder().decode(JournalPlayDiagram.Action.self, from: Data(old.utf8))
        #expect(action.shape == nil)
        #expect(!action.isStraight)
    }

    @Test func playbackRunsAlongTheDrawnCurve() {
        let action = JournalPlayDiagram.Action(kind: .cut, player: 1, path: [P(2, 5), P(7, 9), P(12, 5)], shape: .curved)
        let diagram = JournalPlayDiagram(offense: [.init(number: 1, at: P(2, 5))], actions: [action])
        let end = JournalPlayMath.frame(diagram, at: 1).players[1]
        #expect(end == P(12, 5))
        // Midway the player is on the curve, which passes through the bend.
        let mid = try! #require(JournalPlayMath.frame(diagram, at: 0.5).players[1])
        #expect(abs(mid.x - 7) < 0.3 && abs(mid.y - 9) < 0.3)
    }
}
