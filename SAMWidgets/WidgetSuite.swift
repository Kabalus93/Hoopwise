import SwiftUI
import WidgetKit

// MARK: - The widget suite: Today, Attention, Cadence
//
// All read the same snapshot through the same provider; each widget has
// exactly one job. Restraint rules: one accent, no rings or gauges, type
// hierarchy does the communicating, every tap lands somewhere specific.

private let agendaTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"      // fixed 24h: unambiguous, fixed-width
    return formatter
}()

// MARK: - Today — the day at a glance

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var entry: NextUpEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var agenda: [NextUpSession] {
        entry.snapshot?.agendaToday(at: entry.date) ?? []
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            case .systemLarge:
                agendaBody(maxRows: 10, roomy: true)
            default:
                agendaBody(maxRows: 4, roomy: false)
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agendaBody(maxRows: Int, roomy: Bool) -> some View {
        let sessions = agenda
        VStack(alignment: .leading, spacing: roomy ? 10 : 6) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(widgetAccent)
                    .kerning(0.8)
                Spacer()
                if entry.snapshot?.isStale ?? false {
                    Text("Open app to refresh")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if sessions.isEmpty {
                Spacer()
                Text("Rest day")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No sessions scheduled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ForEach(sessions.prefix(maxRows)) { session in
                    Link(destination: URL(string: "hoopwise://session/\(session.id.uuidString)")!) {
                        agendaRow(session, roomy: roomy)
                    }
                    .tint(.primary)
                }
                if sessions.count > maxRows {
                    Text("+\(sessions.count - maxRows) later")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 54)
                }
                Spacer(minLength: 0)
                if roomy, let preview = tomorrowPreview {
                    Divider()
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func agendaRow(_ session: NextUpSession, roomy: Bool) -> some View {
        let finished = session.end <= entry.date
        let isFeatured = entry.snapshot?.featuredSession(at: entry.date)?.id == session.id
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(agendaTimeFormatter.string(from: session.start))
                .font(.system(size: roomy ? 16 : 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(finished ? AnyShapeStyle(.tertiary)
                                 : isFeatured ? AnyShapeStyle(widgetAccent)
                                 : AnyShapeStyle(.secondary))
                .frame(width: roomy ? 52 : 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(finished ? .secondary : .primary)
                    .lineLimit(roomy ? 2 : 1)          // 中文 titles wrap in large only
                    .truncationMode(.tail)
                if roomy, let program = session.programLine {
                    Text(program)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let location = session.location, !location.isEmpty, !finished {
                Text(location)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)           // location gives way before title
                    .frame(maxWidth: 72, alignment: .trailing)
            }
            if finished {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            } else if let roster = session.rosterCount, roster > 0 {
                Text("\(roster)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(finished ? 0.6 : 1)
    }

    /// After the last session ends, preview tomorrow's first.
    private var tomorrowPreview: String? {
        guard agenda.allSatisfy({ $0.end <= entry.date }),
              let first = entry.snapshot?.agendaTomorrow(at: entry.date).first
        else { return nil }
        return "Tomorrow · \(agendaTimeFormatter.string(from: first.start)) \(first.title)"
    }

    // MARK: Circular — remaining count, a plain numeral.

    private var circularBody: some View {
        let remaining = agenda.filter { $0.end > entry.date }.count
        return VStack(spacing: 0) {
            Text("\(remaining)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(remaining == 1 ? "session" : "sessions")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "hoopwise://sessions")!)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.todayKind, provider: NextUpProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("The whole day's sessions at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular])
    }
}

// MARK: - Attention — who needs you

struct AttentionWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var entry: NextUpEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var students: [NextUpStudent] { entry.snapshot?.attentionList ?? [] }

    var body: some View {
        Group {
            if family == .systemSmall { smallBody } else { mediumBody }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ATTENTION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(widgetAccent)
                .kerning(0.8)
            if let top = students.first {
                Text("\(students.count)")
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(students.count == 1 ? "needs you" : "need you")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(top.name)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .privacySensitive()
                chip(top.reason)
            } else {
                Spacer(minLength: 0)
                allSteady
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(students.first.map {
            URL(string: "hoopwise://athlete/\($0.id.uuidString)")!
        } ?? URL(string: "hoopwise://sessions")!)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ATTENTION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(widgetAccent)
                .kerning(0.8)
            if students.isEmpty {
                Spacer()
                allSteady
                Spacer()
            } else {
                ForEach(students) { student in
                    Link(destination: URL(string: "hoopwise://athlete/\(student.id.uuidString)")!) {
                        HStack(spacing: 9) {
                            WidgetAvatar(student: student, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(student.name)
                                    .font(.system(.footnote, weight: .semibold))
                                    .lineLimit(1)
                                    .privacySensitive()
                                if let chinese = student.chineseName, chinese != student.name {
                                    Text(chinese)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .privacySensitive()
                                }
                            }
                            Spacer(minLength: 4)
                            chip(student.reason)
                        }
                    }
                    .tint(.primary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var allSteady: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All steady")
                .font(.system(.title3, design: .rounded, weight: .medium))
            if let percent = entry.snapshot?.weeklyAttendancePercent {
                Text("\(percent)% attendance this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing needs you right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ reason: NextUpStudent.Reason) -> some View {
        Text(reason.chipLabel)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(widgetAccent.opacity(0.16), in: Capsule())
            .foregroundStyle(widgetAccent)
    }
}

struct AttentionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.attentionKind, provider: NextUpProvider()) { entry in
            AttentionWidgetView(entry: entry)
        }
        .configurationDisplayName("Attention")
        .description("Athletes who need a look — notes, attendance, bundles.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Cadence — the week's shape

struct CadenceWidgetView: View {
    var entry: NextUpEntry
    var familyOverride: WidgetFamily?

    private var week: [WeekCell] { entry.snapshot?.week(at: entry.date) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(widgetAccent)
                .kerning(0.8)
            HStack(spacing: 6) {
                ForEach(week, id: \.date) { cell in
                    dayColumn(cell)
                }
            }
            .frame(maxHeight: .infinity)
            Text(bottomLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .widgetURL(URL(string: "hoopwise://sessions")!)
    }

    private func dayColumn(_ cell: WeekCell) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(cell.date, inSameDayAs: entry.date)
        let letter = cell.date.formatted(.dateTime.weekday(.narrow))
        return VStack(spacing: 4) {
            Text(letter)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isToday ? widgetAccent : .secondary)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < min(cell.count, 3)
                              ? widgetAccent : Color.primary.opacity(0.08))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isToday ? widgetAccent.opacity(0.6) : Color.clear, lineWidth: 1.2))
    }

    private var bottomLine: String {
        let today = entry.snapshot?.agendaToday(at: entry.date) ?? []
        let remaining = today.filter { $0.end > entry.date }.count
        if remaining > 0 {
            return remaining == 1 ? "1 more today" : "\(remaining) more today"
        }
        if let next = entry.snapshot?.featuredSession(at: entry.date) {
            let day = next.start.formatted(.dateTime.weekday(.abbreviated))
            return "Next · \(day) \(agendaTimeFormatter.string(from: next.start)) \(next.title)"
        }
        return "Nothing scheduled"
    }
}

struct CadenceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.cadenceKind, provider: NextUpProvider()) { entry in
            CadenceWidgetView(entry: entry)
        }
        .configurationDisplayName("Cadence")
        .description("The shape of your training week.")
        .supportedFamilies([.systemMedium])
    }
}
