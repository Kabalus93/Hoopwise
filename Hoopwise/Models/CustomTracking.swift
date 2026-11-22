import Foundation

// THE COACH'S OWN TRACKED DRILLS (23 Nov 2026, Luther: "I should be also able
// to create my own trackable drill … I would control the variables that I
// track (time, amount of shots, and other), what the score / result would
// mean on the player's oct evaluation"). Decided: four measures, one number
// per drill, compared with the athlete's own history and same-grade peers,
// and the octagon SUGGESTS a rating the coach takes with one tap.
//
// · DEFINITION — on the drill, in its synced tags as ONE `track:<base64
//   JSON>` tag (no schema change; syncs with the drill). Set in New / Edit
//   Drill → "Track results".
// · RESULTS — `SessionCurriculum.tracked` (curriculum JSON, its own key so a
//   build without this feature cannot misread the built-in shooting runs),
//   written field-level by `setSessionTracking` and kept by whole-session
//   saves like games and marks.
// · MEANING — the drill's linked octagon skills: each result shows beside
//   those skills in the evaluation with a rank among same-grade peers, and
//   `CustomTrackHistory.suggestion` turns the athlete's standing into a 1–10
//   hint the coach can take. It never sets a rating by itself.

/// What a custom tracked drill measures.
nonisolated enum TrackMeasure: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Makes of a fixed number of attempts → a share.
    case madeOf
    /// How many in a set time (makes, reps, passes).
    case inTime
    /// A stopwatch: how long it took. Lower is better.
    case timeToFinish
    /// A number with the coach's own unit (touches, points, streak).
    case count

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .madeOf: chinese ? "命中 / 出手" : "Made of attempts"
        case .inTime: chinese ? "限时计数" : "How many in a time"
        case .timeToFinish: chinese ? "用时" : "Time to finish"
        case .count: chinese ? "计数 / 得分" : "Count or points"
        }
    }

    func short(chinese: Bool) -> String {
        switch self {
        case .madeOf: chinese ? "命中率" : "Made of"
        case .inTime: chinese ? "限时" : "In a time"
        case .timeToFinish: chinese ? "用时" : "Time"
        case .count: chinese ? "计数" : "Count"
        }
    }

    var symbol: String {
        switch self {
        case .madeOf: "target"
        case .inTime: "timer"
        case .timeToFinish: "stopwatch"
        case .count: "number"
        }
    }
}

/// How a coach's drill is tracked. Stored on the drill.
nonisolated struct TrackDefinition: Codable, Hashable, Sendable {
    var measure: TrackMeasure = .madeOf
    /// madeOf: attempts a spot; inTime: seconds a spot; else unused.
    var amount: Int = 10
    /// Named spots or sides ("Left", "Right"); empty = one number.
    var spots: [String] = []
    /// count / inTime: what is counted ("passes"); empty = "makes" for
    /// inTime, nothing for count.
    var unit: String = ""
    /// count only: whether a bigger number is better.
    var higherIsBetter: Bool = true
    /// The octagon skills a result speaks for (DrillAttribute raw values).
    var skills: [String] = []

    init(measure: TrackMeasure = .madeOf, amount: Int = 10, spots: [String] = [], unit: String = "",
         higherIsBetter: Bool = true, skills: [String] = []) {
        self.measure = measure; self.amount = amount; self.spots = spots; self.unit = unit
        self.higherIsBetter = higherIsBetter; self.skills = skills
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measure = (try? c.decode(TrackMeasure.self, forKey: .measure)) ?? .count
        amount = (try? c.decode(Int.self, forKey: .amount)) ?? 10
        spots = (try? c.decode([String].self, forKey: .spots)) ?? []
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        higherIsBetter = (try? c.decode(Bool.self, forKey: .higherIsBetter)) ?? true
        skills = (try? c.decode([String].self, forKey: .skills)) ?? []
    }

    var spotCount: Int { max(1, spots.count) }
    var attributes: [DrillAttribute] { skills.compactMap(DrillAttribute.init(rawValue:)) }

    /// Results compare only under the same measure, amount and spots.
    var key: String { "\(measure.rawValue)|\(measure == .madeOf || measure == .inTime ? amount : 0)|\(spotCount)" }

    var lowerIsBetter: Bool {
        switch measure {
        case .timeToFinish: true
        case .count: !higherIsBetter
        default: false
        }
    }

    /// The largest number one spot can take (pad range).
    var maxEntry: Int {
        switch measure {
        case .madeOf: amount
        case .inTime: max(20, amount)
        case .timeToFinish: 600
        case .count: 200
        }
    }

    func spotName(_ i: Int, chinese: Bool) -> String {
        spots.indices.contains(i) ? spots[i] : (chinese ? "结果" : "Result")
    }

    func unitWord(chinese: Bool) -> String {
        if !unit.trimmingCharacters(in: .whitespaces).isEmpty { return unit }
        return measure == .inTime ? (chinese ? "次" : "makes") : ""
    }

    /// "10 shots · 2 spots", "1 min · passes", "Time · lower is better".
    func summary(chinese: Bool) -> String {
        var parts: [String] = []
        switch measure {
        case .madeOf: parts.append(chinese ? "每点 \(amount) 次出手" : (spots.count > 1 ? "\(amount) shots a spot" : "\(amount) attempts"))
        case .inTime:
            parts.append(ShootingSetup.time(amount, chinese: chinese) + (spots.count > 1 ? (chinese ? "／点" : " a spot") : ""))
            let w = unitWord(chinese: chinese); if !w.isEmpty { parts.append(w) }
        case .timeToFinish: parts.append(chinese ? "计时，越快越好" : "Timed, faster is better")
        case .count:
            let w = unitWord(chinese: chinese)
            parts.append(w.isEmpty ? (chinese ? "计数" : "Count") : w)
            parts.append(higherIsBetter ? (chinese ? "越多越好" : "higher is better") : (chinese ? "越少越好" : "lower is better"))
        }
        if spots.count > 1 { parts.append(spots.joined(separator: " / ")) }
        return parts.joined(separator: " · ")
    }

    /// One athlete's result from their spot entries (nil = not reported).
    /// madeOf → share 0…1 over the spots reported; inTime / count → the
    /// average a spot; time → average seconds.
    func result(_ values: [Double?]) -> Double? {
        let got = values.compactMap { $0 }
        guard !got.isEmpty else { return nil }
        switch measure {
        case .madeOf: return got.reduce(0, +) / Double(got.count * max(1, amount))
        default: return got.reduce(0, +) / Double(got.count)
        }
    }

    /// "70%", "12 makes", "14.2 s", "23 passes".
    func text(_ value: Double, chinese: Bool) -> String {
        switch measure {
        case .madeOf: return "\(Int((value * 100).rounded()))%"
        case .timeToFinish: return Self.seconds(value)
        case .inTime, .count:
            let n = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
            let w = unitWord(chinese: chinese)
            return w.isEmpty ? n : (chinese ? "\(n) \(w)" : "\(n) \(w)")
        }
    }

    /// One spot's entry as typed: makes, a count, or a time.
    func entryText(_ value: Double) -> String {
        measure == .timeToFinish ? Self.seconds(value) : (value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value))
    }

    static func seconds(_ s: Double) -> String {
        s >= 60 ? String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60)) : String(format: "%.1f s", s)
    }

    /// Is `a` better than `b`?
    func better(_ a: Double, than b: Double) -> Bool { lowerIsBetter ? a < b : a > b }
}

