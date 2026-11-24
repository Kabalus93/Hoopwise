import Foundation

// THE PROGRESS REPORT (25 Nov 2026, Luther, after the audit: parents got
// snapshots — the card, a shot chart — and nothing that shows CHANGE over a
// term). Everything one page prints about one athlete over a period, as plain
// values. NOTHING INVENTED: a part without data is empty and its section is
// left out. Ratings then = the evaluation in force when the period began (or
// the first one made in it); now = the current one.

struct ProgressReportFacts {
    struct Skill: Identifiable { let axis: DrillAttribute; let title: String; let then: Int?; let now: Int
        var id: String { axis.rawValue }; var change: Int? { then.map { now - $0 } } }
    struct Result: Identifiable { let id: String; let title: String; let first: String?; let last: String; let improved: Bool? }

    var name = ""
    var secondName: String?
    var schoolGrade: String?
    var program: String?
    var accentHex = "#007AFF"
    var periodStart = Date()
    var periodEnd = Date()
    var classesPresent = 0
    var classesTaken = 0
    var games = 0
    /// Points, rebounds, assists a game over the period's games.
    var perGame: [(label: String, value: Double)] = []
    var playerOfTheSession = 0
    var skills: [Skill] = []
    var skillsSince: Date?
    /// The skills their classes spent most time on, most first.
    var workedOn: [String] = []
    var results: [Result] = []
    var focus: [String] = []
    var coachWords = ""
    var coach = ""
    var academy = ""
    var chinese = false

    var attendanceShare: Double? { classesTaken > 0 ? Double(classesPresent) / Double(classesTaken) : nil }

    static func make(student: Student, players: [Player], programs: [Program], sessions: [SessionEvent],
                     drills: [DrillItem], from start: Date, to end: Date = Date(),
                     coachWords: String = "", focus: [DrillAttribute]? = nil,
                     coach: String, academy: String, chinese: Bool) -> ProgressReportFacts {
        var f = ProgressReportFacts()
        f.chinese = chinese
        f.name = student.primaryName(chinese: chinese)
        f.secondName = student.secondaryName(chinese: chinese)
        f.schoolGrade = student.currentSchoolGrade(asOf: end)?.shortName(chinese: chinese)
        let program = student.programId.flatMap { id in programs.first { $0.id == id } }
            ?? programs.first { $0.enrolledStudentIds.contains(student.id) }
        f.program = program.map { $0.name.isEmpty ? $0.resolvedDisplayName(in: programs) : $0.name }
        if let hex = program?.colorHex { f.accentHex = hex }
        f.periodStart = start; f.periodEnd = end
        f.coach = coach; f.academy = academy
        f.coachWords = coachWords.trimmingCharacters(in: .whitespacesAndNewlines)

        let period = start...max(start, end)
        let happened = sessions.filter { !SessionLifecycle.didNotHappen($0) && period.contains($0.startTime) }
        // Attendance: classes where their mark was taken; unmarked is not absent.
        let marked = happened.filter { s in
            s.actualAttendeeIds.contains(student.id) || s.excusedAbsences.contains(student.id)
                || s.unexcusedAbsences.contains(student.id)
        }
        let attended = happened.filter { $0.actualAttendeeIds.contains(student.id) }
        f.classesTaken = marked.count
        f.classesPresent = attended.count
        f.playerOfTheSession = happened.filter { $0.manOfTheMatchId == student.id }.count

        // Games in the period.
        let lines = GameStatsReport.playerGames(student.id, in: sessions, in: period)
        f.games = lines.count
        if !lines.isEmpty {
            let n = Double(lines.count)
            f.perGame = [
                (chinese ? "得分" : "Points", Double(lines.reduce(0) { $0 + $1.line.points }) / n),
                (chinese ? "篮板" : "Rebounds", Double(lines.reduce(0) { $0 + $1.line.rebounds }) / n),
                (chinese ? "助攻" : "Assists", Double(lines.reduce(0) { $0 + $1.line.assists }) / n),
            ]
        }

        // Skills then and now.
        if let skills = players.first(where: { $0.studentId == student.id })?.skills, skills.isEvaluated {
            let before = skills.history.last { $0.date <= start }
            let firstIn = skills.history.first { $0.date > start && $0.date <= end }
            let then = before ?? firstIn
            // "Then" must be an earlier evaluation than the current one.
            let usable = then.flatMap { snap in snap == skills.history.last ? nil : snap }
            f.skillsSince = usable?.date
            f.skills = DrillAttribute.allCases.compactMap { axis in
                guard let now = skills.rating(axis) else { return nil }
                return Skill(axis: axis, title: axis.title(chinese: chinese), then: usable?.axes[axis.rawValue], now: now)
            }
            let chosen = focus ?? AthleteFocus.current(skills)
            f.focus = chosen.map { $0.title(chinese: chinese) }
        } else if let focus {
            f.focus = focus.map { $0.title(chinese: chinese) }
        }

        // What the classes they were at worked on.
        var total: [DrillAttribute: Double] = [:]
        for session in attended {
            for (axis, value) in PlanCoverage.minutes(of: session.curriculum, drills: drills) { total[axis, default: 0] += value }
        }
        let shares = PlanCoverage.normalized(total)
        f.workedOn = DrillAttribute.allCases.filter { (shares[$0] ?? 0) >= 0.5 }
            .sorted { (shares[$0] ?? 0) > (shares[$1] ?? 0) }.prefix(4).map { $0.title(chinese: chinese) }

        // Tracked results: first and latest in the period, per comparable setup.
        var results: [(count: Int, result: Result)] = []
        for series in ShootingHistory.series(for: student.id, sessions: sessions) {
            let points = series.points.filter { period.contains($0.date) }
            guard let last = points.last else { continue }
            let first = points.count >= 2 ? points.first : nil
            let text = { (v: Double) in ShootingResult.text(v, mode: series.setup.mode, chinese: chinese) }
            results.append((points.count, Result(
                id: "s:" + series.setup.key,
                title: series.setup.drill.title(chinese: chinese) + " · " + series.setup.summary(chinese: chinese),
                first: first.map { text($0.value) }, last: text(last.value),
                improved: first.flatMap { abs(last.value - $0.value) < 0.0001 ? nil : last.value > $0.value })))
        }
        var seen = Set<String>()
        for session in happened {
            for run in session.curriculum.tracked where run.result(for: student.id) != nil {
                let id = run.drillId.uuidString + "|" + run.definition.key
                guard seen.insert(id).inserted else { continue }
                let points = CustomTrackHistory.series(student.id, drillId: run.drillId, key: run.definition.key, sessions: sessions)
                    .filter { period.contains($0.date) }
                guard let last = points.last else { continue }
                let first = points.count >= 2 ? points.first : nil
                let def = run.definition
                let name = drills.first { $0.id == run.drillId }?.localizedName ?? (chinese ? "追踪训练" : "Tracked drill")
                results.append((points.count, Result(
                    id: "t:" + id, title: name,
                    first: first.map { def.text($0.value, chinese: chinese) }, last: def.text(last.value, chinese: chinese),
                    improved: first.flatMap { f in
                        abs(last.value - f.value) < 0.0001 ? nil : (def.lowerIsBetter ? last.value < f.value : last.value > f.value)
                    })))
            }
        }
        f.results = results.sorted { $0.count > $1.count }.prefix(6).map(\.result)
        return f
    }

