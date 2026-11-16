import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Program Stats Context (for peer comparison)
struct ProgramStatsContext {
    let maxPPG: Double
    let maxRPG: Double
    let maxAPG: Double
    let maxSPG: Double
    let maxBPG: Double
    let maxEffort: Double
    let avgPPG: Double
    let studentCount: Int
    
    static let empty = ProgramStatsContext(maxPPG: 15, maxRPG: 8, maxAPG: 5, maxSPG: 3, maxBPG: 2, maxEffort: 7, avgPPG: 0, studentCount: 0)
    
    /// Calculate program stats from all enrolled students' training stats
    static func calculate(from allStats: [TrainingSessionStats]) -> ProgramStatsContext {
        let validStats = allStats.filter { $0.hasStats }
        guard !validStats.isEmpty else { return .empty }

        let maxPPG = max(validStats.map { $0.ppg }.max() ?? 15, 5) // Minimum 5 to avoid division issues
        let maxRPG = max(validStats.map { $0.rpg }.max() ?? 8, 3)
        let maxAPG = max(validStats.map { $0.apg }.max() ?? 5, 2)
        let maxSPG = max(validStats.map { $0.spg }.max() ?? 3, 1)
        let maxBPG = max(validStats.map { $0.bpg }.max() ?? 2, 1)
        let maxEffort = max(validStats.map { $0.efrt }.max() ?? 7, 2)
        let avgPPG = validStats.map { $0.ppg }.reduce(0, +) / Double(validStats.count)
        
        return ProgramStatsContext(
            maxPPG: maxPPG,
            maxRPG: maxRPG,
            maxAPG: maxAPG,
            maxSPG: maxSPG,
            maxBPG: maxBPG,
            maxEffort: maxEffort,
            avgPPG: avgPPG,
            studentCount: validStats.count
        )
    }
}

// MARK: - Smart Blending Engine for Performance Radar
/// Blends tangible game stats with coach evaluations using confidence-based weighting.
/// More games played = higher weight on stats. Stats always prioritized over subjective evaluation.
struct PerformanceRadarMetrics {
    let scoring: Double      // PPG blended with coach scoring eval
    let playmaking: Double   // APG blended with coach playmaking eval
    let rebounding: Double   // RPG blended with coach rebounding eval
    let defense: Double      // (SPG+BPG)/2 blended with coach defense eval
    let athleticism: Double  // Pure coach evaluation (no stat)
    let effort: Double       // Tangible (RPG+APG+SPG+BPG) normalized vs peers
    let hasGameData: Bool
    let gamesPlayed: Int
    let isComparedToPeers: Bool
    
    // MARK: - Confidence-Based Stat Weights
    /// Returns the weight for game stats based on games played (0.0 - 0.8)
    /// More games = more confidence in stats = higher weight
    private static func statWeight(gamesPlayed: Int) -> Double {
        switch gamesPlayed {
        case 0:      return 0.0   // No games: 100% coach eval
        case 1...2:  return 0.5   // Few games: 50/50 blend
        case 3...5:  return 0.6   // Some games: 60% stats
        case 6...10: return 0.7   // Good sample: 70% stats
        default:     return 0.8   // Large sample: 80% stats (max)
        }
    }
    
    /// Compute hybrid metrics from game stats and coach evaluations (legacy)
    static func compute(from stats: TrainingSessionStats?, skills: SkillsEvaluation) -> PerformanceRadarMetrics {
        return compute(from: stats, skills: skills, programContext: nil)
    }
    
