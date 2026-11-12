import Testing
@testable import Hoopwise

struct JournalPlayMathTests {
    typealias P = JournalCourtPoint

    /// Zone-23's high-post entry: 1 at the top passes to 4 at the free-throw
    /// line; 5 runs the baseline; 2 drifts to the corner.
    static let entry = JournalPlayDiagram(
        offense: [
            .init(number: 1, at: P(7.5, 10.3)), .init(number: 2, at: P(13.7, 7)),
            .init(number: 3, at: P(1.3, 7)), .init(number: 4, at: P(7.5, 5.9)), .init(number: 5, at: P(11.6, 0.7)),
        ],
        defense: [.init(at: P(5.5, 7.5)), .init(at: P(9.5, 7.5), isRead: true)],
        ball: 1,
        actions: [
            .init(kind: .pass, player: 1, path: [P(7.5, 9.7), P(7.5, 6.5)], receiver: 4),
            .init(kind: .cut, player: 5, path: [P(11.6, 0.7), P(6, 0.7), P(2.9, 0.7)]),
            .init(kind: .dribble, player: 2, path: [P(13.7, 7), P(14, 3)]),
        ])

    @Test func endPositionsFollowTheActions() {
        #expect(JournalPlayMath.endPosition(of: 5, in: Self.entry) == P(2.9, 0.7))
        #expect(JournalPlayMath.endPosition(of: 2, in: Self.entry) == P(14, 3))
        // A pass doesn't move the passer.
        #expect(JournalPlayMath.endPosition(of: 1, in: Self.entry) == P(7.5, 10.3))
        #expect(JournalPlayMath.endPosition(of: 9, in: Self.entry) == nil)
    }

    @Test func theNextStepStartsWhereThisOneEnds() {
        let next = JournalPlayMath.startOfNextStep(after: Self.entry)
        #expect(next.ball == 4)
        #expect(next.actions.isEmpty)
        #expect(next.player(5)?.at == P(2.9, 0.7))
        #expect(next.player(4)?.at == P(7.5, 5.9))
        // Defenders stay; the next step moves them if it needs to.
        #expect(next.defense == Self.entry.defense)
    }

    @Test func endSpotsAreThePlayersWhoMove() {
        let spots = JournalPlayMath.endSpots(Self.entry)
        #expect(spots.map(\.number) == [2, 5])
        #expect(spots.first?.at == P(14, 3))
    }

    @Test func aPassToNobodyMovingFliesWhileOthersRun() {
        // 1's pass to a standing 4 is drawn first: it leaves at once, while
        // 5 and 2 run (moves 1.5 beats, the pass 1).
        #expect(JournalPlayMath.playBeats(Self.entry) == 1.5)
        let start = JournalPlayMath.frame(Self.entry, at: 0)
        #expect(start.players[5] == P(11.6, 0.7))
        #expect(start.ball == P(7.5, 10.3))  // with 1
        let mid = JournalPlayMath.frame(Self.entry, at: 1.0 / 3)  // half a beat
        #expect(mid.ball.map { abs($0.y - 8.1) < 0.001 } == true)
        let end = JournalPlayMath.frame(Self.entry, at: 1)
        #expect(end.ball == P(7.5, 5.9))  // with 4
        #expect(end.players[5] == P(2.9, 0.7))
    }

    @Test func aPassToACutterLandsAsTheyArrive() {
        // Getafe Wave's outlet (Luther, 12 Nov 2026): 4 sprints up the
        // wing, 1 passes ahead to where 4 is going, then 1 runs. The ball
        // used to fly first and jump back to 4 at the start.
        let outlet = JournalPlayDiagram(
            offense: [.init(number: 1, at: P(0.25, 6.66)), .init(number: 4, at: P(0.43, 12.45))], ball: 1,
            actions: [.init(kind: .cut, player: 4, path: [P(0.43, 12.45), P(12.08, 12.37)]),
                      .init(kind: .pass, player: 1, path: [P(0.25, 6.66), P(12.08, 12.37)], receiver: 4),
                      .init(kind: .cut, player: 1, path: [P(0.25, 6.66), P(18.88, 2.43)])])
        let plan = JournalPlayMath.schedule(outlet)
        #expect(plan.items[1].start == 0.5 && plan.items[1].end == 1.5)   // lands with 4's arrival
        #expect(abs(plan.items[2].start - 0.85) < 0.001)                  // 1 goes after letting go
        // While the ball is in the air nobody holds it; it lands on 4.
        let thrown = JournalPlayMath.frame(outlet, at: 1.0 / plan.total)
        #expect(thrown.balls.first?.inFlight == true)
        let caught = JournalPlayMath.frame(outlet, at: 1.5 / plan.total)
        #expect(caught.ball == P(12.08, 12.37))
        #expect(caught.players[4] == P(12.08, 12.37))
    }

