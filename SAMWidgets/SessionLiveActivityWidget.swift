import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Session Live Activity Attributes (duplicated for widget extension)
struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedMinutes: Int
        var totalMinutes: Int
        var currentPhase: SessionPhase
        var currentDrillName: String?
        var progress: Double
        var attendeeCount: Int
    }
    
    var sessionId: UUID
    var sessionTitle: String
    var programName: String
    var startTime: Date
    var endTime: Date
    var location: String?
    var accentColorHex: String
}

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
}

// MARK: - Live Activity Widget
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            SessionLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.currentPhase.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: context.attributes.accentColorHex))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.currentPhase.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            if let drill = context.state.currentDrillName {
                                Text(drill)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.elapsedMinutes)/\(context.state.totalMinutes)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("min")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 6)
                                
                                Capsule()
                                    .fill(Color(hex: context.attributes.accentColorHex))
                                    .frame(width: geo.size.width * context.state.progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        HStack {
                            Text(context.attributes.sessionTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10))
                                Text("\(context.state.attendeeCount)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
            } compactLeading: {
                Image(systemName: context.state.currentPhase.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: context.attributes.accentColorHex))
            } compactTrailing: {
                Text("\(context.state.totalMinutes - context.state.elapsedMinutes)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: context.attributes.accentColorHex))
            } minimal: {
                Image(systemName: context.state.currentPhase.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: context.attributes.accentColorHex))
            }
        }
    }
}

// MARK: - Lock Screen View
struct SessionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    // Session type icon
                    ZStack {
                        Circle()
                            .fill(Color(hex: context.attributes.accentColorHex).opacity(0.2))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "figure.basketball")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: context.attributes.accentColorHex))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sessionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(context.attributes.programName)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Time remaining
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(context.state.totalMinutes - context.state.elapsedMinutes)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("min left")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 8)
                        
                        // Progress
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: context.attributes.accentColorHex),
                                        Color(hex: context.attributes.accentColorHex).opacity(0.8)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * context.state.progress, height: 8)
                    }
                }
                .frame(height: 8)
                
                // Phase markers
                HStack {
                    PhaseMarker(phase: .warmup, isActive: context.state.currentPhase == .warmup, accentColor: context.attributes.accentColorHex)
                    Spacer()
                    PhaseMarker(phase: .skills, isActive: context.state.currentPhase == .skills, accentColor: context.attributes.accentColorHex)
                    Spacer()
                    PhaseMarker(phase: .game, isActive: context.state.currentPhase == .game, accentColor: context.attributes.accentColorHex)
                }
            }
            
            // Current activity
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: context.state.currentPhase.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: context.attributes.accentColorHex))
                    
                    Text(context.state.currentPhase.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let drill = context.state.currentDrillName {
                        Text("•")
                            .foregroundColor(.white.opacity(0.5))
                        Text(drill)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Attendee count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                    Text("\(context.state.attendeeCount)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: context.attributes.accentColorHex).opacity(0.3),
                    Color.black.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Phase Marker
struct PhaseMarker: View {
    let phase: SessionPhase
    let isActive: Bool
    let accentColor: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: phase.icon)
                .font(.system(size: 10, weight: isActive ? .bold : .regular))
            Text(phase.displayName)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
        }
        .foregroundColor(isActive ? Color(hex: accentColor) : .white.opacity(0.5))
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 107, 53) // Default orange
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
