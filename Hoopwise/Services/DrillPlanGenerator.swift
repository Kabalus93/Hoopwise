import Foundation

// MARK: - Drill Plan Generator (October 2026 rewrite, Luther)
//
// Deterministic scoring + light sampling, on-device, no network. Builds a
// session plan from the ACTIVITY LIBRARY (plus the coach's own drills) and is
// explicit about what it read:
//
//  • AGE — the program's age group, mapped onto the library's ages.
//  • LEVEL — 1…5. The coach's slider on the program page wins; without it,
//    the players' evaluations suggest one, but only when at least half the
//    roster has been rated (otherwise level 3). The level moves the AGE
//    WINDOW: 3 = this age (earlier ages allowed — each library age builds on
//    the ones before it), 4–5 borrow from older ages, 1–2 lean on younger.
//  • FOCUS — the phase's training focus, the roster's weakest evaluated area,
//    and (with enough games) a passing signal from game stats.
//  • HISTORY — every earlier plan of this program. Nothing from the last
//    session repeats; activities seen before come back as REVIEW; the rest is
//    NEW. A phase's first sessions lean new; later ones lean review.
//
// Slots follow the library's blocks: warm-up ← Block 1 (routine, then a small
// game), skills ← Block 2 (one idea, then compete), game ← Block 3. Rule
// options are never planned. `PlanRationale` says what was decided and why,
// so the coach can see the data behind the plan.

struct DrillPlanGenerator {

    // MARK: - Public API

    struct Context {
        let session: SessionEvent
        let program: Program?
        let phase: MicroCycle?
        let enrolledStudents: [Student]
        let players: [Player]               // evaluations (Player.skills)
        let allDrills: [DrillItem]
        /// Every earlier session of this program (any order).
        let programHistory: [SessionEvent]
    }

    enum LevelSource: Equatable {
        case coach                                  // the program-page slider
        case evaluations(rated: Int, of: Int, average: Double)
        case standard                               // not enough data
    }

    /// What the generator decided, in words the coach can check.
    struct PlanRationale: Equatable {
        var age: ActivityAge
        var level: Int
        var levelSource: LevelSource
        var ageWindow: [ActivityAge]
        var focus: [ActivityType]
        var reviewCount = 0
        var newCount = 0
        var notes: [String] = []
    }

    static func generate(in ctx: Context) -> SessionCurriculum { generatePlan(in: ctx).curriculum }

    static func generatePlan(in ctx: Context,
                             random: () -> Double = { Double.random(in: 0..<1) })
        -> (curriculum: SessionCurriculum, rationale: PlanRationale) {
        var cur = ctx.session.curriculum
        // A session made by the cycle planner can arrive with no block minutes
        // at all: share its length out evenly over the three blocks.
        if cur.warmupMinutes + cur.skillsMinutes + cur.gameMinutes == 0 {
            let total = max(30, Int(ctx.session.endTime.timeIntervalSince(ctx.session.startTime) / 60))
            cur.warmupMinutes = total / 3
            cur.skillsMinutes = total / 3
            cur.gameMinutes = total - 2 * (total / 3)
        }
        let warmupBudget = max(5, cur.warmupMinutes)
        let skillsBudget = max(5, cur.skillsMinutes)
        let gameBudget = max(0, cur.gameMinutes)

        let age = libraryAge(for: ctx.program?.ageGroup)
        let (level, source) = resolveLevel(program: ctx.program, students: ctx.enrolledStudents, players: ctx.players)
        let window = ageWeights(age: age, level: level)
        let focus = focusTypes(phase: ctx.phase, students: ctx.enrolledStudents, players: ctx.players,
                               games: ctx.programHistory.flatMap(\.games))
        let history = History(sessions: ctx.programHistory, before: ctx.session)
        let reviewShare = history.reviewShare(phase: ctx.phase, session: ctx.session)

        var rationale = PlanRationale(age: age, level: level, levelSource: source,
                                      ageWindow: ActivityAge.allCases.filter { window[$0] != nil },
                                      focus: focus.types)
        rationale.notes = focus.notes

        let candidates = candidates(drills: ctx.allDrills, window: window, age: age)
        var used: Set<UUID> = []
        func fill(_ slot: Slot, _ budget: Int) -> [UUID] {
            let picks = pick(slot: slot, budget: budget, candidates: candidates, focus: Set(focus.types),
                             history: history, reviewShare: reviewShare, exclude: used, random: random)
            used.formUnion(picks.map(\.id))
            for p in picks { if history.count(p.id) > 0 { rationale.reviewCount += 1 } else { rationale.newCount += 1 } }
            return picks.map(\.id)
        }
        let warmup = fill(.warmup, warmupBudget)
        let skills = fill(.skills, skillsBudget)
        let game = fill(.game, gameBudget)

        let curriculum = SessionCurriculum(
            warmupDrillIds: warmup, skillDrillIds: skills, gameDrillIds: game,
            warmupMinutes: warmupBudget, skillsMinutes: skillsBudget, gameMinutes: gameBudget,
            notes: cur.notes)
        return (curriculum, rationale)
    }

