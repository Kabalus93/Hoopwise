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

// THE TYPE DRIVES IT (24 Nov 2026, Luther: "the kind of tracking should
// determine the setup, how it integrates with the app … shooting: how it's
// measured, what it impacts in the eval — how much of Shooting plus how much
// of athleticism — needs a shot map? … conditioning: laps in how long,
// sprints on a distance"). `TrackKind` is chosen first; its `Preset` fills
// the measure, amount, unit, sides and the skills as MAIN or SOME; the
// coach can change any of it. Shooting drills name the SHOT-MAP ZONES they
// are taken from (results join the athlete's shot chart); finishing drills
// land at the rim; conditioning and ball-handling drills name the COURSE
// (so a time compares only with the same distance).

/// What kind of drill is tracked — picked first, it sets the rest up.
nonisolated enum TrackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shooting, finishing, ballHandling, passing, conditioning, defense, other

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .shooting: chinese ? "投篮" : "Shooting"
        case .finishing: chinese ? "终结" : "Finishing"
        case .ballHandling: chinese ? "运球" : "Ball handling"
        case .passing: chinese ? "传球" : "Passing"
        case .conditioning: chinese ? "体能" : "Conditioning"
        case .defense: chinese ? "防守" : "Defense"
        case .other: chinese ? "其他" : "Other"
        }
    }

    var symbol: String {
        switch self {
        case .shooting: "scope"
        case .finishing: "arrow.up.right.circle"
        case .ballHandling: "basketball"
        case .passing: "arrow.left.arrow.right"
        case .conditioning: "figure.run"
        case .defense: "shield.lefthalf.filled"
        case .other: "slider.horizontal.3"
        }
    }

    /// The measures that make sense for this kind, the usual one first.
    var measures: [TrackMeasure] {
        switch self {
        case .shooting: [.madeOf, .inTime, .count]
        case .finishing: [.madeOf, .inTime]
        case .ballHandling: [.timeToFinish, .inTime, .count]
        case .passing: [.inTime, .madeOf, .count]
        case .conditioning: [.timeToFinish, .inTime, .count]
        case .defense: [.inTime, .madeOf, .count]
        case .other: TrackMeasure.allCases
        }
    }

    /// Whether a course (distance) belongs to this kind's drills.
    var usesCourse: Bool { self == .conditioning || self == .ballHandling }
    /// Whether the drill's shots have a place on the shot map.
    var usesShotMap: Bool { self == .shooting }

    /// What this kind calls a measure ("Time over a distance" for a sprint).
    func measureTitle(_ m: TrackMeasure, chinese: Bool) -> String {
        switch (self, m) {
        case (.conditioning, .timeToFinish): chinese ? "完成距离用时" : "Time over a distance"
        case (.conditioning, .inTime): chinese ? "限时圈数 / 次数" : "Laps or reps in a time"
        case (.ballHandling, .timeToFinish): chinese ? "完成路线用时" : "Time through the course"
        case (.ballHandling, .count): chinese ? "失误次数" : "Errors (fewer is better)"
        case (.shooting, .inTime), (.finishing, .inTime): chinese ? "限时命中" : "Makes in a time"
        case (.defense, .madeOf): chinese ? "防守成功 / 回合" : "Stops of attempts"
        case (.passing, .madeOf): chinese ? "到位 / 传球" : "On target of attempts"
        default: m.title(chinese: chinese)
        }
    }

    /// The definition this kind starts from with `measure` (nil = its usual
    /// one). The coach's own drill name and text are not touched.
    func preset(measure: TrackMeasure? = nil, chinese: Bool) -> TrackDefinition {
        let m = measure.flatMap { measures.contains($0) ? $0 : nil } ?? measures[0]
        var d = TrackDefinition(measure: m)
        d.kind = self
        switch self {
        case .shooting:
            d.skills = ["shooting", "footwork"]; d.some = ["footwork"]
            d.amount = m == .inTime ? 60 : 10
        case .finishing:
            d.skills = ["finishing", "footwork"]; d.some = ["footwork"]
            d.amount = m == .inTime ? 60 : 10
            // Each hand its own makes-of-N; a timed run is one number.
            if m == .madeOf { d.spots = chinese ? ["右手", "左手"] : ["Right hand", "Left hand"] }
        case .ballHandling:
            d.skills = ["ballHandling", "footwork"]; d.some = ["footwork"]
            d.amount = m == .inTime ? 30 : 10
            if m == .count { d.unit = chinese ? "次失误" : "errors"; d.higherIsBetter = false }
            if m == .inTime { d.unit = chinese ? "次" : "reps" }
            if m == .timeToFinish { d.course = .fullCourt }
        case .passing:
            d.skills = ["passing", "gameIQ"]; d.some = ["gameIQ"]
            d.amount = m == .inTime ? 30 : 10
            if m != .madeOf { d.unit = chinese ? "次传球" : "passes" }
        case .conditioning:
            d.skills = ["footwork", "defense"]; d.some = ["defense"]
            d.amount = m == .inTime ? 60 : 10
            if m == .timeToFinish { d.course = .downAndBack }
            if m == .inTime { d.unit = chinese ? "圈" : "laps"; d.course = .lap }
            if m == .count { d.unit = chinese ? "次" : "reps" }
        case .defense:
            d.skills = ["defense", "footwork"]; d.some = ["footwork"]
            d.amount = m == .inTime ? 30 : 10
            if m == .inTime { d.unit = chinese ? "次滑步" : "slides" }
            if m == .count { d.unit = chinese ? "次" : "stops" }
        case .other:
            d.amount = m == .inTime ? 60 : 10
        }
        return d
    }
}

