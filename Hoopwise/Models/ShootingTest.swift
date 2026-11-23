import Foundation

// TRACKED SHOOTING DRILLS (20 Nov 2026, Luther: "drills that are part of
// Hoopwise — if added to a session it appears as an add-on in the plan with a
// functioning mechanism … track the makes from each spot … any type of
// session … made vs miss or made in a set amount of time … add to athletes
// and make it part of the bigger picture student eval").
//
// Three built-in drills — 5-Spot Twos (short or mid range), Free Throws, and
// 5-Spot Threes. Scored either MADE OUT OF N shots a spot (a percentage) or
// MAKES IN N SECONDS a spot (makes per minute), one clock per spot. In groups
// the athletes self-report; the coach types one number per spot.
//
// Results live in the session's plan (SessionCurriculum.shooting — inside the
// curriculum JSON, no schema change). An athlete's history is read across
// sessions (ShootingHistory). Only LIKE WITH LIKE is compared: same drill,
// mode, amount and range (`ShootingSetup.key`).

enum ShootingDrill: String, Codable, CaseIterable, Identifiable {
    // Listed close to far (the library shows them in this order).
    case freeThrows, layups, mikan, twos, midRange, pullUps, dribbleShoot, threes, shotChart
    var id: String { rawValue }

    /// Where the makes are counted: five spots, a side each way, or one
    /// number.
    private var spots: [(en: String, zh: String, en2: String, zh2: String)] {
        switch self {
        case .twos, .threes:
            return [("Left corner", "左底角", "LC", "左底"), ("Left wing", "左侧翼", "LW", "左翼"),
                    ("Top", "弧顶", "Top", "弧顶"), ("Right wing", "右侧翼", "RW", "右翼"),
                    ("Right corner", "右底角", "RC", "右底")]
        case .layups: return [("Right hand", "右手", "R", "右"), ("Left hand", "左手", "L", "左")]
        case .pullUps: return [("Going right", "向右运球", "→", "右"), ("Going left", "向左运球", "←", "左")]
        case .freeThrows: return [("Line", "罚球线", "FT", "罚球")]
        case .midRange: return [("Mid-range", "中距离", "Mid", "中投")]
        case .mikan: return [("Under the rim", "篮下", "Rim", "篮下")]
        case .dribbleShoot: return [("Trips", "往返", "Made", "命中")]
        case .shotChart:
            // ShotZone order.
            return [("At the rim", "篮下", "Rim", "篮下"),
                    ("Left baseline mid-range", "左侧底线中投", "L base", "左底中"),
                    ("Left elbow mid-range", "左肘区中投", "L elbow", "左肘"),
                    ("Right elbow mid-range", "右肘区中投", "R elbow", "右肘"),
                    ("Right baseline mid-range", "右侧底线中投", "R base", "右底中"),
                    ("Left corner three", "左底角三分", "L corner 3", "左底三分"),
                    ("Left wing three", "左侧翼三分", "L wing 3", "左翼三分"),
                    ("Top three", "弧顶三分", "Top 3", "弧顶三分"),
                    ("Right wing three", "右侧翼三分", "R wing 3", "右翼三分"),
                    ("Right corner three", "右底角三分", "R corner 3", "右底三分")]
        }
    }

    var spotCount: Int { spots.count }

    /// Deterministic: every device seeds the same record.
    var drillId: UUID {
        let n: Int
        switch self {
        case .freeThrows: n = 1
        case .twos: n = 2
        case .threes: n = 3
        case .midRange: n = 4
        case .layups: n = 5
        case .mikan: n = 6
        case .pullUps: n = 7
        case .shotChart: n = 8
        case .dribbleShoot: n = 9
        }
        return UUID(uuidString: String(format: "5A0715F0-%04d-4000-8000-%012d", n, n))!
    }

    static let tagPrefix = "tracked:"
    var tag: String { Self.tagPrefix + rawValue }

    static func of(_ drill: DrillItem) -> ShootingDrill? {
        drill.tags.lazy.compactMap { tag -> ShootingDrill? in
            guard tag.hasPrefix(tagPrefix) else { return nil }
            return ShootingDrill(rawValue: String(tag.dropFirst(tagPrefix.count)))
        }.first
    }

