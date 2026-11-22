import Foundation

// AUTO DEFENSE — rebuilt 20 November 2026 (Luther: "a thorough and accurate
// check of automatic defenses … man to man, zone 2-3 and 3-2 … top of the
// art, NBA level of understanding … explore defensive rotations, switches").
// First version 12 November 2026 (calculated spots with nudges, matched by
// nearest player, man / 2-3 / 3-2).
//
// With `defenseMode` set, a defender's spot is WORKED OUT from where the ball
// and the attackers are; the coach's NUDGE is added on top and carried.
//
// MAN-TO-MAN, as the shell drill teaches it:
// · ON THE BALL: an arm's length (≈ 1.1 m) between the ball and the rim;
//   "No middle" sits on the middle side so the handler is sent to the
//   sideline and baseline, where the help is.
// · ONE PASS AWAY (ball side): GAP (pack line — a third of the way to the
//   ball and a step toward the rim, ready to stunt on a drive) or DENY (in
//   the passing lane, a hand in it).
// · TWO PASSES AWAY (help side, or more than ~9 m from the ball): on the
//   SPLIT LINE — the line through the rim down the middle of the floor —
//   just on his man's side, between the ball's depth and his man's: the low
//   man sits in front of the rim, the weak-side wing at the elbow.
//   One pass ↔ two passes is blended, never a jump, as the ball swings.
// · THE POST: ball above the free-throw line extended → three-quarter on the
//   high side; ball below it on his side → full front.
// · HELP AND ROTATE: as the ball handler gets within ~5.8 m of the rim the
//   help-side defender nearest the driving line steps into it, and the
//   defender nearest that helper's man drops to split the two open men
//   ("sink and fill", the X-out). Only on a held ball — never on a pass in
//   flight.
// · SCREENS (`DefenseScheme.screens`), a ball screen = the handler uses it:
//   SWITCH (the two swap men and keep them), DROP (the screener's man sinks
//   between ball and rim, the handler's man goes over and trails), HEDGE
//   (the screener's man steps out into the handler's path, then recovers),
//   TRAP (both on the ball), CHASE (no switch: over the top, a soft show).
//   On a hedge or trap the low man TAGS the roller and the next defender
//   splits. Off-ball screens switch under SWITCH, else are chased.
// ZONES are SLIDE CHARTS — what each position does with the ball at the
// top, a wing, a corner, the high post and a low post (both sides) —
// blended smoothly by where the ball is; the on-ball duty passes between
// positions the same way. Off the ball each defender shades an attacker in
// his area, and someone always protects the rim.
// INBOUNDS (22 Nov 2026, Luther: "the defense engine must understand …
// out of bound or live — maybe this can be selected"). `situation` Auto
// reads an inbound when the BALL is out of bounds (beyond a line by
// 0.15 m); Live never, Inbound always (the holder is the inbounder, the
// nearest line his). BASELINE (behind the attacked baseline): everyone
// basket-side and ball-side of his man — no layups, see the ball —, the
// perimeter defenders sag into the paint, and nobody "helps on the drive"
// against a ball that is out of bounds. SIDELINE / far baseline: the men
// near the ball are denied, the help side sags as live. The INBOUNDER'S
// defender: Pressure (just inside the line, shading the pass to the rim) or
// Protect the rim (free safety in front of the rim / at the ball-side
// elbow). Once the ball is inside, the live rules take over by themselves.
// In playback each defender reacts a fraction of a beat late (his spot is
// averaged over the last `reactionBeats`), so a closeout, a switch or a
// rotation slides instead of jumping. The attacked basket is the court's
// first (half court: the one; full court: the right).

/// How the man-to-man defense plays (per part, inside each step's drawing —
/// written only when not the default, so older drawings read unchanged).
nonisolated struct DefenseScheme: Codable, Equatable, Sendable {
    enum OnBall: String, Codable, CaseIterable, Sendable { case contain, noMiddle }
    enum OffBall: String, Codable, CaseIterable, Sendable { case gap, deny }
    enum Screens: String, Codable, CaseIterable, Sendable { case switchAll, drop, hedge, trap, chase }
    /// Live ball or an inbound — Auto reads it from where the ball is.
    enum Situation: String, Codable, CaseIterable, Sendable { case auto, live, inbound }
    /// The inbounder's defender: on the passer, or protecting the rim.
    enum Inbounder: String, Codable, CaseIterable, Sendable { case pressure, protectRim }

    var onBall: OnBall = .contain
    var offBall: OffBall = .gap
    var screens: Screens = .switchAll
    /// Help on drives and rotate behind the helper.
    var helpRotate = true
    var situation: Situation = .auto
    var inbounder: Inbounder = .pressure

    static let standard = DefenseScheme()

    init(onBall: OnBall = .contain, offBall: OffBall = .gap, screens: Screens = .switchAll, helpRotate: Bool = true,
         situation: Situation = .auto, inbounder: Inbounder = .pressure) {
        self.onBall = onBall
        self.offBall = offBall
        self.screens = screens
        self.helpRotate = helpRotate
        self.situation = situation
        self.inbounder = inbounder
    }

    // Tolerant: an unknown value (a newer build's) reads as the default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onBall = (try? c.decodeIfPresent(OnBall.self, forKey: .onBall)) ?? .contain
        offBall = (try? c.decodeIfPresent(OffBall.self, forKey: .offBall)) ?? .gap
        screens = (try? c.decodeIfPresent(Screens.self, forKey: .screens)) ?? .switchAll
        helpRotate = (try? c.decodeIfPresent(Bool.self, forKey: .helpRotate)) ?? true
        situation = (try? c.decodeIfPresent(Situation.self, forKey: .situation)) ?? .auto
        inbounder = (try? c.decodeIfPresent(Inbounder.self, forKey: .inbounder)) ?? .pressure
    }
}