    var fileStem: String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return ("Progress_" + name).components(separatedBy: bad).joined().replacingOccurrences(of: " ", with: "_")
    }
}

/// What ONE athlete is working on (25 Nov 2026): one or two of the eight
/// skills. The coach's pick is stored with the evaluation
/// (`SkillsEvaluation.focus`); until one is made the app suggests the
/// lowest-rated skills.
nonisolated enum AthleteFocus {
    static let most = 2

    /// The two lowest-rated skills (octagon order breaks ties) — only once
    /// at least four skills are rated, and never a skill rated 8 or more.
    static func suggested(_ skills: SkillsEvaluation) -> [DrillAttribute] {
        let rated = DrillAttribute.allCases.compactMap { axis in skills.rating(axis).map { (axis, $0) } }
        guard rated.count >= 4 else { return [] }
        return rated.enumerated().sorted { a, b in
            a.element.1 != b.element.1 ? a.element.1 < b.element.1 : a.offset < b.offset
        }.prefix(most).filter { $0.element.1 < 8 }.map { $0.element.0 }
    }

    /// The coach's pick, else the suggestion.
    static func current(_ skills: SkillsEvaluation) -> [DrillAttribute] {
        let picked = skills.focus.compactMap(DrillAttribute.init(rawValue:))
        return picked.isEmpty ? suggested(skills) : Array(picked.prefix(most))
    }
}

extension SwiftDataManager {
    /// What the athlete is working on now (the coach's pick, else the
    /// suggestion) — empty until they are evaluated or a focus is picked.
    func athleteFocus(_ studentId: UUID) -> [DrillAttribute] {
        guard let skills = players.first(where: { $0.studentId == studentId })?.skills else { return [] }
        return AthleteFocus.current(skills)
    }

    /// The coach picks the focus (empty = back to the suggestion). Not an
    /// evaluation: the ratings and their history are untouched.
    func setAthleteFocus(_ focus: [DrillAttribute], for studentId: UUID) {
        guard var player = players.first(where: { $0.studentId == studentId }) else { return }
        player.skills.focus = Array(focus.prefix(AthleteFocus.most)).map(\.rawValue)
        player.updatedAt = Date()
        updatePlayer(player)
    }
}
