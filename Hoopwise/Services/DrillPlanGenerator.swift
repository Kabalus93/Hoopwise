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

    /// The coach's say before generating (19 Nov 2026, Luther: "when tapping
    /// on generate, make it a custom generate with coach input — different
    /// parameters that would make the plan perfect"). nil / empty = the
    /// engine decides, exactly as before.
    struct Options: Equatable {
        /// Minutes for each visible block.
        var warmupMinutes: Int? = nil
        var skillsMinutes: Int? = nil
        /// 1–5, instead of the program's level / the evaluations.
        var level: Int? = nil
        /// Skills to build this class around: drills strong on them win.
        var skills: Set<DrillAttribute> = []
        /// Share of the plan that revisits drills run before (0 = all new).
        var reviewShare: Double? = nil
        /// Keep the drills already in the plan and fill the time left.
        var keepExisting = false
        /// Leave out what the last class ran (the engine's rule).
        var avoidLastSession = true
    }

    static func generatePlan(in ctx: Context, options: Options = Options(),
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
        let warmupBudget = max(5, options.warmupMinutes ?? cur.warmupMinutes)
        let skillsBudget = max(5, options.skillsMinutes ?? cur.skillsMinutes)
        let gameBudget = max(0, cur.gameMinutes)

        let age = libraryAge(for: ctx.program?.ageGroup)
        let resolved = resolveLevel(program: ctx.program, students: ctx.enrolledStudents, players: ctx.players)
        let (level, source) = options.level.map { (min(max($0, 1), 5), LevelSource.coach) } ?? resolved
        let window = ageWeights(age: age, level: level)
        // Only classes that happened speak (a skipped class's games and
        // results were never real), oldest first.
        let happened = ctx.programHistory.filter { !SessionLifecycle.didNotHappen($0) }
            .sorted { $0.startTime < $1.startTime }
        let focus = focusTypes(phase: ctx.phase, students: ctx.enrolledStudents, players: ctx.players,
                               games: happened.flatMap(\.games),
                               shooting: happened.flatMap(\.curriculum.shooting),
                               tracked: happened.flatMap(\.curriculum.tracked))
        var history = History(sessions: ctx.programHistory, before: ctx.session)
        if !options.avoidLastSession { history.forgetLastSession() }
        var gaps = phaseGaps(ctx)
        // The coach's chosen skills weigh as a full gap (and a little more).
        for skill in options.skills { gaps[skill] = max(gaps[skill] ?? 0, 1.5) }
        let reviewShare = options.reviewShare ?? history.reviewShare(phase: ctx.phase, session: ctx.session)

        var rationale = PlanRationale(age: age, level: level, levelSource: source,
                                      ageWindow: ActivityAge.allCases.filter { window[$0] != nil },
                                      focus: focus.types)
        rationale.notes = focus.notes
        if !options.skills.isEmpty {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            rationale.notes.append((zh ? "教练选择的重点：" : "your focus: ")
                + DrillAttribute.allCases.filter { options.skills.contains($0) }.map(\.title).joined(separator: ", "))
        }
        let topGaps = gaps.filter { $0.value >= 0.4 && !options.skills.contains($0.key) }
            .sorted { $0.value > $1.value }.prefix(2).map(\.key.title)
        if !topGaps.isEmpty {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            rationale.notes.append((zh ? "补本阶段的短板：" : "fills the phase's gaps: ") + topGaps.joined(separator: ", "))
        }

        // What the coach's "too easy" / "too hard" ratings at this age say
        // about the level — said, never applied.
        let turnedDown = ctx.allDrills.filter { $0.libraryActivity?.age == age && ($0.preference == .less || $0.preference == .never) }
        if let hint = DrillLevelHint.make(tooEasy: turnedDown.filter { $0.preferenceReason == .tooEasy }.count,
                                          tooHard: turnedDown.filter { $0.preferenceReason == .tooHard || $0.preferenceReason == .notNow }.count) {
            let zh = LocalizationManager.shared.currentLanguage == .chinese
            switch hint {
            case .raise(let n) where level < 5:
                rationale.notes.append(zh ? "你把 \(n) 个本年龄段的训练评为太简单——可以考虑提高水平" : "you rated \(n) drills at this age too easy — a higher level may fit")
            case .lower(let n) where level > 1:
                rationale.notes.append(zh ? "你把 \(n) 个本年龄段的训练评为太难——可以考虑降低水平" : "you rated \(n) drills at this age too hard — a lower level may fit")
            default: break
            }
        }

        let candidates = candidates(drills: ctx.allDrills, window: window, age: age, level: level)
        // Keeping what is planned: it stays first, and only the time left fills.
        let keptWarmup = options.keepExisting ? cur.warmupDrillIds : []
        let keptSkills = options.keepExisting ? cur.skillDrillIds : []
        var used: Set<UUID> = Set(keptWarmup + keptSkills)
        func minutes(_ ids: [UUID]) -> Int {
            ids.reduce(0) { sum, id in sum + (ctx.allDrills.first { $0.id == id }?.durationMinutes ?? 0) }
        }
        func fill(_ slot: Slot, _ budget: Int) -> [UUID] {
            let picks = pick(slot: slot, budget: budget, candidates: candidates, focus: Set(focus.types),
                             history: history, reviewShare: reviewShare, exclude: used, gaps: gaps, random: random)
            used.formUnion(picks.map(\.id))
            for p in picks { if history.count(p.id) > 0 { rationale.reviewCount += 1 } else { rationale.newCount += 1 } }
            return picks.map(\.id)
        }
        let warmup = keptWarmup + fill(.warmup, max(0, warmupBudget - minutes(keptWarmup)))
        let skills = keptSkills + fill(.skills, max(0, skillsBudget - minutes(keptSkills)))
        let game = fill(.game, gameBudget)

        let curriculum = SessionCurriculum(
            warmupDrillIds: warmup, skillDrillIds: skills, gameDrillIds: game,
            warmupMinutes: warmupBudget, skillsMinutes: skillsBudget, gameMinutes: gameBudget,
            notes: cur.notes)
        return (curriculum, rationale)
    }

    /// Target minus what the phase's other planned sessions already train
    /// (both 0…1 by axis); empty with no target.
    static func phaseGaps(_ ctx: Context) -> [DrillAttribute: Double] {
        guard let target = PlanCoverage.target(phaseFocus: ctx.phase?.focus ?? [],
                                               skillTargets: ctx.program?.skillTargets,
                                               groupRatings: groupRatings(students: ctx.enrolledStudents,
                                                                          players: ctx.players)) else { return [:] }
        let phaseSessions = ctx.programHistory.filter { session in
            session.id != ctx.session.id && !SessionLifecycle.didNotHappen(session)
                && (ctx.phase == nil || session.microCycleId == ctx.phase?.id)
        }
        var minutes: [DrillAttribute: Double] = [:]
        for session in phaseSessions {
            for (axis, v) in PlanCoverage.minutes(of: session.curriculum, drills: ctx.allDrills) { minutes[axis, default: 0] += v }
        }
        let covered = PlanCoverage.normalized(minutes)
        var gaps: [DrillAttribute: Double] = [:]
        for (axis, want) in target {
            let gap = want - (covered[axis] ?? 0)
            if gap > 0 { gaps[axis] = gap }
        }
        return gaps
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
    /// trust it. A player counts as rated once they have an eight-skill
    /// evaluation (17 Nov 2026 — the old six-skill one is no longer read).
    static func suggestedLevel(students: [Student], players: [Player])
        -> (level: Int, rated: Int, average: Double)? {
        let byStudent = Dictionary(players.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
        let ratings = students.compactMap { byStudent[$0.id] }.compactMap(\.skills.ratedAverage)
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

    private static func isRated(_ player: Player) -> Bool { player.skills.isEvaluated }

    /// The group's average rating per skill, over the players who rated it
    /// (an unrated skill is unknown, not 0). Empty without evaluations.
    static func groupRatings(students: [Student], players: [Player]) -> [DrillAttribute: Double] {
        let byStudent = Dictionary(players.map { ($0.studentId, $0) }, uniquingKeysWith: { a, _ in a })
        let rated = students.compactMap { byStudent[$0.id] }.filter(isRated)
        var out: [DrillAttribute: Double] = [:]
        for axis in DrillAttribute.allCases {
            let values = rated.compactMap { $0.skills.rating(axis) }
            if !values.isEmpty { out[axis] = Double(values.reduce(0, +)) / Double(values.count) }
        }
        return out
    }

    /// The library activity types that work a skill (weight ≥ 0.6).
    static func activityTypes(for axis: DrillAttribute) -> [ActivityType] {
        ActivityType.allCases.filter { (AttributeProfile.weights(forSkill: $0.rawValue)[axis] ?? 0) >= 0.6 }
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
                                   games: [SessionGame] = [], shooting: [ShootingRun] = [],
                                   tracked: [TrackedRun] = [])
        -> (types: [ActivityType], notes: [String]) {
        var types: [ActivityType] = []
        var notes: [String] = []
        for f in phase?.focus ?? [] { types += map(f) }

        // The roster's weakest evaluated skill (the eight octagon skills, 1–10),
        // when evaluations exist and actually differ between skills.
        let group = groupRatings(students: students, players: players)
        if let low = group.min(by: { $0.value < $1.value }),
           let high = group.max(by: { $0.value < $1.value }), high.value - low.value >= 1 {
            types += activityTypes(for: low.key)
            notes.append("weakest:\(low.key.rawValue)")
        }
        // Performance: with at least 3 recorded games, few assists per basket
        // means the ball sticks — push passing and team play.
        if let signal = passingSignal(games: games, roster: Set(students.map(\.id))) {
            types += [.passing, .teamPlay]
            notes.append(signal)
        }
        // Few steals and blocks per player per game: nobody is pressuring the
        // ball or protecting the rim — push defence.
        if let signal = defenseSignal(games: games, roster: Set(students.map(\.id))) {
            types += [.defence, .oneOnOne]
            notes.append(signal)
        }
        // Tracked shooting drills (20 Nov 2026): the group shoots poorly.
        if let signal = shootingSignal(runs: shooting, roster: Set(students.map(\.id))) {
            types += [.shooting, .layups]
            notes.append(signal)
        }

        // The coach's own tracked drills (23 Nov 2026): a made-of drill the
        // group makes under 35 % puts its linked skills in focus.
        for (axis, signal) in trackedSignals(runs: tracked, roster: Set(students.map(\.id))) {
            types += activityTypes(for: axis)
            notes.append(signal)
        }

        var seen = Set<ActivityType>()
        return (types.filter { seen.insert($0).inserted }, notes)
    }

    /// What the coach's own tracked drills say about the roster (runs
    /// oldest first), per MAIN skill of the drill:
    /// · "tracked:<skill>:<share>" — a made-of drill the roster makes under
    ///   35 % (latest result each, ≥ 3 athletes);
    /// · "trackedDown:<skill>:<percent>" — any measure: ≥ 3 athletes with a
    ///   latest and a previous result under the same setup, and the group is
    ///   10 % or more worse than last time (slower, fewer, a lower share).
    /// One signal a skill, the low share first.
    static func trackedSignals(runs: [TrackedRun], roster: Set<UUID>) -> [(DrillAttribute, String)] {
        // drill|key → the definition and each athlete's results in order.
        var series: [String: (TrackDefinition, [UUID: [Double]])] = [:]
        for run in runs {
            let k = "\(run.drillId)|\(run.definition.key)"
            var entry = series[k] ?? (run.definition, [:])
            entry.0 = run.definition
            for id in roster { if let v = run.result(for: id) { entry.1[id, default: []].append(v) } }
            series[k] = entry
        }
        var out: [(DrillAttribute, String)] = []
        func add(_ def: TrackDefinition, _ note: (DrillAttribute) -> String) {
            for axis in def.mainAttributes where !out.contains(where: { $0.0 == axis }) {
                out.append((axis, note(axis)))
            }
        }
        let ordered = series.values.sorted { $0.0.key < $1.0.key }
        for (def, values) in ordered where def.measure == .madeOf && values.count >= 3 {
            let latest = values.values.compactMap(\.last)
            let avg = latest.reduce(0, +) / Double(latest.count)
            if avg < 0.35 { add(def) { "tracked:\($0.rawValue):\(Int((avg * 100).rounded()))%" } }
        }
        for (def, values) in ordered {
            let pairs = values.values.compactMap { v -> (Double, Double)? in
                v.count >= 2 ? (v[v.count - 2], v[v.count - 1]) : nil
            }
            guard pairs.count >= 3 else { continue }
            let before = pairs.reduce(0) { $0 + $1.0 } / Double(pairs.count)
            let now = pairs.reduce(0) { $0 + $1.1 } / Double(pairs.count)
            guard before > 0 else { continue }
            // Worse = lower when higher is better, higher when lower is.
            let worse = def.lowerIsBetter ? (now - before) / before : (before - now) / before
            if worse >= 0.10 { add(def) { "trackedDown:\($0.rawValue):\(Int((worse * 100).rounded()))%" } }
        }
        return out
    }

    /// The emphasis the DATA asks for — weakest evaluated area, and passing
    /// when game stats show few assists. No phase input.
    static func dataFocus(students: [Student], players: [Player], games: [SessionGame]) -> [ActivityType] {
        focusTypes(phase: nil, students: students, players: players, games: games).types
    }

    /// "assists:<ratio>" when the roster's games show under one assist per
    /// five baskets; nil without enough games or baskets to say. Baskets are
    /// points ÷ THAT GAME's basket value — the Games tab's definition
    /// (`GameStatsReport.assistsPerBasket`); this used to assume every basket
    /// was worth two, so the tab and the engine disagreed in 1- and 3-point
    /// games.
    static func passingSignal(games: [SessionGame], roster: Set<UUID>) -> String? {
        guard let rate = GameStatsReport.assistsPerBasket(games: games, roster: roster) else { return nil }
        return rate.ratio < 0.2 ? "assists:\(String(format: "%.2f", rate.ratio))" : nil
    }

    /// "shooting:<share>" when the roster's tracked shooting (made out of N —
    /// timed results have no common yardstick) averages under 35 % in ONE
    /// test, over at least three athletes' latest results there. Each test
    /// (drill and setup) is judged alone — free throws and threes used to be
    /// averaged together. The lowest such test is reported.
    static func shootingSignal(runs: [ShootingRun], roster: Set<UUID>) -> String? {
        var latest: [String: [UUID: Double]] = [:]
        for run in runs where run.setup.mode.isShare {
            for id in run.reporters where roster.contains(id) {
                if let r = run.result(for: id) { latest[run.setup.key, default: [:]][id] = r.value }
            }
        }
        let lows = latest.values.compactMap { byAthlete -> Double? in
            guard byAthlete.count >= 3 else { return nil }
            let avg = byAthlete.values.reduce(0, +) / Double(byAthlete.count)
            return avg < 0.35 ? avg : nil
        }
        guard let low = lows.min() else { return nil }
        return "shooting:\(Int((low * 100).rounded()))%"
    }

    /// "stocks:<per player-game>" when the roster's games show under one
    /// steal or block per three player-games; nil without enough games. A
    /// player-game is everyone who TOOK PART (`SessionGame.participants`),
    /// not only those with a stat line — a line exists only once a stat is
    /// recorded, so the quiet players were left out and the rate overstated.
    static func defenseSignal(games: [SessionGame], roster: Set<UUID>) -> String? {
        var playerGames = 0, stocks = 0, counted = 0
        for game in games where GameStatsReport.played(game) {
            let here = game.participants.keys.filter(roster.contains)
            guard !here.isEmpty else { continue }
            counted += 1
            playerGames += here.count
            for id in here {
                if let line = game.stats(for: id) { stocks += line.steals + line.blocks }
            }
        }
        guard counted >= 3, playerGames >= 15 else { return nil }
        let rate = Double(stocks) / Double(playerGames)
        return rate < 0.34 ? "stocks:\(String(format: "%.2f", rate))" : nil
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

        /// The coach allows the last class's drills again.
        mutating func forgetLastSession() { lastSession = [] }

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
        /// What it develops (November 2026), for filling a phase's gaps.
        var attributes = AttributeProfile()
        /// How the coach uses it (19 Nov 2026): more, normal, less.
        var preference: DrillPreference = .normal
    }

    private static func candidates(drills: [DrillItem], window: [ActivityAge: Double], age: ActivityAge, level: Int) -> [Candidate] {
        drills.compactMap { drill in
            // A series is not a drill; a drill the coach never uses is never planned.
            guard !drill.isSeries, drill.preference != .never else { return nil }
            // "Use less" follows its reason at this level (too easy / too hard).
            let preference = drill.preference(atLevel: level)
            if let a = drill.libraryActivity {
                guard !a.isRule, let w = window[a.age] else { return nil }
                return Candidate(id: drill.id, minutes: drill.durationMinutes, block: a.block, type: a.type,
                                 category: drill.category, ageWeight: w, isFavorite: drill.isFavorite,
                                 attributes: drill.attributes, preference: preference)
            }
            // A coach's own drill: eligible when untagged or tagged for this age.
            let profile = DrillProfile(drill)
            let fits = profile.ageGroups.isEmpty
                || profile.ageGroups.contains { libraryAge(for: $0) == age || window[libraryAge(for: $0)] != nil }
            guard fits else { return nil }
            return Candidate(id: drill.id, minutes: drill.durationMinutes, block: nil, type: nil,
                             category: drill.category, ageWeight: 0.6, isFavorite: drill.isFavorite,
                             attributes: drill.attributes, preference: preference)
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
                     gaps: [DrillAttribute: Double] = [:],
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
            // What the phase has neglected so far (PlanCoverage): drills
            // strong on a gap weigh more.
            for (axis, gap) in gaps { s += 2 * gap * Double(c.attributes[axis]) / 3 }
            // Spaced review: something seen once or twice is worth revisiting;
            // something run many times already less so.
            let n = history.count(c.id)
            if n > 0 { s += n <= 2 ? 0.5 : -0.5 * Double(n - 2) }
            // The coach's way: use more / use less (never is already out).
            s = c.preference.adjusted(max(0.05, s)) ?? 0
            return max(0.02, s)
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
        parts += notes.compactMap { Self.readable($0, zh: zh) }
        return parts.joined(separator: " · ")
    }

    /// What a focus note means, in words; nil for a note with nothing to say.
    static func readable(_ note: String, zh: Bool) -> String? {
        let parts = note.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return note }
        switch parts[0] {
        case "weakest":
            guard let axis = DrillAttribute(rawValue: parts[1]) else { return nil }
            return zh ? "评估最弱：\(axis.title)" : "weakest evaluated: \(axis.title)"
        case "assists":
            return zh ? "比赛中助攻偏少（每球 \(parts[1])）" : "few assists in games (\(parts[1]) per basket)"
        case "shooting":
            return zh ? "投篮测试命中偏低（平均 \(parts[1])）" : "low shooting-drill results (\(parts[1]) average)"
        case "tracked":
            let bits = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard bits.count == 2, let axis = DrillAttribute(rawValue: bits[0]) else { return nil }
            return zh ? "训练成绩偏低：\(axis.title(chinese: true))（平均 \(bits[1])）"
                      : "low tracked-drill results: \(axis.title(chinese: false)) (\(bits[1]) average)"
        case "trackedDown":
            let bits = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard bits.count == 2, let axis = DrillAttribute(rawValue: bits[0]) else { return nil }
            return zh ? "训练成绩比上次下降 \(bits[1])：\(axis.title(chinese: true))"
                      : "tracked-drill results down \(bits[1]) on last time: \(axis.title(chinese: false))"
        case "stocks":
            return zh ? "比赛中抢断盖帽偏少（人均每场 \(parts[1])）" : "few steals and blocks in games (\(parts[1]) per player-game)"
        default:
            return note
        }
    }
}
