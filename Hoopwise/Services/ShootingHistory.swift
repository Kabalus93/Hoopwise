import Foundation

// An athlete's tracked shooting across sessions (20 Nov 2026). Pure. Every
// surface — the plan add-on's "last time", the athlete profile, the evidence
// beside the Shooting rating — reads this, so they cannot disagree.

enum ShootingHistory {
    struct Point: Hashable {
        let date: Date
        let sessionId: UUID
        let result: ShootingResult
        var value: Double { result.value }
    }

    /// One comparable test (same drill, mode, amount, range), oldest first.
    struct Series: Identifiable, Hashable {
        var id: String { setup.key }
        let setup: ShootingSetup
        let points: [Point]

        var latest: Point? { points.last }
        var best: Double? { points.map(\.value).max() }
        /// The last `n` results' average.
        func recent(_ n: Int = 3) -> Double? { average(points.suffix(n)) }
        /// The `n` before those.
        func earlier(_ n: Int = 3) -> Double? {
            guard points.count > n else { return nil }
            return average(points.dropLast(n).suffix(n))
        }
        /// Per spot over every result (5-spot drills): for hot / cold spots.
        var spotAverages: [Double?] {
            (0..<setup.drill.spotCount).map { spot in
                let values = points.compactMap { $0.result.spotValue(spot) }
                return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
        }

        private func average<S: Sequence>(_ s: S) -> Double? where S.Element == Point {
            let v = s.map(\.value)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
    }

    /// Every test the athlete has a result in, most recent first.
    static func series(for student: UUID, sessions: [SessionEvent]) -> [Series] {
        var byKey: [String: (ShootingSetup, [Point])] = [:]
        for s in sessions where !SessionLifecycle.didNotHappen(s) {
            for run in s.curriculum.shooting {
                guard let result = run.result(for: student) else { continue }
                let key = run.setup.key
                var entry = byKey[key] ?? (run.setup, [])
                entry.1.append(Point(date: s.startTime, sessionId: s.id, result: result))
                byKey[key] = entry
            }
        }
        return byKey.values
            .map { Series(setup: $0.0, points: $0.1.sorted { $0.date < $1.date }) }
            .sorted { ($0.latest?.date ?? .distantPast) > ($1.latest?.date ?? .distantPast) }
    }

    /// The athlete's last result in this test before `date` (the add-on's
    /// "last time").
    static func previous(_ student: UUID, setup: ShootingSetup, before date: Date,
                         sessions: [SessionEvent]) -> ShootingResult? {
        sessions
            .filter { !SessionLifecycle.didNotHappen($0) && $0.startTime < date }
            .sorted { $0.startTime > $1.startTime }
            .lazy
            .compactMap { s in s.curriculum.shooting.first { $0.setup.key == setup.key }?.result(for: student) }
            .first
    }

    // MARK: The athlete's shot chart (21 Nov 2026)
    //
    // Fed by every tracked drill that has a place on the floor: the Shot
    // Chart itself (zone = zone), 5-Spot Threes (the five three-point zones),
    // 5-Spot Twos at MID range (corners → baseline mid, wings → elbows, top
    // split between the elbows), and lay-ups / the Mikan drill (at the rim).
    // Timed results have no attempts, so they cannot make a percentage.
    // Free throws sit beside the map (`freeThrows`).

    /// One run's contribution to the ten zones.
    static func zones(of run: ShootingRun, student: UUID) -> [ShotZoneValue?] {
        var out = [ShotZoneValue?](repeating: nil, count: 10)
        guard run.setup.mode.isShare, let r = run.result(for: student) else { return out }
        func add(_ zone: Int, _ made: Double, _ att: Double) {
            var z = out[zone] ?? ShotZoneValue(made: 0, attempted: 0)
            z.made += made; z.attempted += att
            out[zone] = z
        }
        for spot in 0..<run.setup.drill.spotCount {
            guard let s = r.shots(at: spot) else { continue }
            let m = Double(s.made), a = Double(s.attempted)
            switch run.setup.drill {
            case .shotChart: add(spot, m, a)
            case .threes: add(5 + spot, m, a)
            case .twos:
                guard run.setup.range != .short else { continue }
                switch spot {
                case 0: add(1, m, a)
                case 1: add(2, m, a)
                case 2: add(2, m / 2, a / 2); add(3, m / 2, a / 2)
                case 3: add(3, m, a)
                default: add(4, m, a)
                }
            case .layups, .mikan: add(0, m, a)
            default: break
            }
        }
        return out
    }

    private static func merge(_ a: [ShotZoneValue?], _ b: [ShotZoneValue?]) -> [ShotZoneValue?] {
        zip(a, b).map { x, y in
            guard let y else { return x }
            guard let x else { return y }
            return ShotZoneValue(made: x.made + y.made, attempted: x.attempted + y.attempted)
        }
    }

    /// The athlete's ten zones over the sessions given (optionally only
    /// those before a date).
    static func zoneMap(for student: UUID, sessions: [SessionEvent], before: Date? = nil) -> [ShotZoneValue?] {
        var out = [ShotZoneValue?](repeating: nil, count: 10)
        for s in sessions where !SessionLifecycle.didNotHappen(s) && (before.map { s.startTime < $0 } ?? true) {
            for run in s.curriculum.shooting { out = merge(out, zones(of: run, student: student)) }
            // The coach's own shooting / finishing drills (24 Nov 2026).
            for run in s.curriculum.tracked { out = merge(out, zones(of: run, student: student)) }
        }
        return out
    }

    /// A coach's tracked drill on the ten zones: a made-of shooting drill
    /// at the zones it names, a made-of finishing drill at the rim.
    static func zones(of run: TrackedRun, student: UUID) -> [ShotZoneValue?] {
        var out = [ShotZoneValue?](repeating: nil, count: 10)
        let def = run.definition
        for (spot, value) in run.values(for: student).enumerated() {
            guard let value, let zone = def.zone(forSpot: spot) else { continue }
            var z = out[zone] ?? ShotZoneValue(made: 0, attempted: 0)
            z.made += value; z.attempted += Double(def.amount)
            out[zone] = z
        }
        return out
    }

    /// The latest session that put anything on the athlete's map.
    static func latestMapSession(for student: UUID, sessions: [SessionEvent]) -> SessionEvent? {
        sessions
            .filter { s in !SessionLifecycle.didNotHappen(s)
                && (s.curriculum.shooting.contains { zones(of: $0, student: student).contains { $0 != nil } }
                    || s.curriculum.tracked.contains { zones(of: $0, student: student).contains { $0 != nil } }) }
            .max { $0.startTime < $1.startTime }
    }

    /// Change per zone between the map before `date` and the map with it.
    static func deltas(_ now: [ShotZoneValue?], _ then: [ShotZoneValue?]) -> [Double?] {
        zip(now, then).map { n, t in
            guard let n, let t, n.attempted > 0, t.attempted > 0 else { return nil }
            return n.share - t.share
        }
    }

    /// Free throws (made of N, or chart) over the sessions given.
    static func freeThrows(for student: UUID, sessions: [SessionEvent]) -> ShotZoneValue? {
        var total = ShotZoneValue(made: 0, attempted: 0)
        for s in sessions where !SessionLifecycle.didNotHappen(s) {
            for run in s.curriculum.shooting where run.setup.drill == .freeThrows && run.setup.mode.isShare {
                guard let r = run.result(for: student) else { continue }
                total.made += Double(r.made); total.attempted += Double(r.attempted)
            }
        }
        return total.attempted > 0 ? total : nil
    }

    // MARK: Evidence beside the Shooting rating

    struct Evidence: Hashable {
        let setup: ShootingSetup
        let recent: Double
        let earlier: Double?
        let results: Int
        /// Among athletes of the same grade who took the same test.
        let rank: Int
        let of: Int
    }

    /// One line per test, most recent first (at most three).
    static func evidence(for student: UUID, peers: [UUID], sessions: [SessionEvent]) -> [Evidence] {
        let mine = series(for: student, sessions: sessions)
        guard !mine.isEmpty else { return [] }
        let others = Set(peers).subtracting([student])
        let peerSeries = others.map { series(for: $0, sessions: sessions) }
        return mine.prefix(3).compactMap { s in
            guard let recent = s.recent() else { return nil }
            let theirs = peerSeries.compactMap { list in list.first { $0.setup.key == s.setup.key }?.recent() }
            let rank = theirs.filter { $0 > recent }.count + 1
            return Evidence(setup: s.setup, recent: recent, earlier: s.earlier(),
                            results: s.points.count, rank: rank, of: theirs.count + 1)
        }
    }

    /// "FT · 10 shots: 64% (last 3) · up from 48% · 2nd of 9 same grade".
    static func text(_ e: Evidence, chinese: Bool) -> String {
        var parts = ["\(e.setup.drill.short(chinese: chinese)) · \(e.setup.summary(chinese: chinese)): "
                     + ShootingResult.text(e.recent, mode: e.setup.mode, chinese: chinese)
                     + (e.results > 1 ? (chinese ? "（近 \(min(e.results, 3)) 次）" : " (last \(min(e.results, 3)))") : "")]
        if let earlier = e.earlier {
            let then = ShootingResult.text(earlier, mode: e.setup.mode, chinese: chinese)
            if e.recent > earlier * 1.02 { parts.append(chinese ? "高于之前的 \(then)" : "up from \(then)") }
            else if e.recent < earlier * 0.98 { parts.append(chinese ? "低于之前的 \(then)" : "down from \(then)") }
            else { parts.append(chinese ? "与之前持平" : "steady") }
        }
        if e.of > 1 {
            parts.append(chinese ? "同年级第 \(e.rank)/\(e.of)" : "\(ordinal(e.rank)) of \(e.of) same grade")
        }
        return parts.joined(separator: " · ")
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
