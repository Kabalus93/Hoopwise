import Foundation

// What a plan trains, on the eight DrillAttribute axes (November 2026,
// Luther: "based on the drills I add to the session … a visual octagon that
// shows what is emphasised and what has been neglected … this feeds back into
// the program"). Pure: the session's Plan dashboard, the program's phase
// coverage and Generate Plan all read it.

enum PlanCoverage {
    /// Axis → minutes. Each drill's own minutes (what the Plan tab shows) are
    /// shared among its skills by their 0–3 scores, so the eight add up to
    /// the plan; a play counts like a ten-minute drill shaped by its skills.
    static func minutes(of curriculum: SessionCurriculum, drills: [DrillItem],
                        playProfile: (SessionPlayRef) -> AttributeProfile = { _ in defaultPlayProfile }) -> [DrillAttribute: Double] {
        let byId = Dictionary(drills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var total: [DrillAttribute: Double] = [:]
        // A drill's minutes are SHARED among the skills it works, by their
        // scores — so the minutes of all eight skills add up to the plan's
        // own minutes (26 Nov 2026, Luther: "the math still does not add
        // up" — a 73-minute plan read ~46 min footwork, ~40 finishing, ~40
        // game IQ, because a 20-minute drill counted 20 minutes for EACH
        // skill it had as Main).
        func add(_ profile: AttributeProfile, minutes: Double) {
            let sum = DrillAttribute.allCases.reduce(0) { $0 + profile[$1] }
            guard sum > 0 else { return }
            for axis in DrillAttribute.allCases where profile[axis] > 0 {
                total[axis, default: 0] += minutes * Double(profile[axis]) / Double(sum)
            }
        }
        // Each drill counts for ITS OWN minutes — the same numbers the Plan
        // tab adds up in each block's header (18 Nov 2026, Luther: "still
        // got wrong numbers here" — "Ball handling ~50 min" on a plan whose
        // blocks read 24 + 10 min: the stored block length, set when the plan
        // was generated and never shown, was shared out instead).
        func block(_ ids: [UUID]) {
            for drill in ids.compactMap({ byId[$0] }) {
                add(drill.attributes, minutes: Double(drill.durationMinutes))
            }
        }
        block(curriculum.warmupDrillIds)
        block(curriculum.skillDrillIds)
        // The Game block is NOT counted (17 Nov 2026, Luther: "where do these
        // numbers come from? Make sure they reflect the plan"): the Plan tab
        // shows Warm-up and Skills only, and a 34-minute visible plan
        // reported ~57 minutes of ball handling because the hidden game
        // block's drills and minutes were added in.
        for ref in curriculum.plays { add(playProfile(ref), minutes: 10) }
        return total
    }

    /// A play with no breakdown: reading, creating, passing.
    static let defaultPlayProfile = AttributeProfile(scores: [.gameIQ: 3, .playmaking: 2, .passing: 2, .footwork: 1])

    /// A team play's profile from its breakdown's skills (else the default).
    static func playProfile(_ ref: SessionPlayRef, teams: [Team]) -> AttributeProfile {
        var weights: [DrillAttribute: Double] = [:]
        for team in teams {
            for role in team.playbook.breakdowns[ref.key]?.roles ?? [] {
                for skill in role.skills {
                    for (axis, w) in AttributeProfile.weights(forSkill: skill) { weights[axis, default: 0] += w }
                }
            }
        }
        guard let top = weights.values.max(), top > 0 else { return defaultPlayProfile }
        var p = AttributeProfile(scores: weights.mapValues { Int(($0 / top * 3).rounded()) })
        p[.gameIQ] = max(p[.gameIQ], 2)
        return p
    }

    /// Scaled so the biggest axis is 1 — the octagon shows EMPHASIS.
    static func normalized(_ values: [DrillAttribute: Double]) -> [DrillAttribute: Double] {
        guard let top = values.values.max(), top > 0 else { return [:] }
        return values.mapValues { $0 / top }
    }

    /// What the session should emphasise, from BOTH sources Luther asked for:
    /// the phase focus and the program's skill targets (team practices: the
    /// team's focus plays' skills). Nil when nothing says.
    static func target(phaseFocus: [TrainingFocus], skillTargets: ProgramSkillTargets?,
                       teamSkills: [String] = [],
                       groupRatings: [DrillAttribute: Double] = [:]) -> [DrillAttribute: Double]? {
        var w: [DrillAttribute: Double] = [:]
        for focus in phaseFocus {
            for (axis, v) in AttributeProfile.weights(for: focus) { w[axis, default: 0] += v }
        }
        // The program's targets on the eight skills (a target of 8 asks for
        // 0.8). They used to be six retired skills spread over the eight.
        if let t = skillTargets, t.hasTargets {
            for axis in DrillAttribute.allCases {
                if let want = t.target(axis) { w[axis, default: 0] += Double(want) / 10 }
            }
        }
        for skill in teamSkills {
            for (axis, v) in AttributeProfile.weights(forSkill: skill) { w[axis, default: 0] += v }
        }
        var n = normalized(w)
        // The GROUP's weakest rated skills (17 Nov 2026 — the evaluation feeds
        // the plan): a skill the expected athletes average 5 or less on asks
        // for 0.6 (at 5) up to ~0.92 (at 1), whatever the phase says.
        for (axis, value) in groupWeakness(groupRatings) { n[axis] = max(n[axis] ?? 0, value) }
        return n.isEmpty ? nil : n
    }

    /// The group's weak skills as target values (average ≤ 5 → 0.6…0.92).
    static func groupWeakness(_ groupRatings: [DrillAttribute: Double]) -> [DrillAttribute: Double] {
        var out: [DrillAttribute: Double] = [:]
        for (axis, avg) in groupRatings where avg <= 5 { out[axis] = min(1, 0.6 + (5 - avg) * 0.08) }
        return out
    }

    /// Axes the target really asks for (≥ 0.6 — a focus's secondary axes,
    /// weighted 0.5, don't count) where the plan falls well short (target −
    /// plan ≥ 0.4, the plan scaled to its biggest axis), biggest gap first.
    static func neglected(plan: [DrillAttribute: Double], target: [DrillAttribute: Double]?) -> [DrillAttribute] {
        guard let target else { return [] }
        let p = normalized(plan)
        func gap(_ axis: DrillAttribute) -> Double { (target[axis] ?? 0) - (p[axis] ?? 0) }
        return DrillAttribute.allCases
            .filter { (target[$0] ?? 0) >= 0.6 && gap($0) >= 0.4 }
            .sorted { gap($0) > gap($1) }
    }

    /// The axes the plan leans on, biggest first (≥ 0.6 of the top).
    static func emphasis(_ plan: [DrillAttribute: Double]) -> [DrillAttribute] {
        let p = normalized(plan)
        return DrillAttribute.allCases.filter { (p[$0] ?? 0) >= 0.6 }.sorted { (p[$0] ?? 0) > (p[$1] ?? 0) }
    }
}