nonisolated extension JournalPlayMath {
    static let reactionBeats = 0.35

    // MARK: - The court's frame of reference

    /// The attacked rim, the direction from it toward the court's middle
    /// ("out") and across ("side").
    static func defenseFrame(_ court: JournalCourtKind) -> (basket: JournalCourtPoint, out: JournalCourtPoint, side: JournalCourtPoint) {
        switch court {
        case .half: return (court.baskets[0], JournalCourtPoint(0, 1), JournalCourtPoint(1, 0))
        case .full: return (court.baskets[0], JournalCourtPoint(-1, 0), JournalCourtPoint(0, 1))
        }
    }

    /// Court metres ↔ (side, out) from the attacked rim.
    struct DefenseGeometry {
        let basket: JournalCourtPoint
        let out: JournalCourtPoint
        let side: JournalCourtPoint

        init(_ court: JournalCourtKind) {
            let f = JournalPlayMath.defenseFrame(court)
            basket = f.basket
            out = f.out
            side = f.side
        }

        func local(_ p: JournalCourtPoint) -> (s: Double, o: Double) {
            let dx = p.x - basket.x, dy = p.y - basket.y
            return (dx * side.x + dy * side.y, dx * out.x + dy * out.y)
        }

        func world(_ s: Double, _ o: Double) -> JournalCourtPoint {
            JournalCourtPoint(basket.x + side.x * s + out.x * o, basket.y + side.y * s + out.y * o)
        }
    }

    private static func clamp(_ p: JournalCourtPoint, _ court: JournalCourtKind) -> JournalCourtPoint {
        let size = court.size
        return JournalCourtPoint(min(max(p.x, 0.3), size.width - 0.3), min(max(p.y, 0.3), size.height - 0.3))
    }

    private static func lerp(_ a: JournalCourtPoint, _ b: JournalCourtPoint, _ t: Double) -> JournalCourtPoint {
        JournalCourtPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    private static func unit(_ from: JournalCourtPoint, _ to: JournalCourtPoint) -> JournalCourtPoint {
        let d = max(from.distance(to: to), 0.0001)
        return JournalCourtPoint((to.x - from.x) / d, (to.y - from.y) / d)
    }

    private static func plus(_ p: JournalCourtPoint, _ v: JournalCourtPoint, _ k: Double) -> JournalCourtPoint {
        JournalCourtPoint(p.x + v.x * k, p.y + v.y * k)
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The attacker holding the ball (within 0.6 m of it), if any.
    static func ballHolder(players: [Int: JournalCourtPoint], ball: JournalCourtPoint?) -> Int? {
        guard let ball else { return nil }
        let nearest = players.min { $0.value.distance(to: ball) < $1.value.distance(to: ball) }
        guard let n = nearest, n.value.distance(to: ball) < 0.6 else { return nil }
        return n.key
    }

    // MARK: - Inbounds

    /// Where the ball is put in from.
    enum InboundSide: Equatable, Sendable {
        /// Behind the attacked baseline (a BLOB).
        case baseline
        /// A sideline, or the far baseline of a full court.
        case side
    }

    /// The line a point is beyond (by more than 0.15 m), if any, and the
    /// direction into the court from it.
    static func outOfBounds(_ p: JournalCourtPoint, court: JournalCourtKind) -> (side: InboundSide, inward: JournalCourtPoint)? {
        let size = court.size, e = 0.15
        switch court {
        case .half:
            if p.y < -e { return (.baseline, JournalCourtPoint(0, 1)) }
            if p.x < -e { return (.side, JournalCourtPoint(1, 0)) }
            if p.x > size.width + e { return (.side, JournalCourtPoint(-1, 0)) }
        case .full:
            if p.x > size.width + e { return (.baseline, JournalCourtPoint(-1, 0)) }
            if p.x < -e { return (.side, JournalCourtPoint(1, 0)) }
            if p.y < -e { return (.side, JournalCourtPoint(0, 1)) }
            if p.y > size.height + e { return (.side, JournalCourtPoint(0, -1)) }
        }
        return nil
    }

    /// The nearest line to a point inside the court (an inbound forced on a
    /// holder drawn on the floor).
    static func nearestLine(_ p: JournalCourtPoint, court: JournalCourtKind) -> (side: InboundSide, inward: JournalCourtPoint) {
        let size = court.size
        var lines: [(d: Double, side: InboundSide, inward: JournalCourtPoint)] = [
            (p.x, .side, JournalCourtPoint(1, 0)),
            (size.width - p.x, court == .full ? .baseline : .side, JournalCourtPoint(-1, 0)),
        ]
        switch court {
        case .half: lines.append((p.y, .baseline, JournalCourtPoint(0, 1)))
        case .full:
            lines.append((p.y, .side, JournalCourtPoint(0, 1)))
            lines.append((size.height - p.y, .side, JournalCourtPoint(0, -1)))
        }
        let best = lines.min { $0.d < $1.d }!
        return (best.side, best.inward)
    }

    /// The inbound in play at a moment: from the ball's position (Auto), never
    /// (Live), or always (Inbound — the holder's nearest line).
    static func inbound(ball: JournalCourtPoint?, holderAt: JournalCourtPoint?, court: JournalCourtKind,
                        scheme: DefenseScheme) -> (side: InboundSide, inward: JournalCourtPoint)? {
        guard let ball else { return nil }
        switch scheme.situation {
        case .live: return nil
        case .auto: return outOfBounds(ball, court: court)
        case .inbound: return outOfBounds(ball, court: court) ?? nearestLine(holderAt ?? ball, court: court)
        }
    }

    /// The inbounder's defender. Pressure: just inside the line opposite the
    /// passer, shaded toward the rim (the pass he must not make). Protect the
    /// rim: in front of the rim on the ball side (baseline), or at the
    /// ball-side elbow (sideline).
    static func inbounderSpot(_ passer: JournalCourtPoint, inward: JournalCourtPoint, side: InboundSide,
                              court: JournalCourtKind, scheme: DefenseScheme) -> JournalCourtPoint {
        let g = DefenseGeometry(court)
        switch scheme.inbounder {
        case .pressure:
            // Onto the line, then 0.8 m inside it.
            let size = court.size
            var onLine = passer
            if inward.x != 0 { onLine.x = inward.x > 0 ? 0 : size.width }
            if inward.y != 0 { onLine.y = inward.y > 0 ? 0 : size.height }
            var spot = plus(onLine, inward, 0.8)
            // Along the line toward the rim: take away the pass to the basket.
            let along = JournalCourtPoint(-inward.y, inward.x)
            let toward = (g.basket.x - spot.x) * along.x + (g.basket.y - spot.y) * along.y
            spot = plus(spot, along, max(-0.5, min(0.5, toward * 0.3)))
            return clamp(spot, court)
        case .protectRim:
            let b = g.local(passer)
            if side == .baseline { return clamp(g.world(b.s >= 0 ? 0.6 : -0.6, 1.4), court) }
            let dir = unit(g.basket, passer)
            return clamp(plus(g.basket, dir, min(4.6, g.basket.distance(to: passer) * 0.5)), court)
        }
    }

    /// Against a baseline inbound: between his man and the rim, a step toward
    /// the ball (see it, no backdoor to the rim); a man out on the perimeter
    /// is given the pass out — his defender sags into the paint.
    static func baselineInboundSpot(guarding man: JournalCourtPoint, ball: JournalCourtPoint,
                                    court: JournalCourtKind, scheme: DefenseScheme) -> JournalCourtPoint {
        let g = DefenseGeometry(court)
        let dRim = man.distance(to: g.basket), dBall = man.distance(to: ball)
        var spot: JournalCourtPoint
        if scheme.offBall == .deny, dBall < 4.5 {
            // Deny the direct pass in, the rim still behind him.
            spot = plus(plus(man, unit(man, ball), 0.9), unit(man, g.basket), 0.3)
        } else {
            spot = plus(plus(man, unit(man, g.basket), min(1.1, max(0.5, dRim * 0.3))), unit(man, ball), 0.45)
        }
        let sag = smooth((dRim - 5.8) / 2.0)
        if sag > 0 { spot = lerp(spot, lerp(man, g.basket, 0.42), sag) }
        return clamp(spot, court)
    }

    // MARK: - Man-to-man: one defender

    /// On the ball: an arm's length between him and the rim; "No middle"
    /// sits on the middle side of him.
    static func onBallSpot(_ man: JournalCourtPoint, court: JournalCourtKind, scheme: DefenseScheme = .standard) -> JournalCourtPoint {
        let g = DefenseGeometry(court)
        let dRim = man.distance(to: g.basket)
        // An arm's length; looser far beyond the arc, tighter near the rim.
        let gap = min(1.1, max(0.7, dRim * 0.35)) + 0.5 * smooth((dRim - 8.5) / 2.5)
        var spot = plus(man, unit(man, g.basket), gap)
        if scheme.onBall == .noMiddle {
            let m = g.local(man)
            // Off the middle third only: at the top there is no middle to take.
            let shade = 0.5 * smooth((abs(m.s) - 1.2) / 1.5)
            if shade > 0 {
                let toMiddle = m.s > 0 ? -1.0 : 1.0
                spot = plus(spot, g.side, toMiddle * shade)
            }
        }
        return clamp(spot, court)
    }

    /// How far "help side" a man is with the ball at `ball`: 0 = one pass
    /// away on the ball side, 1 = two passes away (across the split line, or
    /// more than ~9 m from the ball). Continuous.
    static func helpSideness(man: JournalCourtPoint, ball: JournalCourtPoint, court: JournalCourtKind) -> Double {
        let g = DefenseGeometry(court)
        let m = g.local(man), b = g.local(ball)
        let across = m.s == 0 ? 0 : -(m.s / abs(m.s)) * b.s        // > 0: the ball is on the other side
        let bySide = smooth((across - 0.3) / 2.2) * smooth((abs(m.s) - 0.6) / 1.2)
        let byDistance = smooth((man.distance(to: ball) - 7.6) / 2.2)
        return max(bySide, byDistance)
    }

    /// Where a man-to-man defender stands against `man` with the ball at
    /// `ball` (his own spot, before the team's help and screen rules).
    static func manSpot(guarding man: JournalCourtPoint, ball: JournalCourtPoint?, court: JournalCourtKind,
                        scheme: DefenseScheme = .standard,
                        inbound: (side: InboundSide, inward: JournalCourtPoint)? = nil) -> JournalCourtPoint {
        let g = DefenseGeometry(court)
        if let inbound, let ball {
            if man.distance(to: ball) < 0.6 {
                return inbounderSpot(man, inward: inbound.inward, side: inbound.side, court: court, scheme: scheme)
            }
            if inbound.side == .baseline {
                return baselineInboundSpot(guarding: man, ball: ball, court: court, scheme: scheme)
            }
            // Sideline: the live rules, the men near the ball denied.
            var denying = scheme
            if man.distance(to: ball) < 7.6 { denying.offBall = .deny }
            return manSpot(guarding: man, ball: ball, court: court, scheme: denying)
        }
        guard let ball, man.distance(to: ball) >= 0.6 else { return onBallSpot(man, court: court, scheme: scheme) }
        let dBall = man.distance(to: ball)
        let toBall = unit(man, ball), toRim = unit(man, g.basket)

        // One pass away: in the gap, or denying the lane.
        let onePass: JournalCourtPoint
        switch scheme.offBall {
        case .gap:
            onePass = plus(plus(man, toBall, min(dBall * 0.33, 2.4)), toRim, min(0.7, man.distance(to: g.basket) * 0.25))
        case .deny:
            onePass = plus(plus(man, toBall, min(1.1, dBall * 0.4)), toRim, 0.35)
        }

        // Two passes away: on the split line, on his man's side, between the
        // ball's depth and his man's.
        let m = g.local(man), b = g.local(ball)
        let sideSign = m.s >= 0 ? 1.0 : -1.0
        let helpS = sideSign * min(0.8, abs(m.s))
        let helpO = min(max(0.55 * m.o + 0.45 * min(b.o, m.o + 2), 1.0), max(m.o, 1.0))
        let twoPass = g.world(helpS, helpO)

        var spot = lerp(onePass, twoPass, helpSideness(man: man, ball: ball, court: court))

        // The post: ball above the free-throw line extended → three-quarter
        // on the high side; below it on his side → full front. Ball side only.
        let post = smooth((3.9 - man.distance(to: g.basket)) / 1.4) * (1 - helpSideness(man: man, ball: ball, court: court))
        if post > 0 {
            let high = smooth((b.o - 2.8) / 1.4)     // 1: ball above the FT line extended
            let threeQuarter = plus(man, unit(JournalCourtPoint(0, 0),
                                              JournalCourtPoint(toBall.x + toRim.x * 0.45, toBall.y + toRim.y * 0.45)), 0.85)
            let front = plus(man, toBall, 0.95)
            spot = lerp(spot, lerp(front, threeQuarter, high), post)
        }
        return clamp(spot, court)
    }

    // MARK: - Man-to-man: the team

    /// A ball screen or off-ball screen in use at a moment, for the coverage.
    struct ActiveScreen: Equatable, Sendable {
        var screener: Int
        var user: Int
        var spot: JournalCourtPoint
        /// 0…1: how much the coverage is on at this moment.
        var weight: Double
        /// The user had the ball: a pick-and-roll.
        var ballScreen: Bool
    }

    /// The man defense's team rules on top of each defender's own spot: help
    /// and rotate on drives, and the screen coverage. `guards[i]` is who
    /// defender i guards at this moment.
    static func manTeamSpots(_ spots: [JournalCourtPoint?], guards: [Int?], players: [Int: JournalCourtPoint],
                             ball: JournalCourtPoint?, court: JournalCourtKind,
                             scheme: DefenseScheme = .standard, screens: [ActiveScreen] = [],
                             inbound: Bool = false) -> [JournalCourtPoint?] {
        guard let ball else { return spots }
        let g = DefenseGeometry(court)
        var out = spots
        let holder = ballHolder(players: players, ball: ball)
        func defender(of n: Int) -> Int? { guards.firstIndex(of: n) }
        /// Helpers already given a job this moment (one job each).
        var busy = Set<Int>()
        if let h = holder, let d = defender(of: h) { busy.insert(d) }

        // 1. Screen coverage.
        for screen in screens where screen.weight > 0 {
            guard let ds = defender(of: screen.screener), let du = defender(of: screen.user),
                  let sAt = players[screen.screener], let uAt = players[screen.user],
                  out[ds] != nil, out[du] != nil else { continue }
            let w = screen.weight
            if screen.ballScreen {
                let trail = plus(uAt, unit(g.basket, uAt), 0.85)                       // over the top, behind
                // Up at the screen, in the handler's path around it.
                let hedge = plus(screen.spot, unit(screen.spot, uAt), min(2.4, screen.spot.distance(to: uAt) + 0.8))
                let dRim = uAt.distance(to: g.basket)
                let drop = plus(g.basket, unit(g.basket, uAt), max(1.2, min(3.0, dRim - 1.6)))
                let sideOfScreen = unit(uAt, screen.spot)
                switch scheme.screens {
                case .switchAll:
                    break                                          // handled by the switch itself
                case .drop:
                    out[du] = lerp(out[du]!, trail, w)
                    out[ds] = lerp(out[ds]!, drop, w)
                case .hedge:
                    out[du] = lerp(out[du]!, trail, w)
                    out[ds] = lerp(out[ds]!, hedge, w)
                case .trap:
                    let a = plus(plus(uAt, sideOfScreen, 0.85), unit(uAt, g.basket), 0.35)
                    let b = plus(plus(uAt, sideOfScreen, -0.85), unit(uAt, g.basket), 0.35)
                    out[ds] = lerp(out[ds]!, a, w)
                    out[du] = lerp(out[du]!, b, w)
                case .chase:
                    out[du] = lerp(out[du]!, trail, w)
                    out[ds] = lerp(out[ds]!, lerp(out[ds]!, hedge, 0.4), w)
                }
                busy.insert(ds); busy.insert(du)
                // Hedge and trap leave the roller: the low man tags him, and
                // the defender nearest the low man's man splits the two.
                if scheme.screens == .hedge || scheme.screens == .trap {
                    let roll = smooth((6.2 - sAt.distance(to: g.basket)) / 2.6) * w
                    if roll > 0 {
                        let tagSpot = plus(sAt, unit(sAt, g.basket), 0.9)
                        let candidates = out.indices.filter { out[$0] != nil && !busy.contains($0) }
                        if let low = candidates.min(by: { out[$0]!.distance(to: tagSpot) < out[$1]!.distance(to: tagSpot) }) {
                            let lowMan = guards[low].flatMap { players[$0] }
                            out[low] = lerp(out[low]!, tagSpot, roll)
                            busy.insert(low)
                            if let lowMan { rotate(behind: lowMan, own: guards, players: players, out: &out, busy: &busy,
                                                   basket: g.basket, weight: roll * 0.85) }
                        }
                    }
                }
            } else if scheme.screens != .switchAll {
                // Off-ball screen chased: the user's man trails on the screen
                // side; the screener's man bumps into the lane a moment.
                let trail = plus(uAt, unit(uAt, screen.spot), 0.9)
                out[du] = lerp(out[du]!, trail, w)
                out[ds] = lerp(out[ds]!, lerp(uAt, g.basket, 0.45), w * 0.35)
                busy.insert(du)
            }
        }

        // 2. Help on the drive, and the rotation behind the helper — never
        // against a ball that is still out of bounds.
        if scheme.helpRotate, !inbound, let h = holder {
            let dBall = ball.distance(to: g.basket)
            // Penetration: from inside the free-throw line, full at ~2.8 m.
            let s = smooth((4.6 - dBall) / 1.8)
            if s > 0 {
                let gap = plus(ball, unit(ball, g.basket), min(1.3, max(0, dBall - 0.9)))
                let b = g.local(ball)
                let candidates = out.indices.filter { i in
                    guard out[i] != nil, !busy.contains(i), let n = guards[i], n != h, let man = players[n] else { return false }
                    // Never help off the strong-side corner (the kick-out three).
                    let m = g.local(man)
                    let strongCorner = abs(m.s) > 4.8 && m.o < 2.4 && m.s * b.s > 0
                    return man.distance(to: ball) >= 3.5 && !strongCorner
                }
                if let helper = candidates.min(by: { out[$0]!.distance(to: gap) < out[$1]!.distance(to: gap) }) {
                    out[helper] = lerp(out[helper]!, gap, s)
                    busy.insert(helper)
                    if let open = guards[helper].flatMap({ players[$0] }) {
                        rotate(behind: open, own: guards, players: players, out: &out, busy: &busy,
                               basket: g.basket, weight: s * 0.85)
                    }
                }
            }
        }
        return out
    }

    /// The rotation behind a helper: the free defender nearest the man the
    /// helper left drops to split that man and his own, a step toward the rim.
    private static func rotate(behind open: JournalCourtPoint, own guards: [Int?], players: [Int: JournalCourtPoint],
                               out: inout [JournalCourtPoint?], busy: inout Set<Int>, basket: JournalCourtPoint, weight: Double) {
        let candidates = out.indices.filter { out[$0] != nil && !busy.contains($0) }
        guard let next = candidates.min(by: { out[$0]!.distance(to: open) < out[$1]!.distance(to: open) }),
              let mine = guards[next].flatMap({ players[$0] }) else { return }
        let split = plus(lerp(open, mine, 0.5), unit(lerp(open, mine, 0.5), basket), 0.8)
        out[next] = lerp(out[next]!, split, weight)
        busy.insert(next)
    }

    // MARK: - Zones: the slide charts

    /// The five zone spots with the ball at the top, as (side, out) from the
    /// rim — the matching order (2-3: left guard, right guard, left forward,
    /// right forward, centre; 3-2: point, left wing, right wing, left low,
    /// right low).
    static func zoneSlots(_ mode: JournalPlayDiagram.DefenseMode) -> [(side: Double, out: Double)] {
        chart(mode).first { $0.name == "top" }?.slots ?? []
    }

    /// One row of a slide chart: where the ball is, where each position
    /// stands, and who plays the ball (nil: the nearest of the front line).
    private struct ChartRow {
        var name: String
        var ball: (s: Double, o: Double)
        var slots: [(side: Double, out: Double)]
        var onBall: Int?
        /// Up to how far the on-ball defender goes (1: all the way).
        var press: Double = 1
    }

    /// The charts for the right side; the left is their mirror.
    private static func chart(_ mode: JournalPlayDiagram.DefenseMode) -> [ChartRow] {
        switch mode {
        case .man:
            return []
        case .zone23:
            // GL, GR, FL, FR, C
            return [
                ChartRow(name: "top", ball: (0, 7.0),
                         slots: [(-1.7, 6.0), (1.7, 6.0), (-3.6, 1.8), (3.6, 1.8), (0, 1.6)], onBall: nil),
                ChartRow(name: "deep", ball: (0, 9.8),
                         slots: [(-1.9, 6.3), (1.9, 6.3), (-3.6, 1.8), (3.6, 1.8), (0, 1.6)], onBall: nil, press: 0.35),
                ChartRow(name: "highPost", ball: (0, 4.3),
                         slots: [(-1.3, 5.0), (1.3, 5.0), (-1.9, 1.3), (1.9, 1.3), (0, 3.4)], onBall: 4),
                ChartRow(name: "wing", ball: (5.3, 4.6),
                         slots: [(0.4, 4.2), (4.6, 4.2), (-2.0, 1.2), (3.8, 1.4), (1.6, 1.0)], onBall: 1),
                ChartRow(name: "corner", ball: (6.6, 0.3),
                         slots: [(0.6, 3.9), (4.2, 3.8), (-1.0, 1.2), (6.0, 0.6), (2.8, 0.9)], onBall: 3),
                ChartRow(name: "lowPost", ball: (3.0, 0.6),
                         slots: [(-0.2, 4.0), (2.6, 3.6), (-0.6, 1.2), (4.0, 1.8), (2.4, 0.9)], onBall: 4),
            ]
        case .zone32:
            // P, WL, WR, BL, BR
            return [
                ChartRow(name: "top", ball: (0, 7.0),
                         slots: [(0, 6.6), (-3.6, 4.8), (3.6, 4.8), (-2.0, 1.4), (2.0, 1.4)], onBall: 0),
                ChartRow(name: "deep", ball: (0, 9.8),
                         slots: [(0, 7.3), (-3.8, 5.0), (3.8, 5.0), (-2.0, 1.4), (2.0, 1.4)], onBall: 0, press: 0.35),
                ChartRow(name: "highPost", ball: (0, 4.3),
                         slots: [(0, 4.9), (-1.6, 4.2), (1.6, 4.2), (-1.6, 1.4), (1.6, 1.4)], onBall: 0),
                ChartRow(name: "wing", ball: (5.3, 4.6),
                         slots: [(1.6, 4.8), (-1.0, 4.0), (4.6, 4.3), (-0.6, 1.3), (3.6, 1.2)], onBall: 2),
                ChartRow(name: "corner", ball: (6.6, 0.3),
                         slots: [(0.8, 4.0), (-1.6, 1.6), (4.4, 3.6), (2.4, 0.9), (6.0, 0.6)], onBall: 4),
                ChartRow(name: "lowPost", ball: (3.0, 0.6),
                         slots: [(1.0, 3.9), (-1.8, 3.6), (3.6, 2.8), (0.0, 1.2), (2.4, 0.9)], onBall: 4),
            ]
        }
    }

    /// Left/right partner of each position (the mirror swaps them).
    private static func mirrorIndex(_ mode: JournalPlayDiagram.DefenseMode) -> [Int] {
        switch mode {
        case .man: return []
        case .zone23: return [1, 0, 3, 2, 4]
        case .zone32: return [0, 2, 1, 4, 3]
        }
    }

    /// Every zone defender's spot: the slide chart blended by where the ball
    /// is, the on-ball duty passed the same way, each off-ball defender
    /// shading the attacker in his area, and the rim always protected.
    static func zoneSpots(_ mode: JournalPlayDiagram.DefenseMode, ball: JournalCourtPoint?,
                          players: [Int: JournalCourtPoint] = [:], court: JournalCourtKind) -> [JournalCourtPoint] {
        let rows = chart(mode)
        guard !rows.isEmpty else { return [] }
        let g = DefenseGeometry(court)
        let count = rows[0].slots.count
        let partner = mirrorIndex(mode)
        let b: (s: Double, o: Double) = ball.map { g.local($0) } ?? (0, 9.8)

        // Every row and its mirror, weighted by how close the ball is.
        var distances: [Double] = []
        var rowSlots: [[(Double, Double)]] = []
        var rowOnBall: [Int?] = []
        var rowPress: [Double] = []
        for row in rows {
            for mirrored in row.ball.s == 0 ? [false] : [false, true] {
                let bs = mirrored ? -row.ball.s : row.ball.s
                let d2 = (b.s - bs) * (b.s - bs) + (b.o - row.ball.o) * (b.o - row.ball.o)
                distances.append(d2)
                var slots = [(Double, Double)](repeating: (0, 0), count: count)
                for i in 0..<count {
                    let source = mirrored ? partner[i] : i
                    slots[i] = (mirrored ? -row.slots[source].side : row.slots[source].side, row.slots[source].out)
                }
                rowSlots.append(slots)
                rowOnBall.append(row.onBall.map { mirrored ? partner[$0] : $0 })
                rowPress.append(row.press)
            }
        }
        // Gaussian weights relative to the nearest row (never all zero, even
        // with the ball in the backcourt).
        let nearest = distances.min() ?? 0
        let weights = distances.map { exp(-($0 - nearest) / (2 * 1.3 * 1.3)) }
        let total = max(weights.reduce(0, +), 1e-9)
        var anchors: [JournalCourtPoint] = []
        for i in 0..<count {
            var s = 0.0, o = 0.0
            for r in weights.indices { s += weights[r] * rowSlots[r][i].0; o += weights[r] * rowSlots[r][i].1 }
            anchors.append(g.world(s / total, o / total))
        }
        guard let ballAt = ball else { return anchors.map { clamp($0, court) } }

        // Who plays the ball: each row's on-ball position (or its nearest
        // front-line spot), blended.
        var onBallness = [Double](repeating: 0, count: count)
        for r in weights.indices {
            let who: Int
            if let n = rowOnBall[r] {
                who = n
            } else {
                let front = mode == .zone23 ? [0, 1] : [0]
                who = front.min { anchors[$0].distance(to: ballAt) < anchors[$1].distance(to: ballAt) } ?? 0
            }
            onBallness[who] += weights[r] / total * rowPress[r]
        }
        // Beyond the arc the on-ball man only shows.
        let reach = b.o < 7.6 ? 1.0 : max(0.35, 1 - (b.o - 7.6) / 3)
        var spots = anchors
        for i in 0..<count where onBallness[i] > 0 {
            spots[i] = lerp(anchors[i], onBallSpot(ballAt, court: court), min(1, onBallness[i] * reach))
        }

        // Off the ball: shade the attacker in your area — the one nearest
        // your spot, if he is nearer it than any other spot — between him and
        // the rim, without leaving the area.
        let holder = ballHolder(players: players, ball: ballAt)
        for (number, at) in players where number != holder && at.distance(to: g.basket) <= 9.5 {
            guard let i = anchors.indices.min(by: { anchors[$0].distance(to: at) < anchors[$1].distance(to: at) }),
                  onBallness[i] < 0.5, anchors[i].distance(to: at) < 4.0 else { continue }
            let mark = plus(at, unit(at, g.basket), 0.9)
            spots[i] = lerp(spots[i], mark, 0.4)
        }

        // The rim: someone always within 2.5 m of the front of it.
        let paint = g.world(b.s > 0 ? 0.6 : -0.6, 1.4)
        if !spots.contains(where: { $0.distance(to: paint) < 2.5 }),
           let i = spots.indices.filter({ onBallness[$0] < 0.5 }).min(by: { spots[$0].distance(to: paint) < spots[$1].distance(to: paint) }) {
            spots[i] = lerp(spots[i], paint, 0.8)
        }
        return spots.map { clamp($0, court) }
    }

    // MARK: - Spots for a moment

    /// Each defender's spot (nudge included), given where everyone and the
    /// ball are; `guards` is who each defender guards at that moment (man);
    /// `screens` the screens in use then. A man defender with no one to
    /// guard keeps `at`.
    static func defenseSpots(_ diagram: JournalPlayDiagram, players: [Int: JournalCourtPoint], ball: JournalCourtPoint?,
                             guards: [Int?], court: JournalCourtKind, screens: [ActiveScreen] = []) -> [JournalCourtPoint] {
        guard let mode = diagram.defenseMode else { return diagram.defense.map(\.at) }
        let scheme = diagram.defenseScheme ?? .standard
        var bases: [JournalCourtPoint?]
        if mode == .man {
            let own = diagram.defense.indices.map { $0 < guards.count ? guards[$0] : nil }
            let holderAt = ballHolder(players: players, ball: ball).flatMap { players[$0] }
            let play = inbound(ball: ball, holderAt: holderAt, court: court, scheme: scheme)
            bases = own.map { g in g.flatMap { players[$0] }.map {
                manSpot(guarding: $0, ball: ball, court: court, scheme: scheme, inbound: play) } }
            bases = manTeamSpots(bases, guards: own, players: players, ball: ball, court: court, scheme: scheme,
                                 screens: screens, inbound: play != nil)
        } else {
            let zone = zoneSpots(mode, ball: ball, players: players, court: court)
            bases = diagram.defense.indices.map { $0 < zone.count ? zone[$0] : nil }
        }
        let basket = defenseFrame(court).basket
        return diagram.defense.enumerated().map { i, defender in
            guard var base = bases[i] else { return defender.at }
            base = clearOf(players.values, base, basket: basket)
            let n = defender.nudge ?? JournalCourtPoint(0, 0)
            return clamp(JournalCourtPoint(base.x + n.x, base.y + n.y), court)
        }
    }

    /// A defender never stands on an attacker (he would hide under the
    /// circle): within 0.9 m of one, he is pushed out to 0.9 m — away from
    /// him, else toward the basket.
    static func clearOf<S: Sequence>(_ attackers: S, _ spot: JournalCourtPoint, basket: JournalCourtPoint) -> JournalCourtPoint
    where S.Element == JournalCourtPoint {
        var spot = spot
        for a in attackers {
            let d = spot.distance(to: a)
            guard d < 0.9 else { continue }
            var dx = spot.x - a.x, dy = spot.y - a.y
            if d < 0.05 { dx = basket.x - a.x; dy = basket.y - a.y }
            let len = max((dx * dx + dy * dy).squareRoot(), 0.01)
            spot = JournalCourtPoint(a.x + dx / len * 0.9, a.y + dy / len * 0.9)
        }
        return spot
    }

    // MARK: - Screens

    /// A screen used in this step: the screener, the user, where it was set
    /// and when (beats) it was set and used.
    struct ScreenUse: Equatable, Sendable {
        var screener: Int
        var user: Int
        var spot: JournalCourtPoint
        var set: Double
        var used: Double
    }

    /// The screens used in this step: the screener and the player whose move,
    /// drawn after the screen, passes within 1.5 m of where it was set — at
    /// the moment he goes past it.
    static func screenUses(_ diagram: JournalPlayDiagram, plan: Schedule? = nil) -> [ScreenUse] {
        guard diagram.defenseMode == .man else { return [] }
        let plan = plan ?? schedule(diagram)
        var out: [ScreenUse] = []
        for screen in plan.items where diagram.actions[screen.index].kind == .screen {
            let screener = diagram.actions[screen.index].player
            guard let spot = diagram.actions[screen.index].path.last else { continue }
            var best: (time: Double, distance: Double, user: Int)?
            for item in plan.items where item.index > screen.index {
                let action = diagram.actions[item.index]
                guard action.kind.movesPlayer, action.player != screener else { continue }
                let path = drawnPath(action)
                for k in 0...24 {
                    let f = Double(k) / 24
                    let d = point(along: path, at: eased(f)).distance(to: spot)
                    if d <= screenReach, d < (best?.distance ?? .infinity) {
                        best = (item.start + f * (item.end - item.start), d, action.player)
                    }
                }
            }
            if let best { out.append(ScreenUse(screener: screener, user: best.user, spot: spot,
                                                set: screen.end, used: max(best.time, screen.end))) }
        }
        return out.sorted { $0.used < $1.used }
    }

    /// The screens in use at `beats`, with how strongly (the coverage builds
    /// as the screen is set, holds through the use, fades a beat after).
    static func activeScreens(_ uses: [ScreenUse], at beats: Double, ballHolder: Int?) -> [ActiveScreen] {
        uses.compactMap { u in
            let rise = smooth((beats - (u.set - 0.5)) / 0.5)
            let fall = 1 - smooth((beats - (u.used + 0.5)) / 0.8)
            let w = min(rise, fall)
            guard w > 0.01 else { return nil }
            return ActiveScreen(screener: u.screener, user: u.user, spot: u.spot, weight: w, ballScreen: ballHolder == u.user)
        }
    }

    /// A switch: at `time` (beats), the defenders of `a` and `b` swap men.
    struct DefenseSwitch: Equatable, Sendable {
        var time: Double
        var a: Int
        var b: Int
    }

    /// The switches in this step: every screen used, when the defense
    /// switches (SWITCH; the other coverages stay with their men).
    static func switches(_ diagram: JournalPlayDiagram, plan: Schedule? = nil) -> [DefenseSwitch] {
        guard diagram.defenseMode == .man, (diagram.defenseScheme ?? .standard).screens == .switchAll else { return [] }
        return screenUses(diagram, plan: plan).map { DefenseSwitch(time: $0.used, a: $0.screener, b: $0.user) }
    }

    /// Who each defender guards at `beats` into the step, switches applied.
    static func guards(_ diagram: JournalPlayDiagram, at beats: Double, switches: [DefenseSwitch]) -> [Int?] {
        var guards = diagram.defense.map(\.guards)
        for s in switches where s.time <= beats {
            let i = guards.firstIndex(of: s.a), j = guards.firstIndex(of: s.b)
            if let i { guards[i] = s.b }
            if let j { guards[j] = s.a }
        }
        return guards
    }

    // MARK: - Writing the spots into a drawing

    /// The drawing with every defender at his spot when the step starts (what
    /// the editor and the still diagrams show). Unchanged without a mode.
    static func placingDefense(_ diagram: JournalPlayDiagram, court: JournalCourtKind) -> JournalPlayDiagram {
        guard diagram.defenseMode != nil else { return diagram }
        var out = diagram
        let players = Dictionary(diagram.offense.map { ($0.number, $0.at) }, uniquingKeysWith: { a, _ in a })
        let ball = diagram.balls.first.flatMap { players[$0] }
        let spots = defenseSpots(diagram, players: players, ball: ball, guards: diagram.defense.map(\.guards), court: court)
        for i in out.defense.indices { out.defense[i].at = spots[i] }
        return out
    }

    /// A defender dragged to `point` while the defense is automatic: the
    /// difference from his calculated spot becomes his nudge.
    static func nudging(defender i: Int, to point: JournalCourtPoint, in diagram: JournalPlayDiagram,
                        court: JournalCourtKind) -> JournalPlayDiagram {
        guard diagram.defense.indices.contains(i) else { return diagram }
        var bare = diagram
        bare.defense[i].nudge = nil
        let base = placingDefense(bare, court: court).defense[i].at
        var out = diagram
        let n = JournalCourtPoint(point.x - base.x, point.y - base.y)
        out.defense[i].nudge = hypot(n.x, n.y) < 0.15 ? nil : n
        return placingDefense(out, court: court)
    }

    /// Who guards whom by NEAREST player (Luther): the closest free pair first.
    static func nearestAssignment(defense: [JournalCourtPoint], offense: [JournalPlayDiagram.Player]) -> [Int?] {
        var pairs: [(d: Double, i: Int, n: Int)] = []
        for (i, at) in defense.enumerated() { for p in offense { pairs.append((at.distance(to: p.at), i, p.number)) } }
        var result = [Int?](repeating: nil, count: defense.count)
        var taken = Set<Int>()
        for pair in pairs.sorted(by: { $0.d < $1.d }) where result[pair.i] == nil && !taken.contains(pair.n) {
            result[pair.i] = pair.n
            taken.insert(pair.n)
        }
        return result
    }

    /// Turns auto defense on (or off, nil) for a part's steps, in order: the
    /// first step's defenders are matched (man: one per player, by nearest;
    /// zone: five, each to the nearest spot), and each later step starts
    /// with the previous step's defense, switches applied. Off keeps the
    /// defenders where they stand. `scheme` (man) goes on every step.
    static func applyingDefense(_ mode: JournalPlayDiagram.DefenseMode?, to steps: [JournalPlayDiagram],
                                court: JournalCourtKind, scheme: DefenseScheme? = nil) -> [JournalPlayDiagram] {
        guard let mode else {
            return steps.map { var d = $0; d.defenseMode = nil
                d.defense = d.defense.map { var x = $0; x.guards = nil; x.nudge = nil; return x }
                return d }
        }
        let scheme = scheme ?? steps.first?.defenseScheme
        var out: [JournalPlayDiagram] = []
        for (k, step) in steps.enumerated() {
            var d = step
            d.defenseMode = mode
            d.defenseScheme = scheme == .standard ? nil : scheme
            // The rules place the defenders now: their drawn cuts go.
            d.actions.removeAll { JournalPlayDiagram.defenderIndex($0.player) != nil }
            if k == 0 {
                d.defense = matched(mode, defense: d.defense, offense: d.offense, ball: d.balls.first.flatMap { d.player($0)?.at }, court: court)
            } else {
                d.defense = carriedDefense(from: out[k - 1])
            }
            out.append(placingDefense(d, court: court))
        }
        return out
    }

    /// A new scheme for a part's steps, keeping who guards whom on the first
    /// step and every nudge: later steps take the previous step's men again
    /// (a switch under SWITCH, none under the other coverages).
    static func applyingScheme(_ scheme: DefenseScheme, to steps: [JournalPlayDiagram],
                               court: JournalCourtKind) -> [JournalPlayDiagram] {
        var out: [JournalPlayDiagram] = []
        for (k, step) in steps.enumerated() {
            var d = step
            d.defenseScheme = scheme == .standard ? nil : scheme
            if d.defenseMode != nil, k > 0, out[k - 1].defenseMode != nil {
                let carried = carriedDefense(from: out[k - 1])
                if carried.count == d.defense.count {
                    for i in d.defense.indices { d.defense[i].guards = carried[i].guards }
                }
            }
            out.append(placingDefense(d, court: court))
        }
        return out
    }

    static func matched(_ mode: JournalPlayDiagram.DefenseMode, defense: [JournalPlayDiagram.Defender],
                        offense: [JournalPlayDiagram.Player], ball: JournalCourtPoint?, court: JournalCourtKind) -> [JournalPlayDiagram.Defender] {
        var defense = defense.map { var d = $0; d.nudge = nil; d.guards = nil; return d }
        if mode == .man {
            // One defender per player: extra ones go, missing ones arrive.
            let guards = nearestAssignment(defense: defense.map(\.at), offense: offense)
            defense = zip(defense, guards).compactMap { d, g in g.map { var d = d; d.guards = $0; return d } }
            let free = offense.map(\.number).filter { n in !defense.contains { $0.guards == n } }
            for n in free {
                let at = offense.first { $0.number == n }!.at
                defense.append(.init(at: at, guards: n))
            }
            return defense
        }
        // Zone: five defenders, each to the nearest spot.
        let spots = zoneSpots(mode, ball: ball, court: court)
        while defense.count < spots.count { defense.append(.init(at: spots[defense.count])) }
        defense = Array(defense.prefix(spots.count))
        var ordered = [JournalPlayDiagram.Defender?](repeating: nil, count: spots.count)
        var pairs: [(d: Double, i: Int, s: Int)] = []
        for (i, d) in defense.enumerated() { for (s, spot) in spots.enumerated() { pairs.append((d.at.distance(to: spot), i, s)) } }
        var used = Set<Int>()
        for pair in pairs.sorted(by: { $0.d < $1.d }) where ordered[pair.s] == nil && !used.contains(pair.i) {
            ordered[pair.s] = defense[pair.i]
            used.insert(pair.i)
        }
        return ordered.compactMap { $0 }
    }

    /// The defense the next step starts with: same defenders, nudges and
    /// reads, with this step's switches applied.
    static func carriedDefense(from diagram: JournalPlayDiagram) -> [JournalPlayDiagram.Defender] {
        let plan = schedule(diagram)
        let after = guards(diagram, at: .infinity, switches: switches(diagram, plan: plan))
        return diagram.defense.enumerated().map { i, d in var d = d; d.guards = after[i]; return d }
    }

    // MARK: - Format (1v1 … 5v5)

    /// "3v3" from the drawing: attackers against defenders (man matches one
    /// per attacker; a zone is five).
    static func format(_ diagram: JournalPlayDiagram) -> String? {
        let o = diagram.offense.count, d = diagram.defense.count
        guard o > 0 || d > 0 else { return nil }
        return "\(o)v\(d)"
    }

    /// Zones need five attackers — a 2-3 against three players puts two
    /// defenders on nobody.
    static func zonesFit(_ diagram: JournalPlayDiagram) -> Bool { diagram.offense.count >= 5 }
}