/// One custom tracked drill's results in a session.
nonisolated struct TrackedRun: Codable, Hashable, Identifiable, Sendable {
    var drillId: UUID
    /// The definition when the results were taken — later edits to the drill
    /// do not rewrite what was measured.
    var definition: TrackDefinition
    /// Athlete id (uuidString) → one value a spot, nil = not reported.
    var entries: [String: [Double?]] = [:]

    var id: UUID { drillId }

    func values(for student: UUID) -> [Double?] {
        let v = entries[student.uuidString] ?? []
        return (0..<definition.spotCount).map { v.indices.contains($0) ? v[$0] : nil }
    }

    func value(for student: UUID, spot: Int) -> Double? { values(for: student)[spot] }

    mutating func set(_ value: Double?, for student: UUID, spot: Int) {
        var v = values(for: student)
        guard v.indices.contains(spot) else { return }
        v[spot] = value
        entries[student.uuidString] = v.allSatisfy { $0 == nil } ? nil : v
    }

    func result(for student: UUID) -> Double? { definition.result(values(for: student)) }
    var hasResults: Bool { !entries.isEmpty }
}

// MARK: - On the drill

nonisolated extension DrillItem {
    static let trackPrefix = "track:"

    /// The coach's tracking for this drill, if it is tracked.
    var tracking: TrackDefinition? {
        guard let tag = tags.first(where: { $0.hasPrefix(Self.trackPrefix) }),
              let data = Data(base64Encoded: String(tag.dropFirst(Self.trackPrefix.count))) else { return nil }
        return try? JSONDecoder().decode(TrackDefinition.self, from: data)
    }

    /// `tags` with this tracking (nil removes it).
    static func tags(_ tags: [String], tracking: TrackDefinition?) -> [String] {
        var out = tags.filter { !$0.hasPrefix(trackPrefix) }
        if let tracking, let data = try? JSONEncoder().encode(tracking) {
            out.append(trackPrefix + data.base64EncodedString())
        }
        return out
    }
}

// MARK: - History, peers and the suggested rating