/// The distance a timed drill covers — part of what makes two results
/// comparable.
nonisolated enum TrackCourse: String, Codable, CaseIterable, Identifiable, Sendable {
    case halfCourt, fullCourt, downAndBack, lineDrill, seventeens, lap

    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .halfCourt: chinese ? "半场（14 米）" : "Half court (14 m)"
        case .fullCourt: chinese ? "全场（28 米）" : "Full court (28 m)"
        case .downAndBack: chinese ? "全场往返（56 米）" : "Down and back (56 m)"
        case .lineDrill: chinese ? "折返跑（各线）" : "Line drill (suicide)"
        case .seventeens: chinese ? "边线 17 趟" : "17s (sideline × 17)"
        case .lap: chinese ? "绕场一圈" : "A lap of the court"
        }
    }

    func short(chinese: Bool) -> String {
        switch self {
        case .halfCourt: chinese ? "半场" : "Half court"
        case .fullCourt: chinese ? "全场" : "Full court"
        case .downAndBack: chinese ? "全场往返" : "Down and back"
        case .lineDrill: chinese ? "折返跑" : "Line drill"
        case .seventeens: chinese ? "17 趟" : "17s"
        case .lap: chinese ? "绕场圈" : "Court laps"
        }
    }
}

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
    /// Which of `skills` count as SOME rather than MAIN (half weight).
    var some: [String] = []
    /// The kind of drill — it set the rest up. Definitions from before
    /// kinds read as `.other`.
    var kind: TrackKind = .other
    /// Shooting: the shot-map zones (0…9, ShootingDrill.shotChart's order)
    /// the drill is shot from — one number a zone, in this order. Empty =
    /// no place on the map.
    var zones: [Int] = []
    /// Conditioning / ball handling: the distance covered.
    var course: TrackCourse?

    init(measure: TrackMeasure = .madeOf, amount: Int = 10, spots: [String] = [], unit: String = "",
         higherIsBetter: Bool = true, skills: [String] = []) {
        self.measure = measure; self.amount = amount; self.spots = spots; self.unit = unit
        self.higherIsBetter = higherIsBetter; self.skills = skills
    }

    private enum CodingKeys: String, CodingKey {
        case measure, amount, spots, unit, higherIsBetter, skills, some, kind, zones, course
    }

    /// Only what is set is written, so a plain definition's JSON (and tag)
    /// is what it was before kinds.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(measure, forKey: .measure)
        try c.encode(amount, forKey: .amount)
        try c.encode(spots, forKey: .spots)
        try c.encode(unit, forKey: .unit)
        try c.encode(higherIsBetter, forKey: .higherIsBetter)
        try c.encode(skills, forKey: .skills)
        if !some.isEmpty { try c.encode(some, forKey: .some) }
        if kind != .other { try c.encode(kind, forKey: .kind) }
        if !zones.isEmpty { try c.encode(zones, forKey: .zones) }
        if let course { try c.encode(course, forKey: .course) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measure = (try? c.decode(TrackMeasure.self, forKey: .measure)) ?? .count
        amount = (try? c.decode(Int.self, forKey: .amount)) ?? 10
        spots = (try? c.decode([String].self, forKey: .spots)) ?? []
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        higherIsBetter = (try? c.decode(Bool.self, forKey: .higherIsBetter)) ?? true
        skills = (try? c.decode([String].self, forKey: .skills)) ?? []
        some = (try? c.decode([String].self, forKey: .some)) ?? []
        kind = (try? c.decode(TrackKind.self, forKey: .kind)) ?? .other
        zones = ((try? c.decode([Int].self, forKey: .zones)) ?? []).filter { (0..<10).contains($0) }
        course = try? c.decode(TrackCourse.self, forKey: .course)
    }

    /// Shot-map zones are in play: a shooting drill that names them.
    var onShotMap: Bool { kind.usesShotMap && !zones.isEmpty }
    var spotCount: Int { onShotMap ? zones.count : max(1, spots.count) }
    var attributes: [DrillAttribute] { skills.compactMap(DrillAttribute.init(rawValue:)) }
    /// The skills it mainly speaks for.
    var mainAttributes: [DrillAttribute] { attributes.filter { !some.contains($0.rawValue) } }

    /// How much a result says about a skill: 1 main, 0.5 some, 0 not linked.
    func weight(for axis: DrillAttribute) -> Double {
        guard skills.contains(axis.rawValue) else { return 0 }
        return some.contains(axis.rawValue) ? 0.5 : 1
    }

    /// The shot-map zone a spot's makes belong to (made-of only — a
    /// percentage needs attempts): a shooting drill's own zones, a
    /// finishing drill at the rim.
    func zone(forSpot i: Int) -> Int? {
        guard measure == .madeOf else { return nil }
        if onShotMap { return zones.indices.contains(i) ? zones[i] : nil }
        return kind == .finishing ? 0 : nil
    }

    /// Results compare only under the same measure, amount, spots, zones
    /// and course.
    var key: String {
        var k = "\(measure.rawValue)|\(measure == .madeOf || measure == .inTime ? amount : 0)|\(spotCount)"
        if onShotMap { k += "|z" + zones.map(String.init).joined(separator: ".") }
        if let course { k += "|" + course.rawValue }
        return k
    }

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
        if onShotMap, zones.indices.contains(i) { return Self.zoneShort[chinese ? 1 : 0][zones[i]] }
        return spots.indices.contains(i) ? spots[i] : (chinese ? "结果" : "Result")
    }

    /// The ten shot-map zones' short names (ShootingDrill.shotChart's order).
    static let zoneShort: [[String]] = [
        ["Rim", "L base", "L elbow", "R elbow", "R base", "L corner", "L wing", "Top", "R wing", "R corner"],
        ["篮下", "左底线", "左肘区", "右肘区", "右底线", "左底角", "左翼", "弧顶", "右翼", "右底角"],
    ]

    func unitWord(chinese: Bool) -> String {
        if !unit.trimmingCharacters(in: .whitespaces).isEmpty { return unit }
        return measure == .inTime ? (chinese ? "次" : "makes") : ""
    }

    /// "10 shots · 2 spots", "1 min · passes", "Time · lower is better".
    func summary(chinese: Bool) -> String {
        var parts: [String] = []
        switch measure {
        case .madeOf:
            if onShotMap {
                parts.append(chinese ? "每区 \(amount) 次" : "\(amount) shots a zone")
            } else {
                parts.append(chinese ? (spotCount > 1 ? "每点 \(amount) 次" : "\(amount) 次")
                                     : (spotCount > 1 ? "\(amount) a spot" : "\(amount) attempts"))
            }
        case .inTime:
            parts.append(ShootingSetup.time(amount, chinese: chinese) + (spotCount > 1 ? (chinese ? "／点" : " a spot") : ""))
            let w = unitWord(chinese: chinese); if !w.isEmpty { parts.append(w) }
        case .timeToFinish: parts.append(chinese ? "计时，越快越好" : "Timed, faster is better")
        case .count:
            let w = unitWord(chinese: chinese)
            parts.append(w.isEmpty ? (chinese ? "计数" : "Count") : w)
            parts.append(higherIsBetter ? (chinese ? "越多越好" : "higher is better") : (chinese ? "越少越好" : "lower is better"))
        }
        if let course { parts.append(course.short(chinese: chinese)) }
        if onShotMap {
            parts.append(chinese ? "\(zones.count) 个区域" : (zones.count == 1 ? spotName(0, chinese: false) : "\(zones.count) zones"))
        } else if spots.count > 1 {
            parts.append(spots.joined(separator: " / "))
        }
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
    /// to it as percentiles, weighted MAIN 1 / SOME 0.5, mapped onto 1–10
    /// (bottom 2, top 9 — no drill alone says "perfect"). Nil without a peer
    /// comparison, and nil when the links add up to less than one main drill
    /// (a single "some" link is a hint, not enough to move a rating).
    static func suggestion(for axis: DrillAttribute, standings: [Standing]) -> Int? {
        let linked = standings.compactMap { st -> (Double, Double)? in
            let w = st.definition.weight(for: axis)
            guard w > 0, let p = st.percentile else { return nil }
            return (p, w)
        }
        let total = linked.reduce(0) { $0 + $1.1 }
        guard total >= 1 else { return nil }
        let p = linked.reduce(0) { $0 + $1.0 * $1.1 } / total
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

// MARK: - From plain values (the Claude Desktop connector)

nonisolated extension TrackDefinition {
    struct ParseError: Error, Equatable { let message: String }

    /// A definition from a tool's `tracking` object: the kind's preset with
    /// what was sent on top. A bad field names itself; nothing is guessed.
    static func parsed(_ args: [String: Any], chinese: Bool) throws -> TrackDefinition {
        guard let kindRaw = args["kind"] as? String, let kind = TrackKind(rawValue: kindRaw) else {
            throw ParseError(message: "tracking.kind: " + TrackKind.allCases.map(\.rawValue).joined(separator: ", "))
        }
        var measure: TrackMeasure?
        if let raw = args["measure"] as? String {
            guard let m = TrackMeasure(rawValue: raw), kind.measures.contains(m) else {
                throw ParseError(message: "tracking.measure for \(kind.rawValue): " + kind.measures.map(\.rawValue).joined(separator: ", "))
            }
            measure = m
        }
        var d = kind.preset(measure: measure, chinese: chinese)
        if let n = args["amount"] as? Int {
            switch d.measure {
            case .madeOf: guard (1...100).contains(n) else { throw ParseError(message: "tracking.amount: 1–100 attempts") }
            case .inTime: guard (5...1200).contains(n) else { throw ParseError(message: "tracking.amount: 5–1200 seconds") }
            default: break
            }
            d.amount = n
        }
        if let unit = args["unit"] as? String { d.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let higher = args["higher_is_better"] as? Bool, d.measure == .count { d.higherIsBetter = higher }
        func axes(_ key: String) throws -> [String]? {
            guard let list = args[key] as? [String] else { return nil }
            for name in list where DrillAttribute(rawValue: name) == nil {
                throw ParseError(message: "tracking.\(key): \"\(name)\" is not a skill — " + DrillAttribute.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return list
        }
        let main = try axes("main"), some = try axes("some")
        if main != nil || some != nil {
            let s = (some ?? []).filter { !(main ?? []).contains($0) }
            d.skills = (main ?? []) + s
            d.some = s
        }
        if let sides = args["sides"] as? [String] {
            d.spots = sides.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if d.spots.count == 1 { d.spots = [] }
        }
        if let zones = args["zones"] as? [Int] {
            guard kind.usesShotMap else { throw ParseError(message: "tracking.zones: only a shooting drill has shot-map zones") }
            guard zones.allSatisfy({ (0..<10).contains($0) }), Set(zones).count == zones.count else {
                throw ParseError(message: "tracking.zones: distinct numbers 0–9 (0 rim, 1 left baseline, 2 left elbow, 3 right elbow, 4 right baseline, 5 left corner, 6 left wing, 7 top, 8 right wing, 9 right corner)")
            }
            d.zones = zones
            if !zones.isEmpty { d.spots = [] }
        }
        if let raw = args["course"] as? String {
            guard kind.usesCourse, let course = TrackCourse(rawValue: raw) else {
                throw ParseError(message: "tracking.course (conditioning and ballHandling only): " + TrackCourse.allCases.map(\.rawValue).joined(separator: ", "))
            }
            d.course = course
        }
        return d
    }

    /// The same shape back, for a tool's answer.
    var asValues: [String: Any] {
        var out: [String: Any] = ["kind": kind.rawValue, "measure": measure.rawValue,
                                  "main": mainAttributes.map(\.rawValue), "some": some,
                                  "summary": summary(chinese: false)]
        if measure == .madeOf || measure == .inTime { out["amount"] = amount }
        if !unit.isEmpty { out["unit"] = unit }
        if measure == .count { out["higher_is_better"] = higherIsBetter }
        if onShotMap { out["zones"] = zones } else if !spots.isEmpty { out["sides"] = spots }
        if let course { out["course"] = course.rawValue }
        return out
    }
}
