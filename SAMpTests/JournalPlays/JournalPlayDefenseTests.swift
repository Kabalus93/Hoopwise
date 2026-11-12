import Foundation
import Testing
@testable import Hoopwise

/// Auto defense (12 November 2026, Luther): calculated spots with nudges,
/// matched by nearest player, switch everything, man / 2-3 / 3-2.
struct JournalPlayDefenseTests {
    typealias P = JournalCourtPoint
    typealias D = JournalPlayDiagram

    /// Half court (basket at (7.5, 1.575), y away from the baseline): 1 at
    /// the top with the ball, 2 on the right wing, 5 in the left corner.
    static let set = D(offense: [.init(number: 1, at: P(7.5, 9)), .init(number: 2, at: P(13, 5.5)),
                                 .init(number: 5, at: P(1.2, 1.5))],
                       defense: [.init(at: P(12, 5)), .init(at: P(7.5, 8)), .init(at: P(2, 2))], ball: 1)

    @Test func manIsMatchedByNearestOnePerPlayer() {
        let d = JournalPlayMath.applyingDefense(.man, to: [Self.set], court: .half)[0]
        #expect(d.defenseMode == .man)
        #expect(d.defense.map(\.guards) == [2, 1, 5])
        // A missing defender arrives for an unguarded player; extras go.
        var four = Self.set
        four.offense.append(.init(number: 3, at: P(4, 7)))
        #expect(JournalPlayMath.applyingDefense(.man, to: [four], court: .half)[0].defense.count == 4)
    }

    @Test func theBallHandlersDefenderStandsBetweenHimAndTheBasket() {
        let spot = JournalPlayMath.manSpot(guarding: P(7.5, 9), ball: P(7.5, 9), court: .half)
        #expect(abs(spot.x - 7.5) < 0.01)
        #expect(abs(spot.y - 7.5) < 0.01)               // 1.5 m off, toward the rim
        // Two passes away he sags toward the basket and the ball.
        let help = JournalPlayMath.manSpot(guarding: P(1.2, 8), ball: P(13, 6), court: .half)
        #expect(help.x > 2.5)
    }

    @Test func movingAPlayerMovesHisDefenderAndKeepsTheNudge() {
        var d = JournalPlayMath.applyingDefense(.man, to: [Self.set], court: .half)[0]
        let before = d.defense[0].at
        d = JournalPlayMath.nudging(defender: 0, to: P(before.x - 0.6, before.y), in: d, court: .half)
        d = JournalPlayMath.moving(player: 2, to: P(13, 8.5), in: d)
        d = JournalPlayMath.placingDefense(d, court: .half)
        let plain = JournalPlayMath.manSpot(guarding: P(13, 8.5), ball: P(7.5, 9), court: .half)
        #expect(abs(d.defense[0].at.x - (plain.x - 0.6)) < 0.05)
        #expect(abs(d.defense[0].at.y - plain.y) < 0.05)
    }

    @Test func aScreenSwitchesTheTwoDefendersAndTheSwitchCarries() {
        // 5 screens for 1 at the top; 1 dribbles off it to the right.
        var d = D(offense: [.init(number: 1, at: P(7.5, 9)), .init(number: 5, at: P(4, 3))], ball: 1,
                  actions: [.init(kind: .screen, player: 5, path: [P(4, 3), P(6.5, 8.2)]),
                            .init(kind: .dribble, player: 1, path: [P(7.5, 9), P(6.4, 7.4), P(9, 5)])])
        d.defense = [.init(at: P(7.5, 8)), .init(at: P(4, 2.5))]
        d = JournalPlayMath.applyingDefense(.man, to: [d], court: .half)[0]
        #expect(d.defense.map(\.guards) == [1, 5])
        let swaps = JournalPlayMath.switches(d)
        #expect(swaps.count == 1 && Set([swaps[0].a, swaps[0].b]) == [1, 5])
        #expect(JournalPlayMath.guards(d, at: .infinity, switches: swaps) == [5, 1])
        #expect(JournalPlayMath.startOfNextStep(after: d, court: .half).defense.map(\.guards) == [5, 1])
        // Playback: the defenders end on their new men.
        let end = JournalPlayMath.frame(d, at: 1, court: .half)
        #expect(end.defense.count == 2)
        // The dribble waits for the screen to be set.
        let plan = JournalPlayMath.schedule(d)
        #expect(abs(plan.items[1].start - 1.1) < 0.001)
        #expect(end.defense[1].distance(to: P(9, 5)) < 2)  // X5 now on 1
    }

    @Test func zonesHaveFiveSpotsThatShiftToTheBall() {
        let left = JournalPlayMath.zoneSpots(.zone23, ball: P(2, 6), court: .half)
        let right = JournalPlayMath.zoneSpots(.zone23, ball: P(13, 6), court: .half)
        #expect(left.count == 5)
        #expect(left.map(\.x).reduce(0, +) < right.map(\.x).reduce(0, +))
        let d = JournalPlayMath.applyingDefense(.zone32, to: [Self.set], court: .half)[0]
        #expect(d.defense.count == 5 && d.defense.allSatisfy { $0.guards == nil })
    }

    @Test func byHandStepsAreUnchangedAndOldDrawingsStillRead() throws {
        #expect(JournalPlayMath.placingDefense(Self.set, court: .half) == Self.set)
        let json = try JSONEncoder().encode(Self.set)
        #expect(String(decoding: json, as: UTF8.self).contains("defenseMode") == false)
        let auto = JournalPlayMath.applyingDefense(.man, to: [Self.set], court: .half)[0]
        let back = try JSONDecoder().decode(D.self, from: JSONEncoder().encode(auto))
        #expect(back == auto)
        // Turning it off leaves the defenders where they stand, by hand.
        let off = JournalPlayMath.applyingDefense(nil, to: [auto], court: .half)[0]
        #expect(off.defenseMode == nil && off.defense.map(\.at) == auto.defense.map(\.at))
    }
}
