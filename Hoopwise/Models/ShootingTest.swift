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
    case twos, freeThrows, threes
    var id: String { rawValue }

    /// Five spots — corners, wings, top — or one line for free throws.
    var spotCount: Int { self == .freeThrows ? 1 : 5 }

    /// Deterministic: every device seeds the same record.
    var drillId: UUID {
        switch self {
        case .twos: UUID(uuidString: "5A0715F0-0002-4000-8000-000000000002")!
        case .freeThrows: UUID(uuidString: "5A0715F0-0001-4000-8000-000000000001")!
        case .threes: UUID(uuidString: "5A0715F0-0003-4000-8000-000000000003")!
        }
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
        }
    }

    func title(chinese: Bool) -> String {
        guard chinese else { return englishName }
        switch self {
        case .twos: return "五点两分投篮"
        case .freeThrows: return "罚球"
        case .threes: return "五点三分投篮"
        }
    }

    func short(chinese: Bool) -> String {
        switch self {
        case .twos: chinese ? "两分" : "2PT"
        case .freeThrows: chinese ? "罚球" : "FT"
        case .threes: chinese ? "三分" : "3PT"
        }
    }

    var englishDescription: String {
        switch self {
        case .twos:
            "Shoot from five spots inside the arc — left corner, left wing, top, right wing, right corner — at short or mid range. Count the makes at each spot: out of a set number of shots, or within a set time. Tracked: results go to each athlete's shooting record."
        case .freeThrows:
            "Free throws from the line. Count the makes: out of a set number of shots, or within a set time. Tracked: results go to each athlete's shooting record."
        case .threes:
            "Shoot from five spots behind the arc — left corner, left wing, top, right wing, right corner. Count the makes at each spot: out of a set number of shots, or within a set time. Tracked: results go to each athlete's shooting record."
        }
    }

    func description(chinese: Bool) -> String {
        guard chinese else { return englishDescription }
        switch self {
        case .twos: return "在三分线内的五个点投篮——左底角、左侧翼、弧顶、右侧翼、右底角，近距离或中距离。记录每个点的命中数：固定出手数，或固定时间。计入每位学员的投篮记录。"
        case .freeThrows: return "罚球线罚球。记录命中数：固定出手数，或固定时间。计入每位学员的投篮记录。"
        case .threes: return "在三分线外的五个点投篮——左底角、左侧翼、弧顶、右侧翼、右底角。记录每个点的命中数：固定出手数，或固定时间。计入每位学员的投篮记录。"
        }
    }

    /// The record the library seeds.
    var drillItem: DrillItem {
        DrillItem(id: drillId, name: englishName, category: .shooting, difficulty: .beginner,
                  durationMinutes: self == .freeThrows ? 5 : 10,
                  description: englishDescription, minPlayers: 1,
                  tags: [tag, "type:shooting", "kind:tracked",
                         "attr:shooting=3", "attr:footwork=1"],
                  createdAt: Date(timeIntervalSince1970: 1_795_000_000),
                  updatedAt: Date(timeIntervalSince1970: 1_795_000_000))
    }

    /// Spot names, left to right.
    func spotName(_ index: Int, chinese: Bool) -> String {
        guard self != .freeThrows else { return chinese ? "罚球线" : "Line" }
        let en = ["Left corner", "Left wing", "Top", "Right wing", "Right corner"]
        let zh = ["左底角", "左侧翼", "弧顶", "右侧翼", "右底角"]
        return (chinese ? zh : en)[min(max(index, 0), 4)]
    }

    func spotShort(_ index: Int, chinese: Bool) -> String {
        guard self != .freeThrows else { return chinese ? "罚球" : "FT" }
        let en = ["LC", "LW", "Top", "RW", "RC"]
        let zh = ["左底", "左翼", "弧顶", "右翼", "右底"]
        return (chinese ? zh : en)[min(max(index, 0), 4)]
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
        return ShootingSetup(drill: drill, mode: .attempts, shots: 10,
                             seconds: drill == .freeThrows ? 60 : 30,
                             range: drill == .twos ? .mid : nil)
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
