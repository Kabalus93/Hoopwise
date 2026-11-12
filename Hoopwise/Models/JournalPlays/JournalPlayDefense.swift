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
// · help and the post (man): the weak-side defender nearest the driving
//   line steps in as the ball nears the rim; a post man is played three-
//   quarters on the ball side (`manTeamSpots`);
// · 2-3 / 3-2 — five areas around the basket that shift with the ball; each
//   defender guards the ball or shades the attacker in his area, sinks when
//   it is empty, and someone always protects the paint (`zoneSpots`).
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

    /// Every zone defender's spot (12 November 2026, Luther: "for zone the
    /// defense only reacts to the ball and disregards the other players").
    /// A zone guards AREAS and plays whoever is in them:
    /// · the five spots shift toward the ball (`anchors`); every attacker
    ///   within reach belongs to the area of the nearest spot — so the areas
    ///   move with the ball and a cutter is handed from area to area;
    /// · the ball in your area: guard the ball;
    /// · one attacker in your area: shade him — between him and the basket,
    ///   leaning to the ball — without leaving your spot (60 %);
    /// · two: the one nearer the basket, less far (45 %);
    /// · none: sink toward the ball and the paint;
    /// · the ball outside every area (deep): the nearest spot shows, no chase;
    /// · someone always protects the paint.
    static func zoneSpots(_ mode: JournalPlayDiagram.DefenseMode, ball: JournalCourtPoint?,
                          players: [Int: JournalCourtPoint] = [:], court: JournalCourtKind) -> [JournalCourtPoint] {
        let (basket, out, side) = defenseFrame(court)
        func world(_ s: Double, _ o: Double) -> JournalCourtPoint {
            JournalCourtPoint(basket.x + side.x * s + out.x * o, basket.y + side.y * s + out.y * o)
        }
        func lerp(_ a: JournalCourtPoint, _ b: JournalCourtPoint, _ t: Double) -> JournalCourtPoint {
            JournalCourtPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
        let ball = ball ?? world(0, 6.5)
        let bs = (ball.x - basket.x) * side.x + (ball.y - basket.y) * side.y
        let bo = (ball.x - basket.x) * out.x + (ball.y - basket.y) * out.y
        let anchors = zoneSlots(mode).map { slot in
            world(slot.side + bs * 0.3, slot.out + min(max(bo - 5, -2), 2) * 0.2)
        }
        guard !anchors.isEmpty else { return [] }

        // Who holds the ball: the attacker on it.
        let holder = players.min { $0.value.distance(to: ball) < $1.value.distance(to: ball) }
            .flatMap { $0.value.distance(to: ball) < 0.6 ? $0.key : nil }
        // Every attacker within the zone's reach (inside ~9.5 m of the rim),
        // in the area of the nearest spot.
        var areas = [[Int]](repeating: [], count: anchors.count)
        for (number, at) in players where at.distance(to: basket) <= 9.5 {
            let i = anchors.indices.min { anchors[$0].distance(to: at) < anchors[$1].distance(to: at) }!
            areas[i].append(number)
        }
        var spots = anchors
        var ballCovered = false
        for i in anchors.indices {
            let here = areas[i]
            if let h = holder, here.contains(h) {
                spots[i] = manSpot(guarding: ball, ball: ball, court: court)
                ballCovered = true
            } else if let man = here.min(by: { players[$0]!.distance(to: basket) < players[$1]!.distance(to: basket) }) {
                spots[i] = lerp(anchors[i], manSpot(guarding: players[man]!, ball: ball, court: court), here.count == 1 ? 0.6 : 0.45)
            } else {
                spots[i] = lerp(anchors[i], lerp(ball, basket, 0.6), 0.15)
            }
        }
        // The ball handler outside every area (or no players given): the
        // nearest spot steps up — all the way inside the arc, half beyond it.
        if !ballCovered, let i = anchors.indices.min(by: { anchors[$0].distance(to: ball) < anchors[$1].distance(to: ball) }) {
            spots[i] = lerp(anchors[i], manSpot(guarding: ball, ball: ball, court: court), bo < 8.5 ? 1 : 0.4)
        }
        // Paint protection: someone stays within 2.5 m of the front of the rim.
        let paint = world(bs > 0 ? 0.6 : -0.6, 1.4)
        if !spots.contains(where: { $0.distance(to: paint) < 2.5 }) {
            let free = anchors.indices.filter { areas[$0].isEmpty }
            let pool = free.isEmpty ? Array(anchors.indices) : free
            if let i = pool.min(by: { spots[$0].distance(to: paint) < spots[$1].distance(to: paint) }) {
                spots[i] = lerp(spots[i], paint, 0.8)
            }
        }
        return spots.map { clamp($0, court) }
    }

    // MARK: - Man-to-man: help and the post

    /// The man defense's team rules on top of each defender's own spot:
    /// · POST: a man within ~3.8 m of the rim (not the ball) is played three-
    ///   quarters on the ball side, not from behind;
    /// · HELP: as the ball gets within 5.5 m of the rim, the weak-side
    ///   defender nearest the driving line (his man ≥ 4 m from the ball)
    ///   steps into it, 1.4 m in front of the ball — leaving his man open.
    static func manTeamSpots(_ spots: [JournalCourtPoint?], guards: [Int?], players: [Int: JournalCourtPoint],
                             ball: JournalCourtPoint?, court: JournalCourtKind) -> [JournalCourtPoint?] {
        guard let ball else { return spots }
        let basket = defenseFrame(court).basket
        func lerp(_ a: JournalCourtPoint, _ b: JournalCourtPoint, _ t: Double) -> JournalCourtPoint {
            JournalCourtPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
        func unit(_ from: JournalCourtPoint, _ to: JournalCourtPoint) -> JournalCourtPoint {
            let d = max(from.distance(to: to), 0.01)
            return JournalCourtPoint((to.x - from.x) / d, (to.y - from.y) / d)
        }
        var out = spots
        let holder = players.min { $0.value.distance(to: ball) < $1.value.distance(to: ball) }
            .flatMap { $0.value.distance(to: ball) < 0.6 ? $0.key : nil }

        // Post: three-quarter on the ball side.
        for i in out.indices {
            guard let spot = out[i], let g = guards[i], g != holder, let man = players[g] else { continue }
            let dRim = man.distance(to: basket)
            let p = min(max((3.8 - dRim) / 1.5, 0), 1)
            guard p > 0, ball.distance(to: man) < 9 else { continue }
            let toBall = unit(man, ball), toRim = unit(man, basket)
            let front = JournalCourtPoint(man.x + toBall.x * 0.9 + toRim.x * 0.4, man.y + toBall.y * 0.9 + toRim.y * 0.4)
            out[i] = lerp(spot, front, p)
        }

        // Help on the drive.
        let dBall = ball.distance(to: basket)
        let s = min(max((5.5 - dBall) / 2.5, 0), 1)
        if s > 0 {
            let toRim = unit(ball, basket)
            let gap = JournalCourtPoint(ball.x + toRim.x * 1.4, ball.y + toRim.y * 1.4)
            let candidates = out.indices.filter { i in
                guard out[i] != nil, let g = guards[i], g != holder, let man = players[g] else { return false }
                return man.distance(to: ball) >= 4
            }
            if let helper = candidates.min(by: { out[$0]!.distance(to: gap) < out[$1]!.distance(to: gap) }) {
                out[helper] = lerp(out[helper]!, gap, s)
            }
        }
        return out
    }

    // MARK: - Spots for a moment

    /// Each defender's spot (nudge included), given where everyone and the
    /// ball are; `guards` is who each defender guards at that moment (man).
    /// A man defender with no one to guard keeps `at`.
    static func defenseSpots(_ diagram: JournalPlayDiagram, players: [Int: JournalCourtPoint], ball: JournalCourtPoint?,
                             guards: [Int?], court: JournalCourtKind) -> [JournalCourtPoint] {
        guard let mode = diagram.defenseMode else { return diagram.defense.map(\.at) }
        var bases: [JournalCourtPoint?]
        if mode == .man {
            bases = diagram.defense.indices.map { i in
                (i < guards.count ? guards[i] : nil).flatMap { players[$0] }.map { manSpot(guarding: $0, ball: ball, court: court) }
            }
            bases = manTeamSpots(bases, guards: diagram.defense.indices.map { $0 < guards.count ? guards[$0] : nil },
                                 players: players, ball: ball, court: court)
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
    /// circle): within a metre of one, he is pushed out to a metre — away
    /// from him, else toward the basket.
    static func clearOf<S: Sequence>(_ attackers: S, _ spot: JournalCourtPoint, basket: JournalCourtPoint) -> JournalCourtPoint
    where S.Element == JournalCourtPoint {
        var spot = spot
        for a in attackers {
            let d = spot.distance(to: a)
            guard d < 1.0 else { continue }
            var dx = spot.x - a.x, dy = spot.y - a.y
            if d < 0.05 { dx = basket.x - a.x; dy = basket.y - a.y }
            let len = max((dx * dx + dy * dy).squareRoot(), 0.01)
            spot = JournalCourtPoint(a.x + dx / len * 1.0, a.y + dy / len * 1.0)
        }
        return spot
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