    var englishName: String {
        switch self {
        case .twos: "5-Spot Twos"
        case .freeThrows: "Free Throws"
        case .threes: "5-Spot Threes"
        case .midRange: "Mid-Range Shooting"
        case .layups: "Lay-Ups Both Hands"
        case .mikan: "Mikan Drill"
        case .pullUps: "Pull-Up Jumpers"
        case .shotChart: "Shot Chart"
        case .dribbleShoot: "Dribble Out & Shoot"
        }
    }

    func title(chinese: Bool) -> String {
        guard chinese else { return englishName }
        switch self {
        case .twos: return "五点两分投篮"
        case .freeThrows: return "罚球"
        case .threes: return "五点三分投篮"
        case .midRange: return "中距离投篮"
        case .layups: return "左右手上篮"
        case .mikan: return "麦肯上篮"
        case .pullUps: return "急停跳投"
        case .shotChart: return "投篮热区图"
        case .dribbleShoot: return "运球折返投篮"
        }
    }

    func short(chinese: Bool) -> String {
        switch self {
        case .twos: chinese ? "两分" : "2PT"
        case .freeThrows: chinese ? "罚球" : "FT"
        case .threes: chinese ? "三分" : "3PT"
        case .midRange: chinese ? "中投" : "MID"
        case .layups: chinese ? "上篮" : "LAY"
        case .mikan: chinese ? "麦肯" : "MIKAN"
        case .pullUps: chinese ? "急停" : "PULL-UP"
        case .shotChart: chinese ? "热区" : "CHART"
        case .dribbleShoot: chinese ? "折返" : "DRIBBLE"
        }
    }

    /// SF Symbol for the drill's row and card.
    var symbol: String {
        switch self {
        case .freeThrows: "1.circle"
        case .layups: "arrow.up.forward.circle"
        case .mikan: "arrow.triangle.2.circlepath"
        case .twos: "2.circle"
        case .midRange: "scope"
        case .pullUps: "arrow.up.and.down.and.arrow.left.and.right"
        case .threes: "3.circle"
        case .shotChart: "circle.grid.cross"
        case .dribbleShoot: "arrow.uturn.backward.circle"
        }
    }

    private var texts: (en: String, zh: String) {
        let tail = (" Count the makes: out of a set number of shots, or within a set time. Results go to each athlete's shooting record.",
                    "记录命中数：固定出手数，或固定时间。计入每位学员的投篮记录。")
        switch self {
        case .twos:
            return ("Shoot from five spots inside the arc — left corner, left wing, top, right wing, right corner — at short or mid range, counting the makes at each spot." + tail.0,
                    "在三分线内的五个点投篮——左底角、左侧翼、弧顶、右侧翼、右底角，近距离或中距离，分别记录每个点的命中。" + tail.1)
        case .freeThrows:
            return ("Free throws from the line, with the same routine every shot." + tail.0,
                    "罚球线罚球，每一球用同样的投篮节奏。" + tail.1)
        case .threes:
            return ("Shoot from five spots behind the arc — left corner, left wing, top, right wing, right corner — counting the makes at each spot." + tail.0,
                    "在三分线外的五个点投篮——左底角、左侧翼、弧顶、右侧翼、右底角，分别记录每个点的命中。" + tail.1)
        case .midRange:
            return ("A partner rebounds and passes back; the shooter moves to a new spot between the paint and the arc after every shot — any mid-range spot counts. One total." + tail.0,
                    "同伴抢篮板并回传；投篮者每投一球换一个位置，油漆区外、三分线内的任何中距离位置都可以。记录总命中。" + tail.1)
        case .layups:
            return ("Lay-ups from the wing on both sides: right hand on the right, left hand on the left, off one or two dribbles. Counted per side." + tail.0,
                    "两侧侧翼运球上篮：右侧用右手，左侧用左手，一到两次运球。左右分别记录。" + tail.1)
        case .mikan:
            return ("The Mikan Drill: under the basket, alternate right-hand and left-hand lay-ups off the backboard, catching the ball before it touches the floor. Best timed." + tail.0,
                    "麦肯上篮：在篮下左右手交替打板上篮，球落地前接住。最适合计时。" + tail.1)
        case .dribbleShoot:
            return ("Dribble to half court (or the far baseline) and back, shoot, get your own rebound, and go again — shooting on tired legs, at game speed. Each athlete on their own ball." + tail.0,
                    "运球到半场（或对面底线）再运回来，投篮，自己抢篮板，再出发——在疲劳中以比赛速度投篮。每人一个球。" + tail.1)
        case .shotChart:
            return ("Free shooting across the floor, logged by zone: at the rim, four mid-range zones, five three-point zones. Enter made and attempted in each zone; the chart shows the percentage zone by zone. Results go to each athlete's shooting record and shot chart.",
                    "全场自由投篮，按区域记录：篮下、四个中距离区、五个三分区。每区输入命中和出手，热区图逐区显示命中率。计入每位学员的投篮记录和热区图。")
        case .pullUps:
            return ("One or two hard dribbles into a pull-up jump shot from mid-range, going right then going left. Counted each way." + tail.0,
                    "一到两次快速运球后急停跳投，中距离，先向右再向左。左右分别记录。" + tail.1)
        }
    }

