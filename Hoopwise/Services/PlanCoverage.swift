import Foundation

// What a plan trains, on the eight DrillAttribute axes (November 2026,
// Luther: "based on the drills I add to the session … a visual octagon that
// shows what is emphasised and what has been neglected … this feeds back into
// the program"). Pure: the session's Plan dashboard, the program's phase
// coverage and Generate Plan all read it.

enum PlanCoverage {
    /// Axis → weighted minutes. Each drill's 0–3 scores count in proportion to
    /// its share of its block's minutes (a block with no minutes falls back to
    /// the drills' own durations); a play counts like a ten-minute drill
    /// shaped by its skills.
    static func minutes(of curriculum: SessionCurriculum, drills: [DrillItem],
                        playProfile: (SessionPlayRef) -> AttributeProfile = { _ in defaultPlayProfile }) -> [DrillAttribute: Double] {
        let byId = Dictionary(drills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var total: [DrillAttribute: Double] = [:]
        func add(_ profile: AttributeProfile, minutes: Double) {
            for axis in DrillAttribute.allCases { total[axis, default: 0] += minutes * Double(profile[axis]) / 3 }
        }
        func block(_ ids: [UUID], minutes: Int) {
            let found = ids.compactMap { byId[$0] }
            guard !found.isEmpty else { return }
            let share = minutes > 0 ? Double(minutes) / Double(found.count) : nil
            for drill in found { add(drill.attributes, minutes: share ?? Double(max(drill.durationMinutes, 5))) }
        }
        block(curriculum.warmupDrillIds, minutes: curriculum.warmupMinutes)
        block(curriculum.skillDrillIds, minutes: curriculum.skillsMinutes)
        block(curriculum.gameDrillIds, minutes: curriculum.gameMinutes)
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
                       teamSkills: [String] = []) -> [DrillAttribute: Double]? {
        var w: [DrillAttribute: Double] = [:]
        for focus in phaseFocus {
            for (axis, v) in AttributeProfile.weights(for: focus) { w[axis, default: 0] += v }
        }
        if let t = skillTargets, t.hasTargets {
            let scale = 1.0 / 10
            let parts: [(DrillAttribute, Double)] = [
                (.shooting, Double(t.scoring)), (.finishing, Double(t.scoring) * 0.8),
                (.playmaking, Double(t.playmaking)), (.passing, Double(t.playmaking) * 0.8),
                (.defense, Double(t.defense)), (.defense, Double(t.rebounding) * 0.5),
                (.footwork, Double(t.athleticism)), (.gameIQ, Double(t.intangibles)),
            ]
            for (axis, v) in parts { w[axis, default: 0] += v * scale }
        }
        for skill in teamSkills {
            for (axis, v) in AttributeProfile.weights(forSkill: skill) { w[axis, default: 0] += v }
        }
        let n = normalized(w)
        return n.isEmpty ? nil : n
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
