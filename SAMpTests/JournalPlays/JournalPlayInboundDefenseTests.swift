import Foundation
import Testing
@testable import Hoopwise

/// Inbounds and the format (22 Nov 2026, Luther: "the defense engine must
/// understand when defending 1v1 to 5v5, out of bounds or live — maybe this
/// can be selected"). Half court: basket (7.5, 1.575), baseline y = 0.
struct JournalPlayInboundDefenseTests {
    typealias P = JournalCourtPoint
    typealias D = JournalPlayDiagram

    static let rim = P(7.5, 1.575)

    /// His screenshot: 2 inbounds from behind the baseline left of the rim;
    /// 3 on the left block, 1 on the right of the lane.
    static func blob(_ scheme: DefenseScheme? = nil) -> D {
        var d = D(offense: [.init(number: 2, at: P(5.2, -0.6)), .init(number: 3, at: P(2.4, 4.6)),
                            .init(number: 1, at: P(9.8, 5.0))],
                  defense: [.init(at: P(5.4, 0.6)), .init(at: P(3.0, 4.0)), .init(at: P(9.2, 4.4))], ball: 2)
        d.defenseScheme = scheme
        return JournalPlayMath.applyingDefense(.man, to: [d], court: .half, scheme: scheme)[0]
    }

    private func spot(of man: Int, in d: D) -> P {
        d.defense[d.defense.firstIndex { $0.guards == man }!].at
    }

    @Test func aBallBehindTheBaselineIsABaselineInbound() {
        #expect(JournalPlayMath.outOfBounds(P(5, -0.6), court: .half)?.side == .baseline)
        #expect(JournalPlayMath.outOfBounds(P(-0.5, 6), court: .half)?.side == .side)
        #expect(JournalPlayMath.outOfBounds(P(15.6, 6), court: .half)?.side == .side)
        #expect(JournalPlayMath.outOfBounds(P(5, 0.1), court: .half) == nil, "on the line is in")
        // Full court: the attacked baseline is the right one.
        #expect(JournalPlayMath.outOfBounds(P(28.5, 7), court: .full)?.side == .baseline)
        #expect(JournalPlayMath.outOfBounds(P(-0.5, 7), court: .full)?.side == .side)
    }

    @Test func nobodyHidesUnderTheRimAgainstABaselineInbound() {
        let d = Self.blob()
        // The bug: the help-side spot collapsed onto the rim. 1's defender now
        // stays with 1, between him and the rim, a step toward the ball.
        let x1 = spot(of: 1, in: d)
        #expect(x1.distance(to: P(9.8, 5.0)) < 1.6)
        #expect(x1.distance(to: Self.rim) > 1.8)
        #expect(x1.distance(to: Self.rim) < P(9.8, 5.0).distance(to: Self.rim), "basket-side of his man")
        // Every defender is on the floor.
        #expect(d.defense.allSatisfy { $0.at.y > 0 })
    }

    @Test func theInbounderIsPressuredOrTheRimIsProtected() {
        let pressure = spot(of: 2, in: Self.blob())
        #expect(pressure.y > 0.5 && pressure.y < 1.3, "just inside the baseline")
        #expect(abs(pressure.x - 5.2) < 0.8, "opposite the passer")
        #expect(pressure.x > 5.2, "shaded toward the rim")

        var protect = DefenseScheme.standard
        protect.inbounder = .protectRim
        let safety = spot(of: 2, in: Self.blob(protect))
        #expect(safety.distance(to: Self.rim) < 1.6, "free safety in front of the rim")
        #expect(safety.y > Self.rim.y)
    }

    @Test func noHelpOnTheDriveAgainstABallOutOfBounds() {
        // The ball 2 m from the rim used to read as penetration and pulled a
        // helper into the "gap" — toward the baseline.
        let d = Self.blob()
        let x3 = spot(of: 3, in: d)
        #expect(x3.distance(to: P(2.4, 4.6)) < 1.6, "3's defender stays with 3")
    }

    @Test func liveForcesTheLiveRulesAndInboundForcesTheInbound() {
        var live = DefenseScheme.standard
        live.situation = .live
        let players = [2: P(5.2, -0.6), 3: P(2.4, 4.6), 1: P(9.8, 5.0)]
        #expect(JournalPlayMath.inbound(ball: P(5.2, -0.6), holderAt: P(5.2, -0.6), court: .half, scheme: live) == nil)
        var forced = DefenseScheme.standard
        forced.situation = .inbound
        // A holder drawn just inside the baseline is still the inbounder.
        let side = JournalPlayMath.inbound(ball: P(5.2, 0.3), holderAt: P(5.2, 0.3), court: .half, scheme: forced)
        #expect(side?.side == .baseline)
        #expect(JournalPlayMath.inbound(ball: P(7.5, 8), holderAt: players[1], court: .half, scheme: .standard) == nil,
                "Auto: a ball on the floor is live")
    }

    @Test func aSidelineInboundDeniesTheMenNearTheBall() {
        var d = D(offense: [.init(number: 1, at: P(-0.6, 8)), .init(number: 2, at: P(3.0, 9.0)),
                            .init(number: 3, at: P(12, 4))],
                  defense: [.init(at: P(0.5, 8)), .init(at: P(3.5, 8.5)), .init(at: P(11, 4))], ball: 1)
        d = JournalPlayMath.applyingDefense(.man, to: [d], court: .half)[0]
        let x2 = spot(of: 2, in: d)
        let deny = JournalPlayMath.manSpot(guarding: P(3.0, 9.0), ball: P(-0.6, 8), court: .half,
                                           scheme: DefenseScheme(offBall: .deny))
        #expect(x2.distance(to: deny) < 0.2, "one pass away from the inbounder: denied")
        #expect(spot(of: 1, in: d).x > 0.3, "the inbounder's defender is on the floor")
    }

    @Test func theFormatIsReadAndZonesNeedFive() {
        let three = Self.blob()
        #expect(JournalPlayMath.format(three) == "3v3")
        #expect(!JournalPlayMath.zonesFit(three))
        let five = D(offense: (1...5).map { .init(number: $0, at: P(Double($0) * 2.5, 6)) })
        #expect(JournalPlayMath.zonesFit(five))
        // 1v1: one defender, on the ball, no help to give.
        let one = JournalPlayMath.applyingDefense(.man, to: [D(offense: [.init(number: 1, at: P(7.5, 8))], ball: 1)],
                                                  court: .half)[0]
        #expect(JournalPlayMath.format(one) == "1v1")
        #expect(abs(one.defense[0].at.y - 6.9) < 0.05)
    }

    @Test func oldSchemesReadAsAutoAndPressure() throws {
        let old = #"{"onBall":"noMiddle","screens":"chase"}"#
        let s = try JSONDecoder().decode(DefenseScheme.self, from: Data(old.utf8))
        #expect(s.situation == .auto && s.inbounder == .pressure && s.screens == .chase)
    }
}
