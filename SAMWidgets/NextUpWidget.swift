import SwiftUI
import WidgetKit

// MARK: - "Next Up" home-screen widget
//
// A dumb renderer of the App Group snapshot — no CloudKit, no SwiftData,
// milliseconds to render. Timeline entries sit exactly at the moments the
// display must change: now, each session start, each session end, midnight.
// Typography carries the design: time is the hero, one accent color,
// no decoration.

// The app's actual identity: iOS blue in light, lime in dark (AppTheme).
let widgetAccent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.80, green: 1.00, blue: 0.00, alpha: 1)   // #CDFF00
        : UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)   // #007AFF
})

struct NextUpEntry: TimelineEntry {
    let date: Date
    let snapshot: NextUpSnapshot?
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        // Gallery previews use believable fake data, never real students.
        if context.isPreview {
            completion(NextUpEntry(date: Date(), snapshot: .preview))
        } else {
            completion(NextUpEntry(date: Date(), snapshot: WidgetShared.loadSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let snapshot = WidgetShared.loadSnapshot()
        let now = Date()
        // Display-change moments: now, every boundary (precomputed windows
        // when present — rollover changes session AND highlight), midnight.
        var moments: Set<Date> = [now]
        if let snapshot {
            if let windows = snapshot.windows {
                for window in windows where window.start > now {
                    moments.insert(window.start)
                }
            }
            for session in snapshot.sessions {
                if session.start > now { moments.insert(session.start) }
                if session.end > now { moments.insert(session.end) }
            }
            // Countdown ticks: refresh every 15 minutes ahead of the next
            // start so "in 1h 14m" stays honest between boundaries.
            if let next = snapshot.featuredSession(at: now), next.start > now {
                var tick = now.addingTimeInterval(15 * 60)
                while tick < next.start && moments.count < 24 {
                    moments.insert(tick)
                    tick = tick.addingTimeInterval(15 * 60)
                }
            }
        }
        if let midnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime) {
            moments.insert(midnight)
        }
        let entries = moments.sorted().map { NextUpEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct NextUpWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var entry: NextUpEntry
    /// Render harness only — the widget itself always uses the environment.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            case .accessoryInline:
                inlineBody
            case .accessoryRectangular:
                rectangularBody
            default:
                smallBody
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: Lock screen accessories

    private var inlineBody: some View {
        Group {
            if let session = featured {
                Text("Next · \(session.start.formatted(date: .omitted, time: .shortened)) \(session.title)")
            } else {
                Text("Rest day")
            }
        }
        .widgetURL(featured.map { URL(string: "hoopwise://session/\($0.id.uuidString)")! })
    }

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let session = featured {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(session.start, format: .dateTime.hour().minute())
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(Self.countdownText(to: session.start, from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rest day").font(.headline)
                Text("No sessions scheduled")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(featured.map { URL(string: "hoopwise://session/\($0.id.uuidString)")! })
    }

    private var window: NextUpWindow? {
        entry.snapshot?.window(at: entry.date)
    }

    private var featured: NextUpSession? {
        window?.session ?? entry.snapshot?.featuredSession(at: entry.date)
    }

    private var highlight: NextUpStudent? {
        window != nil ? window?.highlight : entry.snapshot?.highlight
    }

    // MARK: Small — the next session, nothing else.

    private var smallBody: some View {
        sessionBlock(compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(featured.map { URL(string: "hoopwise://session/\($0.id.uuidString)")! })
    }

    // MARK: Medium — session left, one highlighted student right.

    private var mediumBody: some View {
        HStack(spacing: 14) {
            Link(destination: URL(string:
                "hoopwise://session/\(featured?.id.uuidString ?? "none")")!) {
                sessionBlock(compact: false)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .tint(.primary)
            .foregroundStyle(.primary)
            if let roster = window?.roster, !roster.isEmpty, let session = featured {
                Divider().padding(.vertical, 8)
                RosterClusterView(members: roster,
                                  total: window?.rosterTotal ?? roster.count,
                                  session: session,
                                  highlight: highlight)
                    .frame(width: 124)
            } else if let student = highlight {
                Divider().padding(.vertical, 8)
                Link(destination: URL(string:
                    "hoopwise://athlete/\(student.id.uuidString)")!) {
                    studentBlock(student)
                        .frame(width: 108)
                }
                .tint(.primary)
                .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Session block

    @ViewBuilder
    private func sessionBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            if let session = featured {
                header(for: session)
                // Time is the hero.
                Text(session.start, format: .dateTime.hour().minute())
                    .font(.system(size: compact ? 32 : 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                // Category, not venue: structured "U8 · 竞赛班" from the
                // program record; title only when no program backs it.
                Text(session.structuredLine ?? session.title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(session.structuredLine == nil ? .middle : .tail)
                countdown(for: session)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                restDay
            }
            Spacer(minLength: 0)
            if entry.snapshot?.isStale ?? false {
                Text("Open app to refresh")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func header(for session: NextUpSession) -> some View {
        let isNow = session.start <= entry.date
        let isToday = Calendar.current.isDate(session.start, inSameDayAs: entry.date)
        Text(isNow ? "NOW" : isToday ? "NEXT" : "NEXT · TOMORROW")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(widgetAccent)
            .kerning(0.8)
    }

    @ViewBuilder
    private func countdown(for session: NextUpSession) -> some View {
        Text(Self.countdownText(to: session.start, from: entry.date))
    }

    static func countdownText(to start: Date, from now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 { return "under way" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 5 { return "starting soon" }
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(minutes / 60)h \(minutes % 60)m"
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REST DAY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(widgetAccent)
                .kerning(0.8)
            Text("No sessions\nscheduled")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Student block

    private func studentBlock(_ student: NextUpStudent) -> some View {
        VStack(spacing: 6) {
            avatar(student)
                .frame(width: 52, height: 52)
            VStack(spacing: 1) {
                Text(student.name)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                if let chinese = student.chineseName, chinese != student.name {
                    Text(chinese)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            }
            Text(student.reason.chipLabel)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(widgetAccent.opacity(0.16), in: Capsule())
                .foregroundStyle(widgetAccent)
        }
        .frame(maxHeight: .infinity)
    }

    private func avatar(_ student: NextUpStudent) -> some View {
        WidgetAvatar(student: student, size: 52)
    }
}

// MARK: - Shared avatar (file-based photos, monogram fallback + redaction)

/// The only photo path in the widget process: a pre-downsampled JPEG in the
/// App Group (v2), legacy inline data (v1), else monogram. Redaction
/// collapses the photo to the monogram — the monogram is the redacted form.
struct WidgetAvatar: View {
    let student: NextUpStudent
    let size: CGFloat

    var body: some View {
        ZStack {
            monogram
            if let image = loadPhoto() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .privacySensitive()
            }
        }
        .frame(width: size, height: size)
    }

    private var monogram: some View {
        Circle()
            .fill(widgetAccent.opacity(0.18))
            .overlay(
                Text(student.initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(widgetAccent))
    }

    private func loadPhoto() -> UIImage? {
        if let filename = student.photoFilename,
           let url = WidgetShared.photoURL(filename: filename),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let data = student.avatarJPEG { return UIImage(data: data) }
        return nil
    }
}

// MARK: - Widget declaration

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Up")
        .description("Your next session and one athlete worth a look.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Roster bubble cluster (medium right side)

/// The next session's roster as bubbles, size = attention need. Three tiers
/// only, deterministic slot packing seeded by athlete id — stable between
/// refreshes. The whole cluster is one Link to the session; only the labeled
/// largest bubble links to its profile.
struct RosterClusterView: View {
    let members: [NextUpRosterMember]
    let total: Int
    let session: NextUpSession
    let highlight: NextUpStudent?

    private static let slots: [CGPoint] = [
        CGPoint(x: 34, y: 26), CGPoint(x: 78, y: 18), CGPoint(x: 106, y: 44),
        CGPoint(x: 16, y: 58), CGPoint(x: 58, y: 52), CGPoint(x: 96, y: 74),
        CGPoint(x: 32, y: 84), CGPoint(x: 70, y: 88),
    ]
    private static let tierSizes: [CGFloat] = [38, 28, 22]

    /// The Mason slot, earned: the first attention-tier member, else the
    /// window highlight if present in the cluster.
    private var labeled: NextUpRosterMember? {
        members.first { $0.tier == 0 }
            ?? members.first { $0.id == highlight?.id }
    }

    var body: some View {
        VStack(spacing: 3) {
            Link(destination: URL(string: "hoopwise://session/\(session.id.uuidString)")!) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        bubble(member, slot: Self.slots[index % Self.slots.count])
                    }
                    if total > members.count {
                        Text("+\(total - members.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                            .position(x: 108, y: 92)
                    }
                }
                .frame(width: 124, height: 100)
                .contentShape(Rectangle())
            }
            if let labeled {
                Link(destination: URL(string: "hoopwise://athlete/\(labeled.id.uuidString)")!) {
                    VStack(spacing: 1) {
                        Text(labeled.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .privacySensitive()
                        if let reason = labeled.reason {
                            Text(reason.chipLabel)
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(widgetAccent.opacity(0.16), in: Capsule())
                                .foregroundStyle(widgetAccent)
                        }
                    }
                }
                .tint(.primary)
            }
        }
    }

    private func bubble(_ member: NextUpRosterMember, slot: CGPoint) -> some View {
        let size = Self.tierSizes[min(max(member.tier, 0), 2)]
        // Deterministic jitter seeded by athlete id — no reshuffling.
        let seed = member.id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let dx = CGFloat(seed % 7) - 3
        let dy = CGFloat((seed / 7) % 7) - 3
        return WidgetAvatar(
            student: NextUpStudent(id: member.id, name: member.name, chineseName: nil,
                                   initials: member.initials, reason: member.reason ?? .streak,
                                   photoFilename: member.photoFilename),
            size: size)
            .overlay(Circle().stroke(member.tier == 0 ? widgetAccent.opacity(0.7) : .clear,
                                     lineWidth: 1.4))
            .position(x: slot.x + dx, y: slot.y + dy)
    }
}

// MARK: - Gallery preview data (never real students)

extension NextUpSnapshot {
    static var preview: NextUpSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: 135, to: Date())!
        return NextUpSnapshot(
            generatedAt: Date(),
            sessions: [
                NextUpSession(id: UUID(), title: "U14 Training",
                              start: start,
                              end: calendar.date(byAdding: .minute, value: 90, to: start)!,
                              location: "Hezhuang Court"),
            ],
            highlight: NextUpStudent(id: UUID(), name: "Wang Yi",
                                     chineseName: "王一",
                                     initials: "WY",
                                     reason: .streak,
                                     avatarJPEG: nil))
    }
}
