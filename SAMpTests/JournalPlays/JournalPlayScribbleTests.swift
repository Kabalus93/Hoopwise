import Foundation
import Testing
@testable import Hoopwise

/// Scribble (16 November 2026, Luther): Pencil strokes on the play page read
/// as cuts, passes, screens and dribbles. Strokes are drawn here in metres on
/// the default half-court alignment: 1 (7.5, 9.6) with the ball, 2 (12.6,
/// 6.6), 3 (2.4, 6.6), 4 (13.9, 1.2), 5 (1.1, 1.2).
struct JournalPlayScribbleTests {
    typealias P = JournalCourtPoint

    static let five = JournalPlayMath.defaultAlignment(.half)

    /// A straight stroke from a to b, as the Pencil samples it.
    static func line(_ a: P, _ b: P) -> [P] {
        (0...20).map { k in
            let t = Double(k) / 20
            return P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
    }

    /// Dashes from a toward b: `count` strokes of `dash` metres, `gap` apart.
    static func dashes(_ a: P, _ b: P, count: Int, dash: Double = 0.6, gap: Double = 0.45) -> [[P]] {
        let length = a.distance(to: b)
        let u = P((b.x - a.x) / length, (b.y - a.y) / length)
        return (0..<count).map { k in
            let s = Double(k) * (dash + gap)
            return line(P(a.x + u.x * s, a.y + u.y * s), P(a.x + u.x * (s + dash), a.y + u.y * (s + dash)))
        }
    }

    @Test func anArrowFromAPlayerIsACut() throws {
        let strokes = [Self.line(P(2.6, 6.4), P(6.5, 2.5)),
                       Self.line(P(6.5, 2.5), P(6.0, 2.6)),
                       Self.line(P(6.5, 2.5), P(6.4, 3.0))]
        let read = JournalPlayScribble.read(strokes, on: Self.five)
        let cut = try #require(read.diagram.actions.last)
        #expect(cut.kind == .cut)
        #expect(cut.player == 3)
        #expect(try #require(cut.path.last).distance(to: P(6.5, 2.5)) < 0.15)
        #expect(read.used == [0, 1, 2], "the arrowhead goes with the line")
    }

    @Test func anArrowheadDrawnInTheSameStrokeIsTrimmedOff() throws {
        let stroke = Self.line(P(2.6, 6.4), P(6.5, 2.5)) + Self.line(P(6.5, 2.5), P(6.0, 2.6)).dropFirst()
        let read = JournalPlayScribble.read([stroke], on: Self.five)
        let cut = try #require(read.diagram.actions.last)
        #expect(cut.kind == .cut)
        #expect(try #require(cut.path.last).distance(to: P(6.5, 2.5)) < 0.2)
    }

    @Test func dashesToATeammateAreAPass() throws {
        var strokes = Self.dashes(P(7.8, 9.4), P(12.4, 6.7), count: 5)
        strokes.append(Self.line(P(12.0, 6.6), P(11.6, 6.4)) + Self.line(P(11.6, 6.4), P(11.8, 7.0)).dropFirst())
        let read = JournalPlayScribble.read(strokes, on: Self.five)
        let pass = try #require(read.diagram.actions.last)
        #expect(pass.kind == .pass)
        #expect(pass.player == 1)
        #expect(pass.receiver == 2)
        #expect(read.used.count == strokes.count)
    }

    @Test func aLineEndingInABarIsAScreen() throws {
        let strokes = [Self.line(P(1.3, 1.4), P(4.5, 4.5)),
                       Self.line(P(4.1, 4.9), P(4.9, 4.1))]
        let read = JournalPlayScribble.read(strokes, on: Self.five)
        let screen = try #require(read.diagram.actions.last)
        #expect(screen.kind == .screen)
        #expect(screen.player == 5)
        #expect(try #require(screen.path.last).distance(to: P(4.5, 4.5)) < 0.3)
    }

    @Test func aZigzagIsADribbleAlongItsMiddle() throws {
        let zigzag = (0...24).map { k in P(7.5 + (k.isMultiple(of: 2) ? 0.35 : -0.35), 9.4 - Double(k) * 0.2) }
        let read = JournalPlayScribble.read([zigzag], on: Self.five)
        let dribble = try #require(read.diagram.actions.last)
        #expect(dribble.kind == .dribble)
        #expect(dribble.player == 1)
        #expect(dribble.path.allSatisfy { abs($0.x - 7.5) < 0.3 }, "the dribble runs down the middle of the zigzag")
    }

    /// The ball rule (17 Nov 2026, Luther): only a player holding a ball
    /// passes or dribbles; from anyone else the strokes stay ink.
    @Test func onlyAPlayerWithTheBallPassesOrDribbles() throws {
        // 2 has no ball: dashes from 2 to 4 stay ink.
        let pass = JournalPlayScribble.read(Self.dashes(P(12.6, 6.4), P(13.8, 1.5), count: 4), on: Self.five)
        #expect(pass.diagram.actions.isEmpty)
        #expect(pass.used.isEmpty)
        // 3 zigzags without a ball: ink.
        let zigzag = (0...24).map { k in P(2.4 + (k.isMultiple(of: 2) ? 0.35 : -0.35), 6.4 - Double(k) * 0.2) }
        #expect(JournalPlayScribble.read([zigzag], on: Self.five).diagram.actions.isEmpty)
        // Once 1 has passed to 2, 2 may pass on.
        let first = JournalPlayScribble.read(Self.dashes(P(7.8, 9.4), P(12.4, 6.7), count: 5), on: Self.five)
        let onward = JournalPlayScribble.read(Self.dashes(P(12.6, 6.4), P(13.8, 1.5), count: 4), on: first.diagram)
        #expect(onward.diagram.actions.last?.kind == .pass)
        #expect(onward.diagram.actions.last?.player == 2)
        // The editor's own rule agrees.
        #expect(JournalPlayStepEditor.mayStart(.pass, by: 1, in: Self.five))
        #expect(!JournalPlayStepEditor.mayStart(.pass, by: 2, in: Self.five))
        #expect(!JournalPlayStepEditor.mayStart(.dribble, by: 3, in: Self.five))
        #expect(JournalPlayStepEditor.mayStart(.cut, by: 3, in: Self.five), "cuts need no ball")
        #expect(JournalPlayStepEditor.mayStart(.pass, by: 2, in: first.diagram), "2 caught it")
        #expect(!JournalPlayStepEditor.mayStart(.pass, by: 1, in: first.diagram), "1 let it go")
    }

    @Test func aCurvedCutIsNotMistakenForAZigzag() throws {
        let curve = (0...30).map { k -> P in
            let t = Double(k) / 30
            return P(2.6 + 4 * t, 6.4 - 4 * t * t)
        }
        let read = JournalPlayScribble.read([curve], on: Self.five)
        #expect(read.diagram.actions.last?.kind == .cut)
    }

    @Test func writingThatStartsOnNoPlayerStaysInk() {
        let strokes = [Self.line(P(8, 12.5), P(11, 12.8)), Self.line(P(9, 12), P(9.2, 12.6))]
        let read = JournalPlayScribble.read(strokes, on: Self.five)
        #expect(read.diagram.actions.isEmpty)
        #expect(read.used.isEmpty)
    }

    @Test func aPassCanFollowACutToWhereTheCutterEnds() throws {
        var strokes = [Self.line(P(2.6, 6.4), P(6.5, 2.5))]
        strokes += Self.dashes(P(7.3, 9.3), P(6.6, 2.9), count: 6)
        let read = JournalPlayScribble.read(strokes, on: Self.five)
        #expect(read.diagram.actions.map(\.kind) == [.cut, .pass])
        #expect(read.diagram.actions.last?.receiver == 3)
    }
}