    var englishDescription: String { texts.en }
    func description(chinese: Bool) -> String { chinese ? texts.zh : texts.en }

    /// The record the library seeds.
    var drillItem: DrillItem {
        let finishing = self == .layups || self == .mikan
        let attrs: [String] = self == .dribbleShoot
            ? ["attr:shooting=2", "attr:ballHandling=2", "attr:footwork=2"]
            : (finishing ? ["attr:finishing=3", "attr:shooting=1", "attr:ballHandling=1"]
               : ["attr:shooting=3", "attr:footwork=1"] + (self == .pullUps ? ["attr:ballHandling=2"] : []))
        return DrillItem(id: drillId, name: englishName, category: .shooting, difficulty: .beginner,
                         durationMinutes: self == .freeThrows || self == .mikan ? 5 : (self == .shotChart ? 15 : 10),
                         description: englishDescription, minPlayers: 1,
                         tags: [tag, "type:shooting", "kind:tracked"] + attrs,
                         createdAt: Date(timeIntervalSince1970: 1_795_000_000),
                         updatedAt: Date(timeIntervalSince1970: 1_795_000_000))
    }

    func spotName(_ index: Int, chinese: Bool) -> String {
        let s = spots[min(max(index, 0), spots.count - 1)]
        return chinese ? s.zh : s.en
    }

    func spotShort(_ index: Int, chinese: Bool) -> String {
        let s = spots[min(max(index, 0), spots.count - 1)]
        return chinese ? s.zh2 : s.en2
    }

    /// The first time it is added.
    var defaultSetup: ShootingSetup {
        switch self {
        case .mikan: ShootingSetup(drill: self, mode: .timed, shots: 10, seconds: 60)
        case .midRange: ShootingSetup(drill: self, mode: .attempts, shots: 20, seconds: 120)
        case .twos: ShootingSetup(drill: self, mode: .attempts, shots: 10, seconds: 30, range: .mid)
        case .threes: ShootingSetup(drill: self, mode: .attempts, shots: 10, seconds: 30)
        case .freeThrows: ShootingSetup(drill: self, mode: .attempts, shots: 10, seconds: 60)
        case .layups, .pullUps: ShootingSetup(drill: self, mode: .attempts, shots: 10, seconds: 30)
        case .shotChart: ShootingSetup(drill: self, mode: .chart, shots: 10, seconds: 60)
        case .dribbleShoot: ShootingSetup(drill: self, mode: .timed, shots: 10, seconds: 60, court: .half)
        }
    }
}

enum ShootingMode: String, Codable, CaseIterable {
    /// Made out of a number of shots a spot.
    case attempts
    /// Makes in a set time a spot.
    case timed
    /// Made AND attempted per zone (the shot chart: free shooting, a
    /// different number of shots in each zone).
    case chart

    /// A share of shots (attempts, chart) rather than makes a minute.
    var isShare: Bool { self != .timed }
}

enum TwosRange: String, Codable, CaseIterable {
    case short, mid
    func title(chinese: Bool) -> String {
        switch self {
        case .short: chinese ? "近距离" : "Short"
        case .mid: chinese ? "中距离" : "Mid"
        }
    }
}

