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
        #expect(abs(spot.y - 7.9) < 0.01)               // an arm's length (1.1 m), toward the rim
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

/// The deeper rules (12 Nov 2026, Luther: "the zone only reacts to the ball
/// and disregards the other players' movement … make it really good").
struct JournalPlayDefenseDepthTests {
    typealias P = JournalCourtPoint

    @Test func aZoneDefenderShadesTheAttackerInHisArea() {
        // Ball at the top; 3 moves from the left wing to the left corner.
        let ball = P(7.5, 9.5)
        let wing = JournalPlayMath.zoneSpots(.zone23, ball: ball, players: [1: ball, 3: P(1.8, 6)], court: .half)
        let corner = JournalPlayMath.zoneSpots(.zone23, ball: ball, players: [1: ball, 3: P(0.8, 1.2)], court: .half)
        // Somebody follows 3: the zone is not the same with him elsewhere.
        #expect(wing != corner)
        let nearestToCorner = corner.map { $0.distance(to: P(0.8, 1.2)) }.min()!
        let nearestToCornerBefore = wing.map { $0.distance(to: P(0.8, 1.2)) }.min()!
        #expect(nearestToCorner < nearestToCornerBefore)
    }

    @Test func theZoneAlwaysProtectsThePaint() {
        // Everyone spread wide around the arc, the ball in a corner.
        let ball = P(0.8, 1.2)
        let players = [1: ball, 2: P(14.2, 1.2), 3: P(1.5, 7), 4: P(13.5, 7), 5: P(7.5, 9.5)]
        let spots = JournalPlayMath.zoneSpots(.zone32, ball: ball, players: players, court: .half)
        #expect(spots.contains { $0.distance(to: P(7.5, 3)) < 2.6 })
    }

    @Test func aWeakSideDefenderHelpsOnTheDrive() {
        // 1 drives to the rim from the right; 3 waits in the left corner.
        let players = [1: P(9, 3.2), 3: P(0.8, 1.2)]
        let guards: [Int?] = [1, 3]
        let own = [JournalPlayMath.manSpot(guarding: players[1]!, ball: players[1]!, court: .half),
                   JournalPlayMath.manSpot(guarding: players[3]!, ball: players[1]!, court: .half)].map(Optional.some)
        let team = JournalPlayMath.manTeamSpots(own, guards: guards, players: players, ball: players[1]!, court: .half)
        // X3 left 3 and stepped toward the driving line.
        #expect(team[1]!.distance(to: players[1]!) < own[1]!.distance(to: players[1]!))
        #expect(team[1]!.distance(to: players[3]!) > own[1]!.distance(to: players[3]!))
    }

    @Test func aPostManIsPlayedOnTheBallSide() {
        // 5 on the right block, the ball on the right wing.
        let players = [2: P(13, 6), 5: P(9.5, 2)]
        let spot = JournalPlayMath.manSpot(guarding: players[5]!, ball: players[2]!, court: .half)
        let behind = P(9.5 - 0.6, 2 - 0.2)            // where a defender behind him would stand
        // Fronting: on the ball side of him, closer to the passer than he is.
        #expect(spot.distance(to: players[2]!) < players[5]!.distance(to: players[2]!))
        #expect(spot.distance(to: players[2]!) < behind.distance(to: players[2]!))
    }
}


/// The rebuilt defense (20 Nov 2026, Luther: "NBA level of understanding"):
/// each principle as the shell drill and the slide charts teach it.
/// Half court: rim (7.5, 1.575); top (7.5, 8.6), wings (±4.8 from the
/// middle, 6.3), corners (0.9 / 14.1, 1.2), the split line x = 7.5.
struct JournalPlayDefensePrinciplesTests {
    typealias P = JournalCourtPoint
    static let top = P(7.5, 8.6), rWing = P(12.3, 6.3), lWing = P(2.7, 6.3)
    static let rCorner = P(14.1, 1.2), lCorner = P(0.9, 1.2)
    static let fiveOut: [Int: P] = [1: top, 2: rWing, 3: lWing, 4: rCorner, 5: lCorner]

    @Test func noMiddleShadesTheWingButNotTheTop() {
        var sc = DefenseScheme(); sc.onBall = .noMiddle
        let wing = JournalPlayMath.onBallSpot(Self.rWing, court: .half, scheme: sc)
        let plain = JournalPlayMath.onBallSpot(Self.rWing, court: .half)
        #expect(wing.x < plain.x - 0.3, "on the middle side of the handler")
        let top = JournalPlayMath.onBallSpot(Self.top, court: .half, scheme: sc)
        #expect(abs(top.x - 7.5) < 0.01)
    }

