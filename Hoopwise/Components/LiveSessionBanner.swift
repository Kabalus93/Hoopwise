import SwiftUI
import Combine

// MARK: - Live Session Banner
/// An in-app banner that displays when a session is currently in progress
/// Matches the style of the lock screen Live Activity
struct LiveSessionBanner: View {
    let session: SessionEvent
    let programName: String
    let programColor: Color
    var onTap: (() -> Void)?
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var elapsedMinutes: Int {
        max(0, Int(currentTime.timeIntervalSince(session.startTime) / 60))
    }
    
    private var totalMinutes: Int {
        Int(session.endTime.timeIntervalSince(session.startTime) / 60)
    }
    
    private var remainingMinutes: Int {
        max(0, totalMinutes - elapsedMinutes)
    }
    
    private var progress: Double {
        guard totalMinutes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(elapsedMinutes) / Double(totalMinutes)))
    }
    
    private var currentPhase: (name: String, icon: String) {
        let curriculum = session.curriculum
        let warmupEnd = curriculum.warmupMinutes
        let skillsEnd = warmupEnd + curriculum.skillsMinutes
        let gameEnd = skillsEnd + curriculum.gameMinutes
        
        if elapsedMinutes < warmupEnd {
            return ("Warmup", "flame.fill")
        } else if elapsedMinutes < skillsEnd {
            return ("Skills", "figure.basketball")
        } else if elapsedMinutes < gameEnd {
            return ("Game", "sportscourt.fill")
        } else {
            return ("Cooldown", "wind")
        }
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: 12) {
                // Header
                HStack {
                    // Live indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(Color.red.opacity(0.5))
                                    .frame(width: 16, height: 16)
                                    .scaleEffect(1.0)
                                    .opacity(0.5)
                            )
                        
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    // Time remaining
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                        Text("\(remainingMinutes) min left")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                
                // Session info
                HStack(spacing: 12) {
                    // Session icon
                    ZStack {
                        Circle()
                            .fill(programColor.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "figure.basketball")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(programName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    // Large countdown
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(remainingMinutes)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("min")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // Progress bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 6)
                            
                            // Progress
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [programColor, programColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    // Phase indicators
                    HStack {
                        phaseIndicator(name: "Warmup", icon: "flame.fill", isActive: currentPhase.name == "Warmup")
                        Spacer()
                        phaseIndicator(name: "Skills", icon: "figure.basketball", isActive: currentPhase.name == "Skills")
                        Spacer()
                        phaseIndicator(name: "Game", icon: "sportscourt.fill", isActive: currentPhase.name == "Game")
                    }
                }
                
                // Current activity
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: currentPhase.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(programColor)
                        
                        Text(currentPhase.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Attendee count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(session.actualAttendeeIds.count) attending")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                programColor.opacity(0.3),
                                Color.black.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(programColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func phaseIndicator(name: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: isActive ? .bold : .regular))
            Text(name)
                .font(.system(size: 9, weight: isActive ? .semibold : .regular))
        }
        .foregroundColor(isActive ? programColor : .white.opacity(0.4))
    }
}

// MARK: - Compact Version for smaller spaces
struct LiveSessionBannerCompact: View {
    let session: SessionEvent
    let programColor: Color
    var onTap: (() -> Void)?
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var remainingMinutes: Int {
        let elapsed = currentTime.timeIntervalSince(session.startTime)
        let total = session.endTime.timeIntervalSince(session.startTime)
        return max(0, Int((total - elapsed) / 60))
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                // Live dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(remainingMinutes) min")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(programColor)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(programColor.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
            LiveSessionBanner(
                session: SessionEvent(
                    title: "U12 Skills Training",
                    date: Date(),
                    startTime: Date().addingTimeInterval(-20 * 60),
                    endTime: Date().addingTimeInterval(40 * 60),
                    curriculum: SessionCurriculum(warmupMinutes: 10, skillsMinutes: 35, gameMinutes: 15),
                    actualAttendeeIds: [UUID(), UUID(), UUID()]
                ),
                programName: "Elite Youth Program",
                programColor: Color.orange
            )
            .padding(.horizontal, 20)
            
            LiveSessionBannerCompact(
                session: SessionEvent(
                    title: "U12 Skills Training",
                    date: Date(),
                    startTime: Date().addingTimeInterval(-20 * 60),
                    endTime: Date().addingTimeInterval(40 * 60)
                ),
                programColor: Color.orange
            )
            .padding(.horizontal, 20)
        }
    }
}