/// How far the dribble goes before the shot (Dribble Out & Shoot).
enum CourtLength: String, Codable, CaseIterable {
    case half, full
    func title(chinese: Bool) -> String {
        switch self {
        case .half: chinese ? "半场折返" : "Half court"
        case .full: chinese ? "全场折返" : "Full court"
        }
    }
}

/// How the drill is scored this time — the comparison key.
struct ShootingSetup: Codable, Hashable {
    var drill: ShootingDrill
    var mode: ShootingMode
    /// Shots a spot (free throws: in all).
    var shots: Int = 10
    /// Seconds a spot (free throws: in all).
    var seconds: Int = 60
    /// Twos only.
    var range: TwosRange?
    /// Dribble Out & Shoot only: to half court or the far baseline.
    var court: CourtLength? = nil

    /// Same key = comparable results.
    var key: String {
        let amount: String
        switch mode {
        case .attempts: amount = "n\(shots)"
        case .timed: amount = "s\(seconds)"
        case .chart: amount = ""
        }
        return [drill.rawValue, mode.rawValue, amount, range?.rawValue ?? ""].joined(separator: "|")
            + (court.map { "|" + $0.rawValue } ?? "")
    }

    /// "10 shots a spot · mid" / "1 min a spot".
    func summary(chinese: Bool) -> String {
        let perSpot = drill.spotCount > 1
        let zone = drill == .shotChart
        var parts: [String] = []
        switch mode {
        case .chart:
            parts.append(chinese ? "每区命中 / 出手" : "made / attempted per zone")
        case .attempts:
            parts.append(chinese ? (perSpot ? (zone ? "每区 \(shots) 投" : "每点 \(shots) 投") : "\(shots) 投")
                                 : (perSpot ? "\(shots) shots a \(zone ? "zone" : "spot")" : "\(shots) shots"))
        case .timed:
            let t = Self.time(seconds, chinese: chinese)
            parts.append(chinese ? (perSpot ? "每点 \(t)" : t) : (perSpot ? "\(t) a spot" : t))
        }
        if let range, drill == .twos { parts.append(range.title(chinese: chinese)) }
        if let court, drill == .dribbleShoot { parts.append(court.title(chinese: chinese)) }
        return parts.joined(separator: " · ")
    }

    /// "45 s", "2 min", "1:30" (Chinese "1分30秒") — times now go to 20 min.
    static func time(_ seconds: Int, chinese: Bool) -> String {
        if seconds < 60 { return chinese ? "\(seconds) 秒" : "\(seconds) s" }
        if seconds % 60 == 0 { return chinese ? "\(seconds / 60) 分钟" : "\(seconds / 60) min" }
        return chinese ? "\(seconds / 60)分\(seconds % 60)秒" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The default the first time; afterwards the coach's last choice.
    static func remembered(_ drill: ShootingDrill) -> ShootingSetup {
        if let data = UserDefaults.standard.data(forKey: "shooting.setup.\(drill.rawValue)"),
           var saved = try? JSONDecoder().decode(ShootingSetup.self, from: data) {
            saved.drill = drill
            return saved
        }
        return drill.defaultSetup
    }

    func remember() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "shooting.setup.\(drill.rawValue)")
        }
    }
}

/// One athlete's makes, one number per spot (nil = not reported).
struct ShootingEntry: Codable, Hashable {
    var studentId: UUID
    var makes: [Int?]
    /// Chart mode: shots taken per zone (nil elsewhere; older entries
    /// decode without it).
    var attempts: [Int?]? = nil

    var reported: [Int] { makes.compactMap { $0 } }
    var isEmpty: Bool { reported.isEmpty && (attempts ?? []).compactMap { $0 }.isEmpty }
}

/// The drill as run in one session.
struct ShootingRun: Codable, Hashable, Identifiable {
    var id = UUID()
    var setup: ShootingSetup
    /// Round 1 (the only round until the coach runs the drill again).
    var entries: [ShootingEntry] = []
    /// ROUNDS (23 Nov 2026, Luther: "sometimes I run the same drill more
    /// than once … see how they improve within the session"): rounds 2…n,
    /// same setup. Written only when there is one. The pages edit ONE round
    /// (`round(_:)` — a run without `more`); everything else reads the
    /// session's result (`result(for:)`): made-of-shots POOLS every round,
    /// a timed result is the BEST round.
    var more: [[ShootingEntry]]? = nil