    @Test func onePassAwayIsInTheGapOrDenying() {
        let gap = JournalPlayMath.manSpot(guarding: Self.rWing, ball: Self.top, court: .half)
        var sc = DefenseScheme(); sc.offBall = .deny
        let deny = JournalPlayMath.manSpot(guarding: Self.rWing, ball: Self.top, court: .half, scheme: sc)
        // Both between man and ball; the deny closer to his man, in the lane.
        #expect(gap.distance(to: Self.top) < Self.rWing.distance(to: Self.top))
        #expect(deny.distance(to: Self.rWing) < gap.distance(to: Self.rWing))
        #expect(deny.distance(to: Self.rWing) < 1.4)
    }

    @Test func twoPassesAwayIsOnTheSplitLine() {
        // Ball on the right wing: the left wing's man is at the elbow on the
        // split line, the left corner's man is the low man at the rim.
        let wing = JournalPlayMath.manSpot(guarding: Self.lWing, ball: Self.rWing, court: .half)
        #expect(abs(wing.x - 7.5) < 1.0 && wing.y > 4.5 && wing.y < 7)
        let low = JournalPlayMath.manSpot(guarding: Self.lCorner, ball: Self.rWing, court: .half)
        #expect(abs(low.x - 7.5) < 1.0 && low.y < 3.5)
    }

    @Test func thePostIsThreeQuarteredHighOrFrontedLow() {
        let post = P(9.8, 2.4)
        let high = JournalPlayMath.manSpot(guarding: post, ball: Self.rWing, court: .half)
        let low = JournalPlayMath.manSpot(guarding: post, ball: Self.rCorner, court: .half)
        #expect(high.y > post.y, "ball above the FT line: on the high side")
        #expect(low.x > post.x, "ball in the corner: fronted, between him and the ball")
    }

    @Test func aDriveBringsTheLowManAndARotationBehindHim() {
        var players = Self.fiveOut
        players[1] = P(9.0, 3.2)                          // 1 drives right
        let guards: [Int?] = [1, 2, 3, 4, 5]
        let base = guards.map { n in Optional(JournalPlayMath.manSpot(guarding: players[n!]!, ball: players[1]!, court: .half)) }
        let team = JournalPlayMath.manTeamSpots(base, guards: guards, players: players, ball: players[1]!, court: .half)
        // X5 (the low man) steps into the drive; X3 drops to split 3 and 5.
        #expect(team[4]!.distance(to: players[1]!) < 1.8)
        #expect(team[2]!.distance(to: JournalCourtPoint(1.8, 3.75)) < 2.0)
        // Never help off the strong-side corner.
        #expect(team[3]! == base[3]!)
    }

