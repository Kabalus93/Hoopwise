import SwiftUI

// A coach as a PLAYER (November 2026, Luther: coaches play in scrimmages and
// game prep — "their position when playing 5v5, tendencies … good shooter,
// high IQ, rebounder, all around"). Stored as tagged entries in the coach's
// synced `specializations` list ("player.position:pg", "player.tendency:
// shooter") — no schema change; `coachingSpecializations` is the list
// without them, which is what screens show as specializations.

enum PlayerPosition: String, CaseIterable, Identifiable, Codable {
    case pointGuard = "pg", shootingGuard = "sg", smallForward = "sf", powerForward = "pf", center = "c"

    var id: String { rawValue }
    var short: String { rawValue.uppercased() }

    var name: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .pointGuard: return zh ? "控球后卫" : "Point guard"
        case .shootingGuard: return zh ? "得分后卫" : "Shooting guard"
        case .smallForward: return zh ? "小前锋" : "Small forward"
        case .powerForward: return zh ? "大前锋" : "Power forward"
        case .center: return zh ? "中锋" : "Center"
        }
    }
}

enum PlayerTendency: String, CaseIterable, Identifiable, Codable {
    case shooter, highIQ, rebounder, allAround, defender, playmaker, slasher

    var id: String { rawValue }

    var label: String {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .shooter: return zh ? "投手" : "Shooter"
        case .highIQ: return zh ? "球商高" : "High IQ"
        case .rebounder: return zh ? "篮板手" : "Rebounder"
        case .allAround: return zh ? "全能" : "All-around"
        case .defender: return zh ? "防守者" : "Defender"
        case .playmaker: return zh ? "组织者" : "Playmaker"
        case .slasher: return zh ? "突破手" : "Slasher"
        }
    }

    var icon: String {
        switch self {
        case .shooter: return "scope"
        case .highIQ: return "brain.head.profile"
        case .rebounder: return "arrow.down.to.line"
        case .allAround: return "star.circle"
        case .defender: return "shield.lefthalf.filled"
        case .playmaker: return "arrow.triangle.branch"
        case .slasher: return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .shooter: return .orange
        case .highIQ: return .purple
        case .rebounder: return .pink
        case .allAround: return .yellow
        case .defender: return .teal
        case .playmaker: return .blue
        case .slasher: return .red
        }
    }
}

extension StaffCoach {
    private static let positionTag = "player.position:"
    private static let tendencyTag = "player.tendency:"

    /// Where the coach plays in a 5v5, if set.
    var playerPosition: PlayerPosition? {
        get {
            specializations.lazy
                .filter { $0.hasPrefix(Self.positionTag) }
                .compactMap { PlayerPosition(rawValue: String($0.dropFirst(Self.positionTag.count))) }
                .first
        }
        set {
            specializations.removeAll { $0.hasPrefix(Self.positionTag) }
            if let newValue { specializations.append(Self.positionTag + newValue.rawValue) }
        }
    }

    /// What the coach is known for on the floor, in the order of `allCases`.
    var playerTendencies: [PlayerTendency] {
        get {
            let set = Set(specializations
                .filter { $0.hasPrefix(Self.tendencyTag) }
                .compactMap { PlayerTendency(rawValue: String($0.dropFirst(Self.tendencyTag.count))) })
            return PlayerTendency.allCases.filter(set.contains)
        }
        set {
            specializations.removeAll { $0.hasPrefix(Self.tendencyTag) }
            specializations.append(contentsOf: newValue.map { Self.tendencyTag + $0.rawValue })
        }
    }

    /// The coach's coaching specializations (what they teach), without the
    /// player tags above.
    var coachingSpecializations: [String] {
        get { specializations.filter { !$0.hasPrefix(Self.positionTag) && !$0.hasPrefix(Self.tendencyTag) } }
        set {
            let tags = specializations.filter { $0.hasPrefix(Self.positionTag) || $0.hasPrefix(Self.tendencyTag) }
            specializations = newValue + tags
        }
    }
}