    /// Smart blending engine: combines game stats with coach evaluations
    /// - Stats are normalized against program peers (or fixed ceiling if no peers)
    /// - Weight shifts toward stats as more games are played
    /// - Athleticism is coach evaluation (no measurable stat)
    static func compute(from stats: TrainingSessionStats?, skills: SkillsEvaluation, programContext: ProgramStatsContext?) -> PerformanceRadarMetrics {
        let hasData = stats?.hasStats ?? false
        let gp = stats?.gamesPlayed ?? 0
        let context = programContext ?? .empty
        let hasPeerData = context.studentCount >= 1
        
        // Calculate confidence-based weight
        let statW = statWeight(gamesPlayed: gp)
        let evalW = 1.0 - statW
        
        // Helper: normalize a stat against max (peer or fixed ceiling)
        func normalize(_ value: Double, peerMax: Double, fixedMax: Double) -> Double {
            let max = (hasPeerData && peerMax > 0) ? peerMax : fixedMax
            return min((value / max) * 10.0, 10.0)
        }
        
        // Helper: blend stat with coach evaluation
        // Adds a floor so blended value never drops below 40% of coach eval
        // This prevents 0-stat scenarios from completely negating coach evaluation
        func blend(stat: Double, eval: Int) -> Double {
            let raw = stat * statW + Double(eval) * evalW
            let floor = Double(eval) * 0.4  // Minimum 40% of coach eval
            return max(raw, floor)
        }
        
        // SCORING: PPG (ceiling: peer max or 15 PPG)
        let scoringStat = hasData ? normalize(stats!.ppg, peerMax: context.maxPPG, fixedMax: 15.0) : 0
        let scoring = hasData ? blend(stat: scoringStat, eval: skills.scoring) : Double(skills.scoring)
        
        // PLAYMAKING: APG (ceiling: peer max or 5 APG)
        let playmakingStat = hasData ? normalize(stats!.apg, peerMax: context.maxAPG, fixedMax: 5.0) : 0
        let playmaking = hasData ? blend(stat: playmakingStat, eval: skills.playmaking) : Double(skills.playmaking)
        
        // REBOUNDING: RPG (ceiling: peer max or 8 RPG)
        let reboundingStat = hasData ? normalize(stats!.rpg, peerMax: context.maxRPG, fixedMax: 8.0) : 0
        let rebounding = hasData ? blend(stat: reboundingStat, eval: skills.rebounding) : Double(skills.rebounding)
        
        // DEFENSE: (SPG + BPG) / 2 (ceiling: peer max or 3 SPG / 2 BPG)
        let spgNorm = hasData ? normalize(stats!.spg, peerMax: context.maxSPG, fixedMax: 3.0) : 0
        let bpgNorm = hasData ? normalize(stats!.bpg, peerMax: context.maxBPG, fixedMax: 2.0) : 0
        let defenseStat = (spgNorm + bpgNorm) / 2.0
        // Defense uses slightly lower stat weight (0.6 max) since steals/blocks don't capture full defense
        let defenseStatW = min(statW, 0.6)
        let defenseEvalW = 1.0 - defenseStatW
        let defense = hasData ? (defenseStat * defenseStatW + Double(skills.defense) * defenseEvalW) : Double(skills.defense)
        
        // ATHLETICISM: Pure coach evaluation (no measurable stat)
        let athleticism = Double(skills.athleticism)

        // EFFORT: tangible overall involvement (rebounds + assists + steals + blocks per game)
        // Kept stat-only to remain measurable and comparable.
        let effortRaw = hasData ? stats!.efrt : 0
        let effortStat = hasData ? normalize(effortRaw, peerMax: context.maxEffort, fixedMax: 7.0) : 0
        let effort = hasData ? effortStat : Double((skills.rebounding + skills.playmaking + skills.defense) / 3)
        
        return PerformanceRadarMetrics(
            scoring: scoring,
            playmaking: playmaking,
            rebounding: rebounding,
            defense: defense,
            athleticism: athleticism,
            effort: effort,
            hasGameData: hasData,
            gamesPlayed: gp,
            isComparedToPeers: hasPeerData && hasData
        )
    }
    
    /// Returns normalized values (0-1) for radar chart display
    var normalizedValues: [Double] {
        [scoring, playmaking, rebounding, defense, athleticism, effort].map { $0 / 10.0 }
    }
    
    /// Returns a breakdown of how each axis was computed (for debugging/transparency)
    var blendDescription: String {
        let w = Self.statWeight(gamesPlayed: gamesPlayed)
        if !hasGameData {
            return "100% Coach Evaluation"
        }
        return "Stats: \(Int(w * 100))% | Eval: \(Int((1-w) * 100))% (\(gamesPlayed) games)"
    }

    /// Stats-only metrics for a windowed period (e.g. the export month).
    /// No coach-eval blend — pure performance signal so the overlay reads as
    /// "what they actually did this period."
    /// Athleticism mirrors the lifetime value (no measurable stat) so the polygon
    /// is anchored on that vertex and the rest of the shape shows the delta.
    static func statsOnly(
        from stats: TrainingSessionStats?,
        programContext: ProgramStatsContext?,
        athleticismFromLifetime: Double
    ) -> PerformanceRadarMetrics? {
        guard let stats = stats, stats.hasStats else { return nil }
        let context = programContext ?? .empty
        let hasPeerData = context.studentCount >= 1

        func normalize(_ value: Double, peerMax: Double, fixedMax: Double) -> Double {
            let max = (hasPeerData && peerMax > 0) ? peerMax : fixedMax
            return min((value / max) * 10.0, 10.0)
        }

        let scoring = normalize(stats.ppg, peerMax: context.maxPPG, fixedMax: 15.0)
        let playmaking = normalize(stats.apg, peerMax: context.maxAPG, fixedMax: 5.0)
        let rebounding = normalize(stats.rpg, peerMax: context.maxRPG, fixedMax: 8.0)
        let spgN = normalize(stats.spg, peerMax: context.maxSPG, fixedMax: 3.0)
        let bpgN = normalize(stats.bpg, peerMax: context.maxBPG, fixedMax: 2.0)
        let defense = (spgN + bpgN) / 2.0
        let effort = normalize(stats.efrt, peerMax: context.maxEffort, fixedMax: 7.0)

        return PerformanceRadarMetrics(
            scoring: scoring,
            playmaking: playmaking,
            rebounding: rebounding,
            defense: defense,
            athleticism: athleticismFromLifetime,
            effort: effort,
            hasGameData: true,
            gamesPlayed: stats.gamesPlayed,
            isComparedToPeers: hasPeerData
        )
    }
}

// MARK: - Share Sheet
#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