    var roundCount: Int { 1 + (more?.count ?? 0) }

    /// Round `i` (0-based) as a run of its own.
    func round(_ i: Int) -> ShootingRun {
        var r = self
        r.more = nil
        r.entries = i == 0 ? entries : (more.flatMap { $0.indices.contains(i - 1) ? $0[i - 1] : nil } ?? [])
        return r
    }

    var rounds: [ShootingRun] { (0..<roundCount).map(round) }

    mutating func setRound(_ i: Int, entries new: [ShootingEntry]) {
        if i == 0 { entries = new; return }
        var m = more ?? []
        while m.count < i { m.append([]) }
        m[i - 1] = new
        more = m
    }

    /// Opens a new, empty round and returns its index.
    @discardableResult mutating func addRound() -> Int {
        more = (more ?? []) + [[]]
        return roundCount - 1
    }

    /// Takes a round out (never the only one).
    mutating func removeRound(_ i: Int) {
        guard roundCount > 1, i < roundCount else { return }
        var all = [entries] + (more ?? [])
        all.remove(at: i)
        entries = all[0]
        more = all.count > 1 ? Array(all.dropFirst()) : nil
    }

    /// Rounds nobody logged in are dropped before saving (round 1 stays).
    mutating func dropEmptyRounds(keeping keep: Int? = nil) {
        guard let m = more else { return }
        let kept = m.enumerated().filter { !$0.element.isEmpty || $0.offset + 1 == keep }.map(\.element)
        more = kept.isEmpty ? nil : kept
    }

    var hasResults: Bool { !entries.isEmpty || (more ?? []).contains { !$0.isEmpty } }

    /// Everyone with a number in any round.
    var reporters: [UUID] {
        var seen = Set<UUID>(); var out: [UUID] = []
        for e in entries + (more ?? []).flatMap({ $0 }) where seen.insert(e.studentId).inserted { out.append(e.studentId) }
        return out
    }

    /// The athlete's entry: the round's own, or — with several rounds — the
    /// session's (shares pooled spot by spot, a timed drill's best round).
    func entry(for student: UUID) -> ShootingEntry? {
        guard more != nil else { return entries.first { $0.studentId == student } }
        let mine = rounds.compactMap { r -> (ShootingEntry, ShootingResult)? in
            guard let e = r.entries.first(where: { $0.studentId == student }) else { return nil }
            let res = ShootingResult(setup: setup, makes: e.makes, attempts: e.attempts)
            return res.spotsReported > 0 ? (e, res) : nil
        }
        guard !mine.isEmpty else { return nil }
        if !setup.mode.isShare { return mine.max { $0.1.value < $1.1.value }?.0 }
        let count = setup.drill.spotCount
        var makes = [Int?](repeating: nil, count: count), attempts = [Int?](repeating: nil, count: count)
        for (_, res) in mine {
            for spot in 0..<count {
                guard let s = res.shots(at: spot) else { continue }
                makes[spot] = (makes[spot] ?? 0) + s.made
                attempts[spot] = (attempts[spot] ?? 0) + s.attempted
            }
        }
        return ShootingEntry(studentId: student, makes: makes, attempts: attempts)
    }

    func makes(_ student: UUID, spot: Int) -> Int? {
        guard let e = entry(for: student), spot < e.makes.count else { return nil }
        return e.makes[spot]
    }

    mutating func set(_ value: Int?, for student: UUID, spot: Int) {
        let count = setup.drill.spotCount
        if let i = entries.firstIndex(where: { $0.studentId == student }) {
            if entries[i].makes.count < count { entries[i].makes += Array(repeating: nil, count: count - entries[i].makes.count) }
            entries[i].makes[spot] = value
            if entries[i].isEmpty { entries.remove(at: i) }
        } else if let value {
            var makes = [Int?](repeating: nil, count: count)
            makes[spot] = value
            entries.append(ShootingEntry(studentId: student, makes: makes))
        }
    }

