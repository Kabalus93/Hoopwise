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
