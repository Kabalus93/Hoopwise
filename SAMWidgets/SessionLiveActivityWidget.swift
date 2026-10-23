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
            let clock = ActivityClock(context.attributes)
            let accent = ActivityCardStyle(isUpcoming: clock.isUpcoming).accent
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
/// The lock-screen card (October 2026, Luther's design): a deep gradient per
/// moment, the brand line in tracked caps, ONE huge countdown, what it counts
/// to in bold, and the class's times bottom-right. Starting soon is navy →
/// blue → cyan; live is court-green → navy → blue.
struct SessionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        let clock = ActivityClock(context.attributes)
        let style = ActivityCardStyle(isUpcoming: clock.isUpcoming)

        return VStack(alignment: .leading, spacing: 0) {
            Text(clock.headline)
                .font(.system(size: 13, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.92))

            Text(timerInterval: clock.interval, countsDown: true)
                .font(.system(size: 60, weight: .heavy))
                .monospacedDigit()
                .kerning(-1.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)

            HStack(alignment: .lastTextBaseline) {
                Text(clock.subtitle(for: className))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 12)
                Text(clock.detail)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
        .activityBackgroundTint(style.base)
        .activitySystemActionForegroundColor(.white)
    }

    private var className: String {
        let program = context.attributes.programName.trimmingCharacters(in: .whitespaces)
        return program.isEmpty ? context.attributes.sessionTitle : program
    }
}

/// The two moments' colours, shared by the card and the Dynamic Island.
struct ActivityCardStyle {
    let isUpcoming: Bool

    /// Deepest tone — what the system shows behind the card's edges.
    var base: Color { isUpcoming ? Color(hex: "0A1A5C") : Color(hex: "072B3A") }
    /// The bright end, used as the Dynamic Island accent.
    var accent: Color { isUpcoming ? Color(hex: "35C8FF") : Color(hex: "2FD39A") }

    var background: some View {
        ZStack {
            if isUpcoming {
                LinearGradient(colors: [Color(hex: "081650"), Color(hex: "1236C8"), Color(hex: "1E7BFF")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(hex: "22D3FF").opacity(0.85), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 220)
            } else {
                LinearGradient(colors: [Color(hex: "0B4F4A"), Color(hex: "0A2F7A"), Color(hex: "1446E0")],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
                RadialGradient(colors: [Color(hex: "0E8A6A").opacity(0.7), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 200)
                RadialGradient(colors: [Color(hex: "081A5A").opacity(0.6), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 180)
            }
        }
    }
}

// MARK: - Clock
/// What the timers count, decided at render time: before the start, the
/// (up to) 10 minutes to it; from the start, the time left in the class.
struct ActivityClock {
    let interval: ClosedRange<Date>
    let caption: String
    let isUpcoming: Bool
    let isChinese: Bool
    let start: Date
    let end: Date

    init(_ attributes: SessionActivityAttributes, now: Date = Date()) {
        start = attributes.startTime
        end = max(attributes.startTime, attributes.endTime)
        isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        isUpcoming = now < start
        if isUpcoming {
            interval = min(now, start.addingTimeInterval(-600))...start
            caption = isChinese ? "后开始" : "starts in"
        } else {
            interval = start...end
            caption = isChinese ? "剩余" : "remaining"
        }
    }

    var headline: String {
        if isChinese { return isUpcoming ? "HOOPWISE · 即将上课" : "HOOPWISE · 正在上课" }
        return isUpcoming ? "HOOPWISE · STARTING SOON" : "HOOPWISE · SESSION LIVE"
    }

    func subtitle(for name: String) -> String {
        if isChinese { return isUpcoming ? "距 \(name) 开始" : "\(name) 剩余时间" }
        return isUpcoming ? "until \(name) starts" : "remaining in \(name)"
    }

    /// "18:30–19:30" before the class, "Ends at 19:30" during it.
    var detail: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if isUpcoming { return "\(f.string(from: start))–\(f.string(from: end))" }
        return isChinese ? "\(f.string(from: end)) 结束" : "Ends at \(f.string(from: end))"
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
