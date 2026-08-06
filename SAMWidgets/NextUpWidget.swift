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
private let accent = Color(uiColor: UIColor { traits in
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
        // Display-change moments: now, every boundary, midnight.
        var moments: Set<Date> = [now]
        if let snapshot {
            for session in snapshot.sessions {
                if session.start > now { moments.insert(session.start) }
                if session.end > now { moments.insert(session.end) }
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
            default:
                smallBody
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private var featured: NextUpSession? {
        entry.snapshot?.featuredSession(at: entry.date)
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
            if let student = entry.snapshot?.highlight {
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
                Text(session.title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let location = session.location, !location.isEmpty {
                        Text(location).lineLimit(1)
                        Text("·")
                    }
                    countdown(for: session)
                }
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
            .foregroundStyle(accent)
            .kerning(0.8)
    }

    @ViewBuilder
    private func countdown(for session: NextUpSession) -> some View {
        if session.start <= entry.date {
            Text("under way")
        } else {
            // Live countdown: relative style self-updates between entries.
            Text("in ") + Text(session.start, style: .relative)
        }
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REST DAY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
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
                .background(accent.opacity(0.16), in: Capsule())
                .foregroundStyle(accent)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func avatar(_ student: NextUpStudent) -> some View {
        if let data = student.avatarJPEG, let image = UIImage(data: data) {
            ZStack {
                // Redacted mode collapses the photo to the monogram — the
                // photo is privacy-sensitive, the monogram is its stand-in.
                monogram(student.initials)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .privacySensitive()
            }
        } else {
            monogram(student.initials)
        }
    }

    private func monogram(_ initials: String) -> some View {
        Circle()
            .fill(accent.opacity(0.18))
            .overlay(
                Text(initials)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(accent))
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
