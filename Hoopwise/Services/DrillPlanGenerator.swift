import Foundation

// MARK: - Drill Plan Generator
//
// Deterministic, on-device. Given a session and its context (program, phase,
// enrolled players, recent history), produce a `SessionCurriculum` whose
// drill IDs fit the time budget per slot, the cohort's age and skill level,
// the phase's training focus, and avoid drills the cohort has run recently.
//
// Pure scoring + sampling — no LLM, no network. Generates a plan in ~10ms
// even with hundreds of drills in the library.

struct DrillPlanGenerator {

    // MARK: - Public API

    struct Context {
        let session: SessionEvent
        let program: Program?
        let phase: MicroCycle?
        let enrolledStudents: [Student]
        let players: [Player]            // For skills lookup
        let allDrills: [DrillItem]
        let recentSessions: [SessionEvent] // Last N sessions on the same program
    }

    /// Generate (or regenerate) a curriculum. Returns a new `SessionCurriculum`
    /// — caller assigns it to `session.curriculum` and saves.
    static func generate(in ctx: Context) -> SessionCurriculum {
        // Time budgets — honor whatever the session already had (set by phase
        // materialization or session-type defaults). Fall back to sensible
        // training defaults.
        let cur = ctx.session.curriculum
        let warmupBudget = max(5, cur.warmupMinutes)
        let skillsBudget = max(5, cur.skillsMinutes)
        let gameBudget   = max(0, cur.gameMinutes)

        // Build profiles once.
        let profiles = DrillProfile.profiles(for: ctx.allDrills)

        // Cohort signals.
        let cohort = Cohort(students: ctx.enrolledStudents,
                            players: ctx.players,
                            program: ctx.program,
                            phase: ctx.phase,
                            session: ctx.session)

        // Drills used recently — penalize them so plans rotate.
        let recentDrillIds = Set(ctx.recentSessions.flatMap { sess in
            sess.curriculum.warmupDrillIds + sess.curriculum.skillDrillIds + sess.curriculum.gameDrillIds
        })

        // Pick per slot. Each pass is independent so a drill could theoretically
        // appear in two slots — we de-dup at the end.
        let warmup = pick(slot: .warmup, budget: warmupBudget,
                          profiles: profiles, cohort: cohort, recentlyUsed: recentDrillIds, exclude: [])
        let skills = pick(slot: .skills, budget: skillsBudget,
                          profiles: profiles, cohort: cohort, recentlyUsed: recentDrillIds,
                          exclude: Set(warmup.map(\.drill.id)))
        let game = pick(slot: .game, budget: gameBudget,
                        profiles: profiles, cohort: cohort, recentlyUsed: recentDrillIds,
                        exclude: Set(warmup.map(\.drill.id)).union(skills.map(\.drill.id)))

        return SessionCurriculum(
            warmupDrillIds: warmup.map(\.drill.id),
            skillDrillIds: skills.map(\.drill.id),
            gameDrillIds: game.map(\.drill.id),
            warmupMinutes: warmupBudget,
            skillsMinutes: skillsBudget,
            gameMinutes: gameBudget,
            notes: cur.notes
        )
    }

    // MARK: - Slot

    enum Slot {
        case warmup, skills, game

        /// Drill categories considered eligible for this slot. Profiles outside
        /// these categories can still match through tags / focus, but we boost
        /// in-category drills heavily.
        var preferredCategories: Set<DrillCategory> {
            switch self {
            case .warmup: return [.warmup, .conditioning]
            case .skills: return [.skills, .shooting, .defense, .offense]
            case .game:   return [.offense, .skills]
            }
        }

        var preferredIntensity: DrillIntensity {
            switch self {
            case .warmup: return .low
            case .skills: return .medium
            case .game:   return .high
            }
        }
    }

    // MARK: - Cohort

    private struct Cohort {
        let count: Int
        let ageGroup: AgeGroup
        let avgSkillLevel: Double      // 0–10 (Player.skills.overallRating)
        let phaseFocus: Set<TrainingFocus>
        let sessionTypeFocus: Set<TrainingFocus>

        init(students: [Student], players: [Player],
             program: Program?, phase: MicroCycle?, session: SessionEvent) {
            self.count = max(1, students.count)
            self.ageGroup = program?.ageGroup ?? .u12

            let lookup = Dictionary(uniqueKeysWithValues: players.map { ($0.studentId, $0) })
            let ratings = students.compactMap { lookup[$0.id]?.skills.overallRating }
            self.avgSkillLevel = ratings.isEmpty
                ? 5.0
                : ratings.reduce(0, +) / Double(ratings.count)

            self.phaseFocus = Set(phase?.focus ?? [])
            self.sessionTypeFocus = Self.focus(for: session.sessionType)
        }

        /// Map session type → its natural focus areas.
        private static func focus(for type: SessionType) -> Set<TrainingFocus> {
            switch type {
            case .training:   return []                                   // Anything from phase
            case .scrimmage:  return [.teamPlay, .gamePrep]
            case .gamePrep:   return [.gamePrep, .teamPlay]
            case .recovery:   return [.recovery]
            case .assessment: return [.shooting, .ballHandling, .conditioning]
            }
        }
    }

    // MARK: - Picker

