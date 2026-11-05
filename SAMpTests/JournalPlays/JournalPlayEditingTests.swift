import Foundation
import Testing
@testable import Hoopwise

@Suite("Drawing a play")
struct JournalPlayEditingTests {
    private typealias P = JournalCourtPoint
    private let entry = JournalPlayMathTests.entry

    @Test func aNewPlayStartsFiveOutWithTheBallAtTheTop() {
        for court in JournalCourtKind.allCases {
            let start = JournalPlayMath.defaultAlignment(court)
            #expect(start.offense.map(\.number) == [1, 2, 3, 4, 5])
            #expect(start.ball == 1)
            for player in start.offense {
                #expect((0...court.size.width).contains(player.at.x) && (0...court.size.height).contains(player.at.y))
            }
        }
    }

    @Test func courtsConvertBothWays() {
        let full = JournalPlayMath.converted(entry, from: .half, to: .full)
        // The basket end goes right: the baseline (y 0) is x 28.
        #expect(full.player(5)?.at == P(28 - 0.7, 11.6))
        let back = JournalPlayMath.converted(full, from: .full, to: .half)
        let points = { (d: JournalPlayDiagram) in d.offense.map(\.at) + d.actions.flatMap(\.path) + d.defense.map(\.at) }
        #expect(zip(points(back), points(entry)).allSatisfy { $0.distance(to: $1) < 1e-9 })
        #expect(JournalPlayMath.converted(entry, from: .half, to: .half) == entry)
    }

    @Test func aFingerPathKeepsOnlyItsBends() {
        let straight = (0...20).map { P(Double($0) * 0.3, 1 + (($0 % 2 == 0) ? 0 : 0.05)) }
        #expect(JournalPlayMath.simplified(straight) == [P(0, 1), P(6, 1)])
        let corner = (0...10).map { P(Double($0) * 0.4, 0) } + (1...10).map { P(4, Double($0) * 0.4) }
        #expect(JournalPlayMath.simplified(corner) == [P(0, 0), P(4, 0), P(4, 4)])
        let zigzag = (0...40).map { P(Double($0) * 0.5, $0 % 2 == 0 ? 0 : 2) }
        #expect(JournalPlayMath.simplified(zigzag).count <= 5)
    }

    @Test func touchesHitTheNearestThing() {
        var diagram = entry
        diagram.defense = [.init(at: P(7.5, 3.85))]
        #expect(JournalPlayMath.hit(P(7.6, 10.2), in: diagram, radius: 0.8) == .player(1))
        #expect(JournalPlayMath.hit(P(7.4, 3.9), in: diagram, radius: 0.8) == .defender(0))
        // 5's cut (the second action) ends at (2.9, 0.7).
        #expect(JournalPlayMath.hit(P(3.0, 0.8), in: diagram, radius: 0.8) == .actionEnd(1))
        // Half-way along 1's pass to 4 (the first action).
        #expect(JournalPlayMath.hit(P(7.6, 8.1), in: diagram, radius: 0.8) == .action(0))
        #expect(JournalPlayMath.hit(P(1, 12), in: diagram, radius: 0.8) == nil)
        // Two defenders on one spot: the one on top (drawn last) is hit.
        diagram.defense.append(.init(at: P(7.5, 3.85)))
        #expect(JournalPlayMath.hit(P(7.5, 3.85), in: diagram, radius: 0.8) == .defender(1))
    }

    @Test func aNewLineStartsWhereThePlayerEndedUp() {
        // 5 already ran to (2.9, 0.7): touching either spot draws from there.
        let fromEnd = JournalPlayMath.lineStart(at: P(3.1, 0.8), in: entry, radius: 0.8)
        #expect(fromEnd?.player == 5 && fromEnd?.from == P(2.9, 0.7))
        let fromStart = JournalPlayMath.lineStart(at: P(11.5, 0.8), in: entry, radius: 0.8)
        #expect(fromStart?.player == 5 && fromStart?.from == P(2.9, 0.7))
    }

    @Test func aPassSnapsToTheNearestTeammate() throws {
        let added = try #require(JournalPlayMath.adding(.pass, by: 1, along: [P(7.5, 10.3), P(13, 4)],
                                                    to: entry, radius: 0.8))
        let pass = try #require(added.actions.last)
        // 2 has cut to (14, 3), so the pass goes there.
        #expect(pass.receiver == 2 && pass.path == [P(7.5, 10.3), P(14, 3)])
        // Far from everyone: no pass.
        #expect(JournalPlayMath.adding(.pass, by: 1, along: [P(7.5, 10.3), P(1, 13)], to: entry, radius: 0.8) == nil)
    }

    @Test func aTapIsNotALine() {
        #expect(JournalPlayMath.adding(.cut, by: 3, along: [P(1.3, 7), P(1.5, 7.1)], to: entry, radius: 0.8) == nil)
        let cut = JournalPlayMath.adding(.cut, by: 3, along: [P(1.3, 7), P(2.3, 6), P(3.3, 5)], to: entry, radius: 0.8)
        #expect(cut?.actions.last?.path == [P(1.3, 7), P(3.3, 5)])
    }

    @Test func movingAPlayerTakesTheirLinesAlong() {
        // 5 moves before his cut: the cut now starts at his new spot.
        let moved = JournalPlayMath.moving(player: 5, to: P(12, 1), in: entry)
        #expect(moved.player(5)?.at == P(12, 1))
        #expect(moved.actions[1].path.first == P(12, 1))
        // 4 moves: a pass that landed on 4 lands on the new spot.
        var snapped = entry
        snapped.actions[0].path = [P(7.5, 10.3), P(7.5, 5.9)]
        let receiver = JournalPlayMath.moving(player: 4, to: P(7.5, 6.5), in: snapped)
        #expect(receiver.actions[0].path.last == P(7.5, 6.5))
        // 1 moves: the pass he throws leaves from the new spot.
        #expect(JournalPlayMath.moving(player: 1, to: P(8, 10), in: snapped).actions[0].path.first == P(8, 10))
    }

    @Test func movingTheEndOfALineMovesWhatFollows() {
        var diagram = entry
        // 5 rolls on from the end of his cut.
        diagram.actions.append(.init(kind: .cut, player: 5, path: [P(2.9, 0.7), P(4, 2)]))
        let moved = JournalPlayMath.moving(endOf: 1, to: P(3.5, 1), in: diagram)
        #expect(moved.actions[1].path.last == P(3.5, 1))
        #expect(moved.actions[3].path.first == P(3.5, 1))
    }

    @Test func erasingTakesLinesAndDefendersButNotPlayers() {
        var diagram = entry
        diagram.defense = [.init(at: P(7.5, 3.85))]
        #expect(JournalPlayMath.erasing(.defender(0), in: diagram).defense.isEmpty)
        #expect(JournalPlayMath.erasing(.action(2), in: diagram).actions.map(\.kind) == [.pass, .cut])
        #expect(JournalPlayMath.erasing(.player(1), in: diagram) == diagram)
    }
}
