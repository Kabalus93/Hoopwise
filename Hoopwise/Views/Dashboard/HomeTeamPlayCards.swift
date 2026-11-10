import SwiftData
import SwiftUI

// Home's TEAM and PLAY cards (November 2026, Luther: "a Teams card — the team
// pinned on the home screen, bubbles of players and a couple of useful team
// stats … and a card for a play I am working on or just finished. Each card
// has its own design for what it shows, in the same language as what
// exists"). Both are glass cards with a small monospaced caps label, like
// Today's athletes and the briefing.

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

// MARK: - Team

/// What Home says about a pinned team, worked out once per render.
@MainActor
struct HomeTeamSummary {
    let team: Team
    let members: [Student]
    let nextPractice: SessionEvent?
    /// Present ÷ expected over the last (up to) four practices that happened
    /// and had a roll call.
    let attendance: (present: Int, expected: Int, practices: Int)
    let focus: [SessionPlayRef]
    let withoutRole: [Student]

    init(team: Team, dataManager: DataManager, now: Date = .now) {
        self.team = team
        members = TeamRoster(team: team, dataManager: dataManager).everyone(dataManager)
        let practices = dataManager.sessionEvents
            .filter { $0.curriculum.teamId == team.id && !SessionLifecycle.didNotHappen($0) }
        nextPractice = practices
            .filter { $0.endTime > now }
            .min { $0.startTime < $1.startTime }
        let recent = practices
            .filter { $0.startTime < now && !$0.actualAttendeeIds.isEmpty }
            .sorted { $0.startTime > $1.startTime }
            .prefix(4)
        var present = 0, expected = 0
        for session in recent {
            let roster = Set(session.attendeeIds + session.curriculum.coachIds)
            present += session.actualAttendeeIds.count
            expected += max(roster.count, session.actualAttendeeIds.count)
        }
        attendance = (present, expected, recent.count)
        let book = team.playbook
        focus = book.focusPlays
        let plays = focus
        withoutRole = plays.isEmpty ? [] : members.filter { book.parts(of: $0.id, in: plays).isEmpty }
    }
}

struct HomeTeamCard: View {
    let summary: HomeTeamSummary
    var onOpen: () -> Void
    var onSelectStudent: (Student) -> Void
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 360

    private var colour: Color { Color(hex: summary.team.colorHex) }