    /// Pick drills for one slot. Greedy budget fill ordered by score, with a
    /// small randomness factor so regenerating produces variety.
    private static func pick(slot: Slot,
                             budget: Int,
                             profiles: [DrillProfile],
                             cohort: Cohort,
                             recentlyUsed: Set<UUID>,
                             exclude: Set<UUID>) -> [DrillProfile] {
        guard budget > 0 else { return [] }

        // Score every profile, filter out hard-fail eligibility.
        let scored: [(profile: DrillProfile, score: Double)] = profiles.compactMap { p in
            guard !exclude.contains(p.drill.id) else { return nil }
            guard p.format.fits(cohort: cohort.count) else { return nil }
            // Drills longer than the entire slot can't fit at all.
            guard p.drill.durationMinutes <= budget else { return nil }
            let s = score(profile: p, slot: slot, cohort: cohort, recentlyUsed: recentlyUsed)
            // A hard floor — drills with terrible fit get culled before sampling.
            guard s > 0 else { return nil }
            return (p, s)
        }

        // Sort by score descending, then sample top portion with mild jitter
        // so two regenerations on the same data don't produce identical plans.
        let sorted = scored.sorted { $0.score > $1.score }
        let candidatePool = Array(sorted.prefix(max(8, sorted.count / 3)))

        var picks: [DrillProfile] = []
        var remaining = budget
        var pool = candidatePool

        while remaining > 0, !pool.isEmpty {
            // Weighted-random pick from the top of the pool. Higher score →
            // higher probability, but lower scores still get a shot.
            let idx = weightedRandomIndex(weights: pool.map(\.score))
            let chosen = pool.remove(at: idx)
            if chosen.profile.drill.durationMinutes <= remaining {
                picks.append(chosen.profile)
                remaining -= chosen.profile.drill.durationMinutes
            }
            // Cap to avoid bloated plans.
            if picks.count >= 5 { break }
        }

        return picks
    }

    // MARK: - Scoring

    /// Score a drill for a slot. Higher = better fit. Negative results are
    /// allowed and get culled before sampling.
    private static func score(profile p: DrillProfile,
                              slot: Slot,
                              cohort: Cohort,
                              recentlyUsed: Set<UUID>) -> Double {
        var score: Double = 1.0

        // 1. Slot category alignment — strong signal.
        if slot.preferredCategories.contains(p.drill.category) {
            score += 4.0
        } else {
            score -= 1.0
        }

        // 2. Intensity vs slot — closer is better.
        score += intensityMatchScore(drill: p.intensity, slot: slot.preferredIntensity)

        // 3. Focus match — phase focus first, session-type focus second.
        if !cohort.phaseFocus.isEmpty {
            let overlap = p.focus.intersection(cohort.phaseFocus).count
            score += Double(overlap) * 1.5
        }
        if !cohort.sessionTypeFocus.isEmpty {
            let overlap = p.focus.intersection(cohort.sessionTypeFocus).count
            score += Double(overlap) * 1.0
        }

        // 4. Age fit — drills tagged with the cohort's age (or "all ages")
        // get a boost; far-off ages are penalized.
        if p.ageGroups.isEmpty {
            // No tag = treat as universal, neutral.
        } else if p.ageGroups.contains(cohort.ageGroup) {
            score += 2.0
        } else {
            // Penalty proportional to age distance.
            let cohortAge = cohort.ageGroup.ceilingAge
            let nearest = p.ageGroups.map { abs($0.ceilingAge - cohortAge) }.min() ?? 99
            score -= Double(nearest) * 0.25
        }

        // 5. Difficulty fit. avgSkillLevel is on a 0–10 scale; map to drill
        // difficulty: <4 prefers beginner, 4–7 intermediate, >7 advanced.
        let preferredDifficulty: DifficultyLevel = {
            switch cohort.avgSkillLevel {
            case ..<4.0:  return .beginner
            case 4.0..<7.0: return .intermediate
            default:        return .advanced
            }
        }()
        if p.drill.difficulty == preferredDifficulty {
            score += 2.0
        } else if abs(p.drill.difficulty.level - preferredDifficulty.level) == 1 {
            score += 0.5
        } else {
            score -= 1.0
        }

        // 6. Freshness — penalize drills the cohort just did.
        if recentlyUsed.contains(p.drill.id) {
            score -= 3.0
        }

        // 7. Source bonus — coach-authored sits even with attributed sources;
        // unattributed gets a tiny nudge down so legit sources surface first.
        switch p.source {
        case .coachAuthored, .febYouth, .fibaDevelopment, .nbaPlayerDev, .coachsClipboard:
            score += 0.5
        case .unattributed:
            break
        }

        // 8. Coach favorites — bias toward what they trust.
        if p.drill.isFavorite { score += 1.0 }

        return score
    }

    private static func intensityMatchScore(drill: DrillIntensity, slot: DrillIntensity) -> Double {
        if drill == slot { return 1.5 }
        // One step away (low<->medium, medium<->high) is fine.
        if (drill == .low && slot == .medium) || (drill == .medium && slot == .low) ||
           (drill == .medium && slot == .high) || (drill == .high && slot == .medium) {
            return 0.0
        }
        // Two steps away (low<->high) is a real mismatch.
        return -1.5
    }

    /// Weighted random pick. Falls back to uniform if all weights are zero.
    private static func weightedRandomIndex(weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        guard total > 0 else { return Int.random(in: 0..<weights.count) }
        let pick = Double.random(in: 0..<total)
        var running: Double = 0
        for (i, w) in weights.enumerated() {
            running += w
            if pick < running { return i }
        }
        return weights.count - 1
    }
}
