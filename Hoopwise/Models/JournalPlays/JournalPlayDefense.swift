import Foundation

// AUTO DEFENSE (12 November 2026, Luther: "assigning a defender to an
// offensive player … moving an offensive player automatically has the
// defender follow him in a natural way … awareness of screens"; decided:
// calculated with nudging, assigned by nearest player, switch everything, a
// choice of man-to-man, 2-3 and 3-2).
//
// With `defenseMode` set, a defender's spot is WORKED OUT, never drawn:
// · man-to-man — the ball–you–man triangle: about a metre off the ball
//   handler toward the basket; off the ball, the further from the ball the
//   more he sags toward the basket and the ball line (help). Continuous, so
//   a closeout happens by itself as a pass flies.
// · 2-3 / 3-2 — five zone spots around the basket that shift toward the
//   ball; the spot nearest the ball steps up to it.
// · the coach's NUDGE (`Defender.nudge`) is added on top and carried.
// · SWITCH EVERYTHING: when a player uses a screen (a move drawn after it
//   that passes within 1.5 m of where it was set), the two defenders swap
//   men at that moment and keep them in the next steps.
// · in playback each defender reacts a fraction of a beat late (his spot is
//   averaged over the last `reactionBeats`), so a switch or a closeout
//   slides instead of jumping.
// The attacked basket is the court's first (half court: the one; full
// court: the right).

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

    private static func clamp(_ p: JournalCourtPoint, _ court: JournalCourtKind) -> JournalCourtPoint {
        let size = court.size
        return JournalCourtPoint(min(max(p.x, 0.3), size.width - 0.3), min(max(p.y, 0.3), size.height - 0.3))
    }

    // MARK: - Man-to-man

    /// Where a man-to-man defender stands against `man` with the ball at `ball`.
    static func manSpot(guarding man: JournalCourtPoint, ball: JournalCourtPoint?, court: JournalCourtKind) -> JournalCourtPoint {
        let basket = defenseFrame(court).basket
        let toBasket = JournalCourtPoint(basket.x - man.x, basket.y - man.y)
        let dBasket = max(man.distance(to: basket), 0.01)
        let ball = ball ?? man
        let dBall = man.distance(to: ball)
        // 0 on the ball, 1 two passes away.
        let t = min(max((dBall - 3) / 7, 0), 1)
        let gap = min(1.5, dBasket * 0.5)
        let sag = min(0.25 * t, 3.0 / dBasket)            // toward the basket, at most 3 m
        let help = 0.2 * t                                // toward the ball
        return clamp(JournalCourtPoint(
            man.x + toBasket.x / dBasket * gap + toBasket.x * sag + (ball.x - man.x) * help,
            man.y + toBasket.y / dBasket * gap + toBasket.y * sag + (ball.y - man.y) * help), court)
    }

    // MARK: - Zones

    /// The five zone spots, as (across, out from the basket) in metres.
    static func zoneSlots(_ mode: JournalPlayDiagram.DefenseMode) -> [(side: Double, out: Double)] {
        switch mode {
        case .man: return []
        case .zone23: return [(-2.2, 5.6), (2.2, 5.6), (-3.9, 1.8), (3.9, 1.8), (0, 1.2)]
        case .zone32: return [(0, 6.8), (-4.2, 5.0), (4.2, 5.0), (-2.2, 1.4), (2.2, 1.4)]
        }
    }

    /// Every zone defender's spot with the ball at `ball`.
    static func zoneSpots(_ mode: JournalPlayDiagram.DefenseMode, ball: JournalCourtPoint?, court: JournalCourtKind) -> [JournalCourtPoint] {
        let (basket, out, side) = defenseFrame(court)
        func world(_ s: Double, _ o: Double) -> JournalCourtPoint {
            JournalCourtPoint(basket.x + side.x * s + out.x * o, basket.y + side.y * s + out.y * o)
        }
        let ball = ball ?? world(0, 6.5)
        let bs = (ball.x - basket.x) * side.x + (ball.y - basket.y) * side.y
        let bo = (ball.x - basket.x) * out.x + (ball.y - basket.y) * out.y
        var spots = zoneSlots(mode).map { slot in
            world(slot.side + bs * 0.3, slot.out + min(max(bo - 5, -2), 2) * 0.2)
        }
        // The spot nearest the ball steps up to it (inside the zone's reach).
        if bo < 10, let i = spots.indices.min(by: { spots[$0].distance(to: ball) < spots[$1].distance(to: ball) }) {
            spots[i] = manSpot(guarding: ball, ball: ball, court: court)
        }
        return spots.map { clamp($0, court) }
    }

    // MARK: - Spots for a moment

    /// Each defender's spot (nudge included), given where everyone and the
    /// ball are; `guards` is who each defender guards at that moment (man).
    /// A man defender with no one to guard keeps `at`.
    static func defenseSpots(_ diagram: JournalPlayDiagram, players: [Int: JournalCourtPoint], ball: JournalCourtPoint?,
                             guards: [Int?], court: JournalCourtKind) -> [JournalCourtPoint] {
        guard let mode = diagram.defenseMode else { return diagram.defense.map(\.at) }
        let zone = mode == .man ? [] : zoneSpots(mode, ball: ball, court: court)
        return diagram.defense.enumerated().map { i, defender in
            let base: JournalCourtPoint?
            if mode == .man {
                base = (i < guards.count ? guards[i] : nil).flatMap { players[$0] }.map { manSpot(guarding: $0, ball: ball, court: court) }
            } else {
                base = i < zone.count ? zone[i] : nil
            }
            guard let base else { return defender.at }
            let n = defender.nudge ?? JournalCourtPoint(0, 0)
            return clamp(JournalCourtPoint(base.x + n.x, base.y + n.y), court)
        }
    }

    // MARK: - Switch everything

    /// A switch: at `time` (beats), the defenders of `a` and `b` swap men.
    struct DefenseSwitch: Equatable, Sendable {
        var time: Double
        var a: Int
        var b: Int
    }

    /// The screens used in this step: the screener and the player whose move,
    /// drawn after the screen, passes within 1.5 m of where it was set — at
    /// the moment he goes past it.
    static func switches(_ diagram: JournalPlayDiagram, plan: Schedule? = nil) -> [DefenseSwitch] {
        guard diagram.defenseMode == .man else { return [] }
        let plan = plan ?? schedule(diagram)
        var out: [DefenseSwitch] = []
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
            if let best { out.append(DefenseSwitch(time: max(best.time, screen.end), a: screener, b: best.user)) }
        }
        return out.sorted { $0.time < $1.time }
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
    /// defenders where they stand.
    static func applyingDefense(_ mode: JournalPlayDiagram.DefenseMode?, to steps: [JournalPlayDiagram],
                                court: JournalCourtKind) -> [JournalPlayDiagram] {
        guard let mode else {
            return steps.map { var d = $0; d.defenseMode = nil
                d.defense = d.defense.map { var x = $0; x.guards = nil; x.nudge = nil; return x }
                return d }
        }
        var out: [JournalPlayDiagram] = []
        for (k, step) in steps.enumerated() {
            var d = step
            d.defenseMode = mode
            if k == 0 {
                d.defense = matched(mode, defense: d.defense, offense: d.offense, ball: d.balls.first.flatMap { d.player($0)?.at }, court: court)
            } else {
                d.defense = carriedDefense(from: out[k - 1])
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
}