nonisolated enum CustomTrackHistory {
    struct Point: Hashable {
        let date: Date
        let value: Double
    }

    /// An athlete's results in one drill under one definition key, oldest first.
    static func series(_ student: UUID, drillId: UUID, key: String, sessions: [SessionEvent]) -> [Point] {
        sessions
            .filter { !SessionLifecycle.didNotHappen($0) }
            .compactMap { s -> Point? in
                guard let run = s.curriculum.tracked.first(where: { $0.drillId == drillId && $0.definition.key == key }),
                      let v = run.result(for: student) else { return nil }
                return Point(date: s.startTime, value: v)
            }
            .sorted { $0.date < $1.date }
    }

    /// Their result in this drill the last time before `date`.
    static func previous(_ student: UUID, drillId: UUID, key: String, before date: Date, sessions: [SessionEvent]) -> Double? {
        series(student, drillId: drillId, key: key, sessions: sessions).last { $0.date < date }?.value
    }

    /// What the evaluation shows for one drill: the athlete's standing.
    struct Standing: Hashable {
        let drillId: UUID
        let drillName: String
        let definition: TrackDefinition
        /// The average of their last three results.
        let recent: Double
        let sessions: Int
        /// 1 = best among peers with results; `of` = how many (≥ 2 to show).
        let rank: Int
        let of: Int
        /// 0 (bottom) … 1 (top) among peers; nil with fewer than 3.
        let percentile: Double?
        /// Their last three vs everything before, when both exist.
        let trend: Double?
    }

    /// Fewer peers with results than this and there is no suggestion.
    static let minimumPeers = 3

    /// Every custom drill this athlete has results in, with their standing
    /// among `peers` (same grade). `drills` resolves names and definitions.
    static func standings(for student: UUID, peers: [UUID], drills: [DrillItem], sessions: [SessionEvent]) -> [Standing] {
        let happened = sessions.filter { !SessionLifecycle.didNotHappen($0) }
        // drill → key → the definition, from the runs the athlete is in.
        var seen: [String: (UUID, TrackDefinition)] = [:]
        for s in happened {
            for run in s.curriculum.tracked where run.result(for: student) != nil {
                seen["\(run.drillId)|\(run.definition.key)"] = (run.drillId, run.definition)
            }
        }
        let everyone = Set(peers + [student])
        return seen.values.compactMap { drillId, def -> Standing? in
            func recent(_ id: UUID) -> (Double, Int, Double?)? {
                let points = series(id, drillId: drillId, key: def.key, sessions: happened)
                guard !points.isEmpty else { return nil }
                let last = points.suffix(3).map(\.value)
                let earlier = points.dropLast(3).map(\.value)
                let avg = last.reduce(0, +) / Double(last.count)
                let trend = earlier.isEmpty ? nil : avg - earlier.reduce(0, +) / Double(earlier.count)
                return (avg, points.count, trend)
            }
            guard let mine = recent(student) else { return nil }
            let values = everyone.compactMap { id in recent(id).map { (id, $0.0) } }
            let better = values.filter { $0.0 != student && def.better($0.1, than: mine.0) }.count
            let worse = values.filter { $0.0 != student && def.better(mine.0, than: $0.1) }.count
            let percentile = values.count >= minimumPeers
                ? (Double(worse) + 0.5 * Double(values.count - 1 - better - worse)) / Double(values.count - 1) : nil
            let name = drills.first { $0.id == drillId }?.localizedName ?? ""
            return Standing(drillId: drillId, drillName: name, definition: def, recent: mine.0, sessions: mine.1,
                            rank: better + 1, of: values.count, percentile: percentile, trend: mine.2)
        }
        .sorted { $0.drillName.localizedStandardCompare($1.drillName) == .orderedAscending }
    }

    /// The rating the results point to for one skill: the standings linked
    /// to it, as percentiles averaged and mapped onto 1–10 (bottom 2, top
    /// 9 — no drill alone says "perfect"). Nil without a peer comparison.
    static func suggestion(for axis: DrillAttribute, standings: [Standing]) -> Int? {
        let ps = standings.filter { $0.definition.attributes.contains(axis) }.compactMap(\.percentile)
        guard !ps.isEmpty else { return nil }
        let p = ps.reduce(0, +) / Double(ps.count)
        return min(9, max(2, Int((2 + p * 7).rounded())))
    }

    /// "Wall passes · 23 passes (last 3) · up 4 · 2nd of 9 same grade".
    static func text(_ s: Standing, chinese: Bool) -> String {
        var parts = [s.drillName, s.definition.text(s.recent, chinese: chinese) + (s.sessions > 1 ? (chinese ? "（近 3 次）" : " (last 3)") : "")]
        if let trend = s.trend, abs(trend) > 0.0001 {
            let improving = s.definition.lowerIsBetter ? trend < 0 : trend > 0
            let amount = s.definition.measure == .madeOf ? "\(Int((abs(trend) * 100).rounded()))%"
                : (s.definition.measure == .timeToFinish ? String(format: "%.1f s", abs(trend)) : String(format: "%g", (abs(trend) * 10).rounded() / 10))
            parts.append(improving ? (chinese ? "进步 \(amount)" : "better by \(amount)") : (chinese ? "退步 \(amount)" : "down \(amount)"))
        }
        if s.of >= 2 { parts.append(chinese ? "同年级 \(s.of) 人中第 \(s.rank)" : "\(ordinal(s.rank)) of \(s.of) same grade") }
        return parts.joined(separator: " · ")
    }

    static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : (["th", "st", "nd", "rd"] + Array(repeating: "th", count: 6))[n % 10]
        return "\(n)\(suffix)"
    }
}