    func attempts(_ student: UUID, spot: Int) -> Int? {
        guard let e = entry(for: student), let a = e.attempts, spot < a.count else { return nil }
        return a[spot]
    }

    /// Chart mode: shots taken in a zone.
    mutating func setAttempts(_ value: Int?, for student: UUID, spot: Int) {
        let count = setup.drill.spotCount
        if let i = entries.firstIndex(where: { $0.studentId == student }) {
            var a = entries[i].attempts ?? Array(repeating: nil, count: count)
            if a.count < count { a += Array(repeating: nil, count: count - a.count) }
            a[spot] = value
            entries[i].attempts = a
            if entries[i].isEmpty { entries.remove(at: i) }
        } else if let value {
            var a = [Int?](repeating: nil, count: count)
            a[spot] = value
            entries.append(ShootingEntry(studentId: student, makes: Array(repeating: nil, count: count), attempts: a))
        }
    }

    /// The athlete's result: a share (attempts, chart) or makes a minute
    /// (timed), over the spots reported.
    func result(for student: UUID) -> ShootingResult? {
        guard let e = entry(for: student) else { return nil }
        let r = ShootingResult(setup: setup, makes: e.makes, attempts: e.attempts)
        return r.spotsReported > 0 ? r : nil
    }
}

/// A result in comparable terms.
struct ShootingResult: Hashable {
    let setup: ShootingSetup
    let makes: [Int?]
    var attempts: [Int?]? = nil

    /// Made and attempted at a spot — nil when not reported (or, timed, never:
    /// a timed result has no attempts).
    func shots(at spot: Int) -> (made: Int, attempted: Int)? {
        guard spot < makes.count, let m = makes[spot] else { return nil }
        switch setup.mode {
        case .attempts:
            // Several rounds pooled carry their own total (see ShootingRun.entry).
            if let a = attempts, spot < a.count, let n = a[spot], n > 0 { return (min(m, n), n) }
            return (m, max(setup.shots, 1))
        case .chart:
            guard let a = attempts, spot < a.count, let n = a[spot], n > 0 else { return nil }
            return (min(m, n), n)
        case .timed: return nil
        }
    }

    private var reportedSpots: [Int] {
        (0..<makes.count).filter { spot in
            setup.mode == .timed ? makes[spot] != nil : shots(at: spot) != nil
        }
    }

    var made: Int { reportedSpots.compactMap { makes[$0] }.reduce(0, +) }
    var attempted: Int { reportedSpots.compactMap { shots(at: $0)?.attempted }.reduce(0, +) }
    var spotsReported: Int { reportedSpots.count }

    /// Attempts / chart: made ÷ shots (0…1). Timed: makes a minute.
    var value: Double {
        switch setup.mode {
        case .attempts, .chart: return Double(made) / Double(max(attempted, 1))
        case .timed: return Double(made) / (Double(max(setup.seconds, 1)) * Double(max(spotsReported, 1)) / 60)
        }
    }

    func spotValue(_ spot: Int) -> Double? {
        switch setup.mode {
        case .attempts, .chart:
            return shots(at: spot).map { Double($0.made) / Double($0.attempted) }
        case .timed:
            guard spot < makes.count, let m = makes[spot] else { return nil }
            return Double(m) / (Double(max(setup.seconds, 1)) / 60)
        }
    }

    /// "64%" / "4.5/min".
    static func text(_ value: Double, mode: ShootingMode, chinese: Bool) -> String {
        switch mode {
        case .attempts, .chart: return "\(Int((value * 100).rounded()))%"
        case .timed:
            let v = String(format: value < 10 ? "%.1f" : "%.0f", value)
            return chinese ? "每分钟 \(v) 中" : "\(v)/min"
        }
    }

    var text: String { Self.text(value, mode: setup.mode, chinese: LocalizationManager.shared.currentLanguage == .chinese) }

    /// "7/10" (made of shots) or "7 made" (timed).
    func madeText(chinese: Bool) -> String {
        switch setup.mode {
        case .attempts, .chart: return "\(made)/\(attempted)"
        case .timed: return chinese ? "进 \(made)" : "\(made) made"
        }
    }
}

extension DrillItem {
    var trackedShooting: ShootingDrill? { ShootingDrill.of(self) }
}