    var body: some View {
        let team = summary.team
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text(isChinese ? "球队" : "TEAM").font(.caption2.weight(.bold)).monospaced()
                        } icon: {
                            Image(systemName: "pin.fill").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            TeamBadge(team: team, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(team.name).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(isChinese ? "\(summary.members.count) 名队员" : "\(summary.members.count) players")
                                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.team.open")

                if !summary.members.isEmpty {
                    TodaysRosterCluster(
                        members: TodaysRosterCluster.members(hero: nil, students: summary.members, sessions: dataManager.sessionEvents),
                        total: summary.members.count,
                        // At most ~34 % of the card, so the name keeps its room.
                        scale: min(sizeClass == .regular ? 1.3 : 1.1, max(0.8, width * 0.34 / 124)),
                        onSelect: { student in
                            if dataManager.students.contains(where: { $0.id == student.id }) { onSelectStudent(student) } else { onOpen() }
                        },
                        onMore: onOpen)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(alignment: .top, spacing: 10) {
                stat(value: nextValue, caption: isChinese ? "下次训练" : "next practice", tint: colour)
                stat(value: attendanceValue, caption: attendanceCaption, tint: attendanceTint)
                stat(value: focusValue, caption: isChinese ? "当前重点" : "focus", tint: .primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if let line = nudge {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Image(systemName: line.icon).font(.footnote).foregroundStyle(line.tint)
                        Text(line.text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer().frame(height: 18)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [colour.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func stat(value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    private var nextValue: String {
        guard let session = summary.nextPractice else { return "—" }
        if session.startTime <= .now { return isChinese ? "进行中" : "Now" }
        let time = session.startTime.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(session.startTime) { return (isChinese ? "今天 " : "Today ") + time }
        if Calendar.current.isDateInTomorrow(session.startTime) { return (isChinese ? "明天 " : "Tomorrow ") + time }
        return session.startTime.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    private var attendanceValue: String {
        let a = summary.attendance
        guard a.expected > 0 else { return "—" }
        return "\(Int((Double(a.present) / Double(a.expected) * 100).rounded()))%"
    }

    private var attendanceCaption: String {
        let n = summary.attendance.practices
        if n == 0 { return isChinese ? "出勤" : "attendance" }
        return isChinese ? "近 \(n) 次出勤" : (n == 1 ? "last practice" : "last \(n) practices")
    }

    private var attendanceTint: Color {
        let a = summary.attendance
        guard a.expected > 0 else { return .secondary }
        let rate = Double(a.present) / Double(a.expected)
        return rate >= 0.8 ? .green : rate >= 0.6 ? .orange : .red
    }

    private var focusValue: String {
        guard let first = summary.focus.first else { return "—" }
        return summary.focus.count > 1 ? "\(first.name) +\(summary.focus.count - 1)" : first.name
    }

    /// One line worth acting on: who has no role in the focus plays, else
    /// that no focus is set.
    private var nudge: (icon: String, text: String, tint: Color)? {
        if summary.focus.isEmpty {
            return ("scope", isChinese ? "还没有当前重点——选出要练的战术，训练计划就能从中生成。"
                                       : "No focus plays yet — pick them and practices build their plan from them.", .orange)
        }
        guard !summary.withoutRole.isEmpty else { return nil }
        let names = summary.withoutRole.prefix(3).map(\.primaryDisplayName).joined(separator: ", ")
        let more = summary.withoutRole.count > 3 ? (isChinese ? " 等 \(summary.withoutRole.count) 人" : " +\(summary.withoutRole.count - 3)") : ""
        return ("person.fill.questionmark",
                (isChinese ? "在重点战术里没有号位：" : "No role in the focus plays: ") + names + more, .orange)
    }
}

// MARK: - Play

/// The play being worked on (edited in the last week) or last studied: the
/// court across the top — it is the play's face — then what it is, how far it
/// has got (steps, wrinkles, variations) and where it is used (upcoming
/// plans, team playbooks).
struct HomePlayCard: View {
    let play: JournalPlay
    let mark: PlayActivity.Mark
    let edited: Bool
    var onOpen: () -> Void
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                court
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label {
                            Text(edited ? (isChinese ? "正在做的战术" : "WORKING ON") : (isChinese ? "最近看过" : "LAST STUDIED"))
                                .font(.caption2.weight(.bold)).monospaced()
                        } icon: {
                            Image(systemName: edited ? "pencil.and.scribble" : "eye").font(.caption)
                        }
                        .foregroundStyle(edited ? Color.accentColor : .secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(mark.date, format: .relative(presentation: .named))
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(verbatim: play.name).font(.title2.bold()).lineLimit(2).multilineTextAlignment(.leading)
                    Text(verbatim: jp(play.category.label)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        count(steps, isChinese ? "步" : (steps == 1 ? "step" : "steps"))
                        if wrinkles > 0 { count(wrinkles, isChinese ? "个变化" : (wrinkles == 1 ? "wrinkle" : "wrinkles")) }
                        if variations > 0 { count(variations, isChinese ? "个变体" : (variations == 1 ? "variation" : "variations")) }
                    }
                    .padding(.top, 2)
                    if let usedIn {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").font(.caption)
                            Text(usedIn).font(.footnote).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .clipShape(.rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityIdentifier("home.play")
    }

    private var court: some View {
        JournalPlayDiagramView(diagram: play.conceptPart?.sortedSteps.first?.diagram ?? JournalPlayDiagram(),
                               court: play.court, compact: true)
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: play.court == .full ? 150 : 180)
            .background(JPalette.background)
    }

    private func count(_ n: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(n)").font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var steps: Int { play.conceptPart?.sortedSteps.count ?? 0 }
    private var wrinkles: Int { play.parts(.wrinkle).count }
    private var variations: Int { play.parts(.variation).count }

    /// "In 2 upcoming plans · Kuxun runs it".
    private var usedIn: String? {
        let key = play.planRef.key
        let upcoming = dataManager.sessionEvents.filter { session in
            session.startTime > .now && !SessionLifecycle.didNotHappen(session)
                && session.curriculum.plays.contains { play.isNamed(by: $0) || $0.key == key }
        }.count
        let teams = dataManager.teams.filter { team in team.playbook.allPlays.contains { $0.ref.key == key } }.map(\.name)
        var parts: [String] = []
        if upcoming > 0 {
            parts.append(isChinese ? "在 \(upcoming) 节即将到来的课程计划里" : (upcoming == 1 ? "In 1 upcoming plan" : "In \(upcoming) upcoming plans"))
        }
        if !teams.isEmpty {
            let list = teams.prefix(2).joined(separator: ", ")
            parts.append(isChinese ? "\(list) 在用" : "\(list) \(teams.count == 1 ? "runs" : "run") it")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
