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
    case freeThrows, layups, mikan, twos, midRange, pullUps, threes
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
        return DrillItem(id: drillId, name: englishName, category: .shooting, difficulty: .beginner,
                         durationMinutes: self == .freeThrows || self == .mikan ? 5 : 10,
                         description: englishDescription, minPlayers: 1,
                         tags: [tag, "type:shooting", "kind:tracked"]
                            + (finishing ? ["attr:finishing=3", "attr:shooting=1", "attr:ballHandling=1"]
                               : ["attr:shooting=3", "attr:footwork=1"]
                                 + (self == .pullUps ? ["attr:ballHandling=2"] : [])),
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
        }
    }
}

enum ShootingMode: String, Codable, CaseIterable {
    /// Made out of a number of shots a spot.
    case attempts
    /// Makes in a set time a spot.
    case timed
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

    /// Same key = comparable results.
    var key: String {
        let amount = mode == .attempts ? "n\(shots)" : "s\(seconds)"
        return [drill.rawValue, mode.rawValue, amount, range?.rawValue ?? ""].joined(separator: "|")
    }

    /// "10 shots a spot · mid" / "1 min a spot".
    func summary(chinese: Bool) -> String {
        let perSpot = drill.spotCount > 1
        var parts: [String] = []
        switch mode {
        case .attempts:
            parts.append(chinese ? (perSpot ? "每点 \(shots) 投" : "\(shots) 投") : (perSpot ? "\(shots) shots a spot" : "\(shots) shots"))
        case .timed:
            let t = Self.time(seconds, chinese: chinese)
            parts.append(chinese ? (perSpot ? "每点 \(t)" : t) : (perSpot ? "\(t) a spot" : t))
        }
        if let range, drill == .twos { parts.append(range.title(chinese: chinese)) }
        return parts.joined(separator: " · ")
    }

    static func time(_ seconds: Int, chinese: Bool) -> String {
        if seconds % 60 == 0 { return chinese ? "\(seconds / 60) 分钟" : "\(seconds / 60) min" }
        return chinese ? "\(seconds) 秒" : "\(seconds) s"
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

    var reported: [Int] { makes.compactMap { $0 } }
    var isEmpty: Bool { reported.isEmpty }
}

/// The drill as run in one session.
struct ShootingRun: Codable, Hashable, Identifiable {
    var id = UUID()
    var setup: ShootingSetup
    var entries: [ShootingEntry] = []

    func entry(for student: UUID) -> ShootingEntry? { entries.first { $0.studentId == student } }

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

    /// The athlete's result: a share (attempts) or makes a minute (timed),
    /// over the spots reported.
    func result(for student: UUID) -> ShootingResult? {
        guard let e = entry(for: student), !e.isEmpty else { return nil }
        return ShootingResult(setup: setup, makes: e.makes)
    }
}

/// A result in comparable terms.
struct ShootingResult: Hashable {
    let setup: ShootingSetup
    let makes: [Int?]

    var made: Int { makes.compactMap { $0 }.reduce(0, +) }
    var spotsReported: Int { makes.compactMap { $0 }.count }

    /// Attempts: made ÷ shots (0…1). Timed: makes a minute.
    var value: Double {
        let n = Double(max(spotsReported, 1))
        switch setup.mode {
        case .attempts: return Double(made) / (Double(max(setup.shots, 1)) * n)
        case .timed: return Double(made) / (Double(max(setup.seconds, 1)) * n / 60)
        }
    }

    func spotValue(_ spot: Int) -> Double? {
        guard spot < makes.count, let m = makes[spot] else { return nil }
        switch setup.mode {
        case .attempts: return Double(m) / Double(max(setup.shots, 1))
        case .timed: return Double(m) / (Double(max(setup.seconds, 1)) / 60)
        }
    }

    /// "64%" / "7/10" / "4.5 a min".
    static func text(_ value: Double, mode: ShootingMode, chinese: Bool) -> String {
        switch mode {
        case .attempts: return "\(Int((value * 100).rounded()))%"
        case .timed:
            let v = String(format: value < 10 ? "%.1f" : "%.0f", value)
            return chinese ? "每分钟 \(v) 中" : "\(v)/min"
        }
    }

    var text: String { Self.text(value, mode: setup.mode, chinese: LocalizationManager.shared.currentLanguage == .chinese) }

    /// "7/10" (attempts) or "7 made" (timed).
    func madeText(chinese: Bool) -> String {
        switch setup.mode {
        case .attempts: return "\(made)/\(setup.shots * max(spotsReported, 1))"
        case .timed: return chinese ? "进 \(made)" : "\(made) made"
        }
    }
}

extension DrillItem {
    var trackedShooting: ShootingDrill? { ShootingDrill.of(self) }
}