    @Test func aReceiverWaitsForTheCatchBeforeMovingOn() {
        // 1 passes to 2, then 2 drives: the drive starts on the catch.
        let catchAndGo = JournalPlayDiagram(
            offense: [.init(number: 1, at: P(7.5, 9.6)), .init(number: 2, at: P(12.6, 6.6))], ball: 1,
            actions: [.init(kind: .pass, player: 1, path: [P(7.5, 9.6), P(12.6, 6.6)], receiver: 2),
                      .init(kind: .dribble, player: 2, path: [P(12.6, 6.6), P(8, 1.5)])])
        let plan = JournalPlayMath.schedule(catchAndGo)
        #expect(plan.items[1].start == 1 && plan.total == 2.5)
    }

    @Test func aHandOffGoesToItsReceiverAndCountsAsTheBall() {
        // 5 dribbles to the wing, hands off to 2 coming around.
        let dho = JournalPlayDiagram(
            offense: [.init(number: 5, at: P(7.5, 8)), .init(number: 2, at: P(13, 4))], ball: 5,
            actions: [.init(kind: .dribble, player: 5, path: [P(7.5, 8), P(10.5, 7)]),
                      .init(kind: .cut, player: 2, path: [P(13, 4), P(11.3, 7.6)]),
                      .init(kind: .handoff, player: 5, path: [P(10.5, 7), P(11.3, 7.6)], receiver: 2)])
        #expect(JournalPlayMath.ballsAfter(dho) == [2])
        #expect(JournalPlayMath.playBeats(dho) == 2.1)  // 1.5 + 0.6
        #expect(JournalPlayMath.frame(dho, at: 1).ball == P(11.3, 7.6))
    }

    @Test func aPlayerWhoPassesAndCutsThrowsFirst() {
        // 1 passes to 2 and basket-cuts: the ball leaves before 1 runs.
        let passAndCut = JournalPlayDiagram(
            offense: [.init(number: 1, at: P(7.5, 9.6)), .init(number: 2, at: P(12.6, 6.6))], ball: 1,
            actions: [.init(kind: .pass, player: 1, path: [P(7.5, 9.6), P(12.6, 6.6)], receiver: 2),
                      .init(kind: .cut, player: 1, path: [P(7.5, 9.6), P(7.5, 2.2)])])
        // The pass takes beat 0…1; 1 sets off just after letting go (0.35).
        let total = JournalPlayMath.playBeats(passAndCut)
        #expect(abs(total - 1.85) < 0.001)
        let throwing = JournalPlayMath.frame(passAndCut, at: 0.3 / total)
        #expect(throwing.players[1] == P(7.5, 9.6))
        #expect(throwing.balls.first?.inFlight == true)
        let cutting = JournalPlayMath.frame(passAndCut, at: 1.2 / total)
        #expect(cutting.ball == P(12.6, 6.6))  // with 2
        #expect(cutting.players[1].map { $0.y < 9.6 && $0.y > 2.2 } == true)
        #expect(JournalPlayMath.frame(passAndCut, at: 1).players[1] == P(7.5, 2.2))
    }

    @Test func aPlayerWhoDribblesThenPassesThrowsAfter() {
        // 1 drives to the wing, then passes to 2 in the corner.
        let driveAndKick = JournalPlayDiagram(
            offense: [.init(number: 1, at: P(7.5, 10.3)), .init(number: 2, at: P(14.4, 4.1))], ball: 1,
            actions: [.init(kind: .dribble, player: 1, path: [P(7.5, 10.3), P(13.1, 7.4)]),
                      .init(kind: .pass, player: 1, path: [P(13.1, 7.4), P(14.4, 4.1)], receiver: 2)])
        // Moves first (0…0.6), the ball with 1 as he drives.
        let driving = JournalPlayMath.frame(driveAndKick, at: 0.3)
        #expect(driving.ball == driving.players[1])
        #expect(JournalPlayMath.frame(driveAndKick, at: 1).ball == P(14.4, 4.1))
    }

    @Test func withoutPassesTheWholeStepIsMovement() {
        var cutOnly = Self.entry
        cutOnly.actions.removeAll { $0.kind == .pass }
        let mid = JournalPlayMath.frame(cutOnly, at: 0.5)
        // 5's path is 8.7 m long; eased 0.5 is 0.5, so 4.35 m along.
        #expect(mid.players[5].map { abs($0.x - 7.25) < 0.001 } == true)
    }

    @Test func pointsAlongAPathGoByDistance() {
        let path = [P(0, 0), P(3, 0), P(3, 1)]
        #expect(JournalPlayMath.point(along: path, at: 0) == P(0, 0))
        #expect(JournalPlayMath.point(along: path, at: 0.5) == P(2, 0))
        #expect(JournalPlayMath.point(along: path, at: 1) == P(3, 1))
        #expect(JournalPlayMath.point(along: [P(1, 1)], at: 0.5) == P(1, 1))
        #expect(JournalPlayMath.eased(0) == 0 && JournalPlayMath.eased(1) == 1 && JournalPlayMath.eased(0.5) == 0.5)
    }
}