    @Test func aHighPostCatchIsNotADrive() {
        var players = Self.fiveOut
        players[1] = P(7.5, 5.9)
        let guards: [Int?] = [1, 2, 3, 4, 5]
        let base = guards.map { n in Optional(JournalPlayMath.manSpot(guarding: players[n!]!, ball: players[1]!, court: .half)) }
        let team = JournalPlayMath.manTeamSpots(base, guards: guards, players: players, ball: players[1]!, court: .half)
        for i in 1..<5 { #expect(team[i]!.distance(to: base[i]!) < 0.6) }
    }

    /// 5 screens for 1 at the top; 1 comes off to the right.
    private func pnr(_ coverage: DefenseScheme.Screens, players: [Int: P]) -> [P] {
        var sc = DefenseScheme(); sc.screens = coverage
        let guards: [Int?] = [1, 5, 2, 3, 4]
        let base = guards.map { n in Optional(JournalPlayMath.manSpot(guarding: players[n!]!, ball: players[1]!, court: .half, scheme: sc)) }
        return JournalPlayMath.manTeamSpots(base, guards: guards, players: players, ball: players[1]!, court: .half, scheme: sc,
            screens: [.init(screener: 5, user: 1, spot: P(8.4, 8.6), weight: 1, ballScreen: true)]).map { $0! }
    }

    @Test func ballScreenCoverages() {
        let set: [Int: P] = [1: P(8.8, 7.6), 5: P(8.4, 8.6), 2: Self.rWing, 3: Self.lWing, 4: Self.rCorner]
        let rim = P(7.5, 1.575)
        // Drop: X5 between the ball and the rim, ~3 m out; X1 trails behind.
        let drop = pnr(.drop, players: set)
        #expect(drop[1].distance(to: rim) < 3.6 && drop[1].y < set[1]!.y)
        #expect(drop[0].distance(to: rim) > set[1]!.distance(to: rim))
        // Hedge: X5 out in the handler's path, past him from the screen.
        let hedge = pnr(.hedge, players: set)
        #expect(hedge[1].distance(to: set[1]!) < 1.0 && hedge[1].y < set[1]!.y)
        // Trap: both on the ball.
        let trap = pnr(.trap, players: set)
        #expect(trap[0].distance(to: set[1]!) < 1.6 && trap[1].distance(to: set[1]!) < 1.6)
        // Only SWITCH swaps men.
        var d = JournalPlayDiagram(offense: [.init(number: 1, at: P(7.5, 9)), .init(number: 5, at: P(4, 3))], ball: 1,
                                   actions: [.init(kind: .screen, player: 5, path: [P(4, 3), P(6.5, 8.2)]),
                                             .init(kind: .dribble, player: 1, path: [P(7.5, 9), P(6.4, 7.4), P(9, 5)])])
        d.defense = [.init(at: P(7.5, 8)), .init(at: P(4, 2.5))]
        d = JournalPlayMath.applyingDefense(.man, to: [d], court: .half, scheme: DefenseScheme(screens: .drop))[0]
        #expect(JournalPlayMath.switches(d).isEmpty)
        #expect(JournalPlayMath.screenUses(d).count == 1)
    }

    @Test func onATrapTheLowManTagsTheRoller() {
        let rolling: [Int: P] = [1: P(9.5, 7.6), 5: P(8.3, 3.5), 2: Self.rWing, 3: Self.lWing, 4: Self.rCorner]
        let trap = pnr(.trap, players: rolling)
        let rim = P(7.5, 1.575)
        // Someone stands between the roller and the rim.
        #expect(trap.contains { $0.distance(to: rolling[5]!) < 1.4 && $0.distance(to: rim) < rolling[5]!.distance(to: rim) })
    }

    @Test func the23SlidesLikeTheChart() {
        // Ball in the right corner: the right forward closes out, the centre
        // fronts the ball-side post, the right guard takes the wing, the left
        // guard the high post, the left forward the rim.
        let s = JournalPlayMath.zoneSpots(.zone23, ball: Self.rCorner, players: Self.fiveOut, court: .half)
        #expect(s[3].distance(to: Self.rCorner) < 1.6)                     // RF on the ball
        #expect(s[4].x > 9 && s[4].y < 3.5)                                 // C ball-side low post
        #expect(s[1].x > 10.5 && s[1].y > 4)                                // RG the wing
        #expect(abs(s[0].x - 7.5) < 1.5 && s[0].y > 4.5)                    // LG high post
        #expect(abs(s[2].x - 7.5) < 1.6 && s[2].y < 3.5)                    // LF the rim
    }

    @Test func the32SlidesLikeTheChart() {
        // Ball in the right corner: the right low man closes out, the left
        // low man slides across to the ball-side post.
        let s = JournalPlayMath.zoneSpots(.zone32, ball: Self.rCorner, players: Self.fiveOut, court: .half)
        #expect(s[4].distance(to: Self.rCorner) < 1.6)
        #expect(s[3].x > 8.8 && s[3].y < 3.5)
        // Ball at the top: the point plays it, the wings at the elbows extended.
        let t = JournalPlayMath.zoneSpots(.zone32, ball: Self.top, players: Self.fiveOut, court: .half)
        #expect(t[0].distance(to: Self.top) < 1.6)
        #expect(t[1].x < 5.5 && t[2].x > 9.5)
    }

    @Test func zonesMoveSmoothlyAsTheBallSwings() {
        // Corner to corner around the arc in small steps: nobody jumps.
        for mode in [JournalPlayDiagram.DefenseMode.zone23, .zone32] {
            var previous: [P]?
            for k in 0...60 {
                let a = Double.pi * Double(k) / 60
                let ball = P(7.5 - 6.6 * cos(a), 1.2 + 5.6 * sin(a))
                let s = JournalPlayMath.zoneSpots(mode, ball: ball, court: .half)
                if let previous {
                    for i in s.indices { #expect(s[i].distance(to: previous[i]) < 1.0, "\(mode) step \(k) defender \(i)") }
                }
                previous = s
            }
        }
    }

    @Test func theSchemeRoundTripsAndIsOnlyWrittenWhenSet() throws {
        var d = JournalPlayDiagram(offense: [.init(number: 1, at: Self.top)], ball: 1)
        #expect(!String(decoding: try JSONEncoder().encode(d), as: UTF8.self).contains("defenseScheme"))
        d.defenseScheme = DefenseScheme(onBall: .noMiddle, offBall: .deny, screens: .hedge, helpRotate: false)
        let back = try JSONDecoder().decode(JournalPlayDiagram.self, from: JSONEncoder().encode(d))
        #expect(back.defenseScheme == d.defenseScheme)
    }
}
