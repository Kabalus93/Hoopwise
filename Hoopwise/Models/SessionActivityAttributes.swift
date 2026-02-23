import Foundation
#if os(iOS)
import ActivityKit
#endif

// MARK: - Session Phase (available on all platforms)
enum SessionPhase: String, Codable, Hashable {
    case warmup = "Warmup"
    case skills = "Skills"
    case game = "Game"
    case cooldown = "Cooldown"
    case completed = "Completed"
    
    var icon: String {
        switch self {
        case .warmup: return "flame.fill"
        case .skills: return "figure.basketball"
        case .game: return "sportscourt.fill"
        case .cooldown: return "wind"
        case .completed: return "checkmark.circle.fill"
        }
    }
    
    var displayName: String { rawValue }
    
    var chineseDisplayName: String {
        switch self {
        case .warmup: return "热身"
        case .skills: return "技能训练"
        case .game: return "比赛"
        case .cooldown: return "放松"
        case .completed: return "已完成"
        }
    }
}

// MARK: - Session Live Activity Attributes (iOS only)
// This struct is only available on iOS where ActivityKit is supported
#if os(iOS)
struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedMinutes: Int
        var totalMinutes: Int
        var currentPhase: SessionPhase
        var currentDrillName: String?
        var progress: Double  // 0.0 to 1.0
        var attendeeCount: Int
    }
    
    // Fixed attributes (don't change during activity)
    var sessionId: UUID
    var sessionTitle: String
    var programName: String
    var startTime: Date
    var endTime: Date
    var location: String?
    var accentColorHex: String
}
#endif