    // MARK: - Age and level

    static func libraryAge(for group: AgeGroup?) -> ActivityAge {
        switch group {
        case .u6: return .u6
        case .u8: return .u8
        case .u10: return .u10
        case .u12, nil: return .u12
        case .u14: return .u14
        case .u16, .u18, .adult: return .u16
        }
    }

    /// The level and where it came from. Coach's slider → evaluations (only
    /// with at least half the roster rated) → 3.
    static func resolveLevel(program: Program?, students: [Student], players: [Player]) -> (Int, LevelSource) {
        if let set = program?.skillTargets?.level, (1...5).contains(set) { return (set, .coach) }
        if let suggestion = suggestedLevel(students: students, players: players) {
            return (suggestion.level, .evaluations(rated: suggestion.rated, of: students.count, average: suggestion.average))
        }
        return (3, .standard)
    }

    /// What the evaluations say, or nil when too few players are rated to
    /// trust it. A player counts as rated once any skill differs from the
    /// untouched default of 5 across the board.
    static func suggestedLevel(students: [Student], players: [Player])
        -> (level: Int, rated: Int, average: Double)? {
        let byStudent = Dictionary(players.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
        let ratings = students.compactMap { byStudent[$0.id] }.filter(isRated).map(\.skills.overallRating)
        guard !students.isEmpty, ratings.count * 2 >= students.count else { return nil }
        let average = ratings.reduce(0, +) / Double(ratings.count)
        let level: Int
        switch average {
        case ..<3.5: level = 1
        case ..<4.5: level = 2
        case ..<6.5: level = 3
        case ..<8.0: level = 4
        default: level = 5
        }
        return (level, ratings.count, average)
    }

    private static func isRated(_ player: Player) -> Bool {
        let s = player.skills
        return [s.scoring, s.playmaking, s.rebounding, s.defense, s.athleticism, s.intangibles] != [5, 5, 5, 5, 5, 5]
    }

    /// Which library ages a plan may draw from, with a weight each.
    static func ageWeights(age: ActivityAge, level: Int) -> [ActivityAge: Double] {
        let all = ActivityAge.allCases
        let i = all.firstIndex(of: age)!
        func at(_ offset: Int) -> ActivityAge? {
            let j = i + offset
            return all.indices.contains(j) ? all[j] : nil
        }
        var w: [ActivityAge: Double] = [:]
        func put(_ a: ActivityAge?, _ v: Double) { if let a { w[a] = max(w[a] ?? 0, v) } }
        switch level {
        case 1: put(at(-1), 1.0); put(at(-2), 0.7); put(age, 0.6)
        case 2: put(age, 1.0); put(at(-1), 0.8)
        case 4: put(age, 1.0); put(at(1), 0.8); put(at(-1), 0.3)
        case 5: put(at(1), 1.0); put(age, 0.6); put(at(2), 0.5)
        default: put(age, 1.0); put(at(-1), 0.4)
        }
        if w.isEmpty { w[age] = 1 }
        return w
    }

    // MARK: - Focus

    private static func focusTypes(phase: MicroCycle?, students: [Student], players: [Player],
                                   games: [SessionGame] = [])
        -> (types: [ActivityType], notes: [String]) {
        var types: [ActivityType] = []
        var notes: [String] = []
        for f in phase?.focus ?? [] { types += map(f) }

        // The roster's weakest evaluated area, when evaluations exist and
        // actually differ between areas.
        let byStudent = Dictionary(players.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
        let rated = students.compactMap { byStudent[$0.id] }.filter(isRated)
        if !rated.isEmpty {
            func avg(_ k: KeyPath<SkillsEvaluation, Int>) -> Double {
                Double(rated.map { $0.skills[keyPath: k] }.reduce(0, +)) / Double(rated.count)
            }
            let areas: [(String, Double, [ActivityType])] = [
                ("scoring", avg(\.scoring), [.shooting, .layups]),
                ("playmaking", avg(\.playmaking), [.dribbling, .passing]),
                ("rebounding", avg(\.rebounding), [.rebounding]),
                ("defense", avg(\.defense), [.defence, .oneOnOne]),
                ("athleticism", avg(\.athleticism), [.warmup, .ballMovement]),
                ("intangibles", avg(\.intangibles), [.teamPlay, .games])]
            let sorted = areas.sorted { $0.1 < $1.1 }
            if let low = sorted.first, let high = sorted.last, high.1 - low.1 >= 1 {
                types += low.2
                notes.append("weakest:\(low.0)")
            }
        }
        // Performance: with at least 3 recorded games, few assists per basket
        // means the ball sticks — push passing and team play.
        if let signal = passingSignal(games: games, roster: Set(students.map(\.id))) {
            types += [.passing, .teamPlay]
            notes.append(signal)
        }

        var seen = Set<ActivityType>()
        return (types.filter { seen.insert($0).inserted }, notes)
    }

    /// The emphasis the DATA asks for — weakest evaluated area, and passing
    /// when game stats show few assists. No phase input.
    static func dataFocus(students: [Student], players: [Player], games: [SessionGame]) -> [ActivityType] {
        focusTypes(phase: nil, students: students, players: players, games: games).types
    }

    /// "assists:<ratio>" when the roster's games show under one assist per
    /// five baskets; nil without enough games or points to say.
    static func passingSignal(games: [SessionGame], roster: Set<UUID>) -> String? {
        let played = games.filter { g in g.playerStats.contains { roster.contains($0.playerId) } }
        guard played.count >= 3 else { return nil }
        let stats = played.flatMap(\.playerStats).filter { roster.contains($0.playerId) }
        let points = stats.reduce(0) { $0 + $1.points }, assists = stats.reduce(0) { $0 + $1.assists }
        let baskets = Double(points) / 2
        guard baskets >= 10 else { return nil }
        let ratio = Double(assists) / baskets
        return ratio < 0.2 ? "assists:\(String(format: "%.2f", ratio))" : nil
    }

    private static func map(_ f: TrainingFocus) -> [ActivityType] {
        switch f {
        case .shooting: return [.shooting, .layups]
        case .ballHandling: return [.dribbling, .ballMovement]
        case .passing: return [.passing, .teamPlay]
        case .defense: return [.defence, .oneOnOne]
        case .conditioning: return [.warmup]
        case .teamPlay: return [.teamPlay, .games]
        case .gamePrep: return [.games]
        case .recovery: return [.warmup]
        }
    }

    // MARK: - History

    struct History {
        private var counts: [UUID: Int] = [:]
        private(set) var lastSession: Set<UUID> = []
        let pastSessionsInPhase: Int
        let isEmpty: Bool

        init(sessions: [SessionEvent], before session: SessionEvent) {
            let past = sessions
                .filter { $0.id != session.id && $0.startTime < session.startTime && !SessionLifecycle.didNotHappen($0) }
                .sorted { $0.startTime < $1.startTime }
            for s in past {
                for id in s.curriculum.warmupDrillIds + s.curriculum.skillDrillIds + s.curriculum.gameDrillIds {
                    counts[id, default: 0] += 1
                }
            }
            if let last = past.last(where: { $0.curriculum.totalDrillCount > 0 }) {
                lastSession = Set(last.curriculum.warmupDrillIds + last.curriculum.skillDrillIds + last.curriculum.gameDrillIds)
            }
            pastSessionsInPhase = past.filter { $0.microCycleId != nil && $0.microCycleId == session.microCycleId }.count
            isEmpty = counts.isEmpty
        }

        func count(_ id: UUID) -> Int { counts[id] ?? 0 }

        /// Share of a slot that should be REVIEW. No history → all new. A
        /// phase's first two sessions introduce (30% review); after that the
        /// plan consolidates (60% review).
        func reviewShare(phase: MicroCycle?, session: SessionEvent) -> Double {
            if isEmpty { return 0 }
            return pastSessionsInPhase < 2 ? 0.3 : 0.6
        }
    }

    // MARK: - Candidates and picking

    enum Slot { case warmup, skills, game }

    struct Candidate {
        let id: UUID
        let minutes: Int
        let block: ActivityBlock?            // nil = a coach's own drill
        let type: ActivityType?
        let category: DrillCategory
        let ageWeight: Double
        let isFavorite: Bool
    }

    private static func candidates(drills: [DrillItem], window: [ActivityAge: Double], age: ActivityAge) -> [Candidate] {
        drills.compactMap { drill in
            if let a = drill.libraryActivity {
                guard !a.isRule, let w = window[a.age] else { return nil }
                return Candidate(id: drill.id, minutes: drill.durationMinutes, block: a.block, type: a.type,
                                 category: drill.category, ageWeight: w, isFavorite: drill.isFavorite)
            }
            // A coach's own drill: eligible when untagged or tagged for this age.
            let profile = DrillProfile(drill)
            let fits = profile.ageGroups.isEmpty
                || profile.ageGroups.contains { libraryAge(for: $0) == age || window[libraryAge(for: $0)] != nil }
            guard fits else { return nil }
            return Candidate(id: drill.id, minutes: drill.durationMinutes, block: nil, type: nil,
                             category: drill.category, ageWeight: 0.6, isFavorite: drill.isFavorite)
        }
    }

    private static func fitsSlot(_ c: Candidate, _ slot: Slot) -> Bool {
        if let block = c.block {
            switch slot {
            case .warmup: return block == .routine || block == .smallGames
            case .skills: return block == .compete
            case .game: return block == .game
            }
        }
        switch slot {
        case .warmup: return [.warmup, .conditioning, .skills].contains(c.category)
        case .skills: return [.skills, .shooting, .defense, .offense].contains(c.category)
        case .game: return c.category == .offense
        }
    }

    static func pick(slot: Slot, budget: Int, candidates: [Candidate], focus: Set<ActivityType>,
                     history: History, reviewShare: Double, exclude: Set<UUID>,
                     random: () -> Double) -> [Candidate] {
        guard budget > 0 else { return [] }
        let eligible = candidates.filter {
            fitsSlot($0, slot) && !exclude.contains($0.id) && $0.minutes <= budget
                && !history.lastSession.contains($0.id)            // never repeat last session
        }
        func score(_ c: Candidate) -> Double {
            var s = c.ageWeight * 3
            if let t = c.type, focus.contains(t) { s += 2 }
            if c.isFavorite { s += 1 }
            // Spaced review: something seen once or twice is worth revisiting;
            // something run many times already less so.
            let n = history.count(c.id)
            if n > 0 { s += n <= 2 ? 0.5 : -0.5 * Double(n - 2) }
            return max(0.05, s)
        }
        let review = eligible.filter { history.count($0.id) > 0 }
        let fresh = eligible.filter { history.count($0.id) == 0 }

        var picks: [Candidate] = []
        var remaining = budget
        var reviewPool = review, freshPool = fresh
        // Warm-up ends with a small game when the library has one to offer.
        var wantSmallGame = slot == .warmup

        func draw(_ pool: inout [Candidate]) -> Candidate? {
            let fitting = pool.filter { $0.minutes <= remaining }
            guard !fitting.isEmpty else { return nil }
            let weights = fitting.map(score)
            let total = weights.reduce(0, +)
            var r = random() * total
            var chosen = fitting.last!
            for (c, w) in zip(fitting, weights) { r -= w; if r <= 0 { chosen = c; break } }
            pool.removeAll { $0.id == chosen.id }
            return chosen
        }

        while remaining >= 5 && picks.count < 5 {
            var next: Candidate?
            let reviewSoFar = picks.filter { history.count($0.id) > 0 }.count
            let wantReview = Double(reviewSoFar) < reviewShare * Double(picks.count + 1)
            if wantSmallGame && remaining <= 10 {
                var games = (reviewPool + freshPool).filter { $0.block == .smallGames }
                next = draw(&games)
                wantSmallGame = false
            }
            if next == nil {
                // Routine before small games inside the warm-up.
                if slot == .warmup {
                    var routineR = reviewPool.filter { $0.block != .smallGames }
                    var routineF = freshPool.filter { $0.block != .smallGames }
                    next = wantReview ? (draw(&routineR) ?? draw(&routineF)) : (draw(&routineF) ?? draw(&routineR))
                } else {
                    next = wantReview ? (draw(&reviewPool) ?? draw(&freshPool)) : (draw(&freshPool) ?? draw(&reviewPool))
                }
            }
            guard let chosen = next else { break }
            reviewPool.removeAll { $0.id == chosen.id }
            freshPool.removeAll { $0.id == chosen.id }
            picks.append(chosen)
            remaining -= chosen.minutes
        }
        return picks
    }
}

// MARK: - Rationale text

extension DrillPlanGenerator.PlanRationale {
    /// One line under the plan: what the engine read and decided.
    var summary: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        var parts: [String] = []
        let ages = ageWindow.map(\.rawValue).joined(separator: "–")
        parts.append(zh ? "\(age.rawValue) · 水平 \(level)" : "\(age.rawValue) · level \(level)")
        switch levelSource {
        case .coach: parts.append(zh ? "教练设定" : "set by coach")
        case .evaluations(let rated, let of, let average):
            parts.append(zh ? "依据 \(rated)/\(of) 名球员评估（均分 \(String(format: "%.1f", average))）"
                            : "from \(rated)/\(of) player evaluations (avg \(String(format: "%.1f", average)))")
        case .standard: parts.append(zh ? "评估不足，按标准水平" : "too few evaluations, standard level")
        }
        if ageWindow.count > 1 { parts.append(zh ? "取材 \(ages)" : "drawing on \(ages)") }
        if reviewCount + newCount > 0 {
            parts.append(zh ? "复习 \(reviewCount) · 新内容 \(newCount)" : "\(reviewCount) review · \(newCount) new")
        }
        if !focus.isEmpty {
            parts.append((zh ? "重点：" : "focus: ") + focus.prefix(3).map(\.title).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
