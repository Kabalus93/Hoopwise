import WidgetKit
import SwiftUI
import ActivityKit

// `SessionActivityAttributes` and `SessionPhase` are declared in
// `Hoopwise/Models/SessionActivityAttributes.swift`. That file must be a
// member of BOTH the Hoopwise app target AND the SAMWidgets extension target
// so the same Swift type identity is shared across processes (ActivityKit
// matches `Activity.request(attributes:)` to widget configurations by
// fully-qualified type, including module).

// MARK: - Live Activity Widget
/// Live Activity / Dynamic Island for an in-progress session.
///
/// Progress and time-remaining are driven by `ProgressView(timerInterval:)`
/// and `Text(timerInterval:)`, both keyed to the immutable
/// `attributes.startTime ... attributes.endTime` range. iOS ticks them
/// locally every frame on lock screen and every second on Dynamic Island —
/// the manager only pushes state updates for things that *change* during
/// the run (current phase, drill name, attendee count), not for time.
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        // Two moments only (October 2026, Luther): the 10 minutes before a
        // class count down to its start, and the class itself counts down
        // what is left. The manager sets the stale date to the start, so iOS
        // redraws there and `ActivityClock` flips from one to the other.
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            let accent = Color(hex: context.attributes.accentColorHex)
            let clock = ActivityClock(context.attributes)
            let interval = clock.interval

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.currentPhase.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(accent)

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
                        Text(timerInterval: interval, countsDown: true)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .multilineTextAlignment(.trailing)
                        Text(clock.caption)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(timerInterval: interval, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(accent)

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
                    .foregroundColor(accent)
            } compactTrailing: {
                // Live-ticking countdown — no state pushes needed.
                Text(timerInterval: interval, countsDown: true)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accent)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.currentPhase.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
        }
    }
}

// MARK: - Lock Screen View
struct SessionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        let accent = Color(hex: context.attributes.accentColorHex)
        let clock = ActivityClock(context.attributes)
        let interval = clock.interval

        return VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.2))
                            .frame(width: 36, height: 36)

                        Image(systemName: "figure.basketball")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accent)
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

                VStack(alignment: .trailing, spacing: 2) {
                    // Live-ticking countdown timer. iOS updates this every
                    // second on the lock screen with no state pushes.
                    Text(timerInterval: interval, countsDown: true)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                    Text(clock.caption)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            VStack(spacing: 6) {
                // Smoothly animated bar — fills proportionally to time
                // elapsed between startTime and endTime, no pushes needed.
                ProgressView(timerInterval: interval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(accent)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())

                HStack {
                    PhaseMarker(phase: .warmup, isActive: context.state.currentPhase == .warmup, accentColor: context.attributes.accentColorHex)
                    Spacer()
                    PhaseMarker(phase: .skills, isActive: context.state.currentPhase == .skills, accentColor: context.attributes.accentColorHex)
                    Spacer()
                    PhaseMarker(phase: .game, isActive: context.state.currentPhase == .game, accentColor: context.attributes.accentColorHex)
                }
            }

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

// MARK: - Clock
/// What the timers count, decided at render time: before the start, the
/// (up to) 10 minutes to it; from the start, the time left in the class.
struct ActivityClock {
    let interval: ClosedRange<Date>
    let caption: String

    init(_ attributes: SessionActivityAttributes, now: Date = Date()) {
        let start = attributes.startTime
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        if now < start {
            interval = min(now, start.addingTimeInterval(-600))...start
            caption = isChinese ? "后开始" : "starts in"
        } else {
            interval = start...max(start, attributes.endTime)
            caption = isChinese ? "剩余" : "remaining"
        }
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

// MARK: - Color Hex Extension
// The widget extension is its own module and needs its own copy of the
// hex-string Color initializer. Don't share with the app's Color extension
// to avoid an inadvertent module dependency.
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 107, 53)
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
