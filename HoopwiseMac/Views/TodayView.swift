import SwiftUI
import Combine

// MARK: - Today (Home)
/// Mac-native home screen. Two-column layout: primary content on the left
/// (today's sessions, today's athletes), attention rail on the right
/// (action items requiring the coach's eye). Hero strip on top folds in the
/// greeting, key counts, and the live-session indicator when a session is
/// actively running.
struct TodayView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var currentTime = Date()
    @State private var selectedSession: SessionEvent?

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroStrip

                CuratedRail()

                if let live = liveSession {
                    LiveSessionBanner(session: live)
                }

                if let liveGame = liveGames.first {
                    LiveGameBanner(game: liveGame)
                }

                statsRow

                HStack(alignment: .top, spacing: 20) {
                    primaryColumn
                    attentionRail
                        .frame(width: 360)
                }
            }
            .padding(28)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .macNewSession, object: nil)
                } label: {
                    Label("New Session", systemImage: "plus")
                }
            }
        }
        .onReceive(tick) { _ in currentTime = Date() }
        #if DEBUG
        .onAppear {
            // Agent hook: open the session sheet so Esc-dismissal is testable.
            if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_OPEN_SHEET"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    selectedSession = todaysSessions.first ?? dataManager.sessionEvents.first
                }
            }
            // Agent hook: simulate tapping the first athlete chip.
            if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_TAP_STUDENT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let student = todaysPlayers.first ?? dataManager.students.first {
                        openAthlete(student)
                    }
                }
            }
        }
        #endif
        .sheet(item: $selectedSession) { session in
            MacSheetChrome(title: session.title) { selectedSession = nil } content: {
                SessionDetailView(session: session)
            }
            .frame(minWidth: 720, minHeight: 560)
        }
    }

    /// A student tap NAVIGATES — the card belongs to the Athletes directory,
    /// not a modal. (The old sheet embedded a page-level detail view whose
    /// toolbar never renders inside a sheet: no close control, no Esc — a
    /// trap.)
    private func openAthlete(_ student: Student) {
        NotificationCenter.default.post(name: .macSidebarSelection,
                                        object: SidebarSection.athletes.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .macOpenAthlete, object: student.id)
        }
    }

    // MARK: - Hero strip

    private var heroStrip: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentTime, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(greeting)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            if liveSession == nil, let next = nextUpcomingSession {
                NextSessionPill(session: next)
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            StatTile(title: "Athletes", value: "\(dataManager.students.count)", systemImage: "person.2.fill", tint: .blue)
            StatTile(title: "Sessions Today", value: "\(todaysSessions.count)", systemImage: "calendar", tint: .orange)
            StatTile(title: "Programs", value: "\(activePrograms.count)", systemImage: "list.clipboard.fill", tint: .indigo)
            StatTile(title: "Drills", value: "\(dataManager.cachedDrills.count)", systemImage: "figure.basketball", tint: .green)
        }
    }

    // MARK: - Primary column

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Today's Sessions", count: todaysSessions.count)
                if todaysSessions.isEmpty {
                    EmptyPanel(systemImage: "calendar", text: "No sessions scheduled today.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(todaysSessions) { session in
                            TodaySessionCard(session: session, attendees: attendees(for: session))
                                .onTapGesture { selectedSession = session }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Today's Athletes", count: todaysPlayers.count)
                if todaysPlayers.isEmpty {
                    EmptyPanel(systemImage: "person.2", text: "No athletes on today's roster.")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(todaysPlayers) { student in
                            AthleteChip(student: student, contract: dataManager.currentContract(for: student.id))
                                .onTapGesture { openAthlete(student) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Attention rail

    private var attentionRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Attention", count: totalActionItems)

            if totalActionItems == 0 {
                EmptyPanel(systemImage: "checkmark.seal.fill", text: "All clear. Nothing needs your attention.")
            } else {
                VStack(spacing: 10) {
                    if !overdueReminders.isEmpty {
                        AttentionGroup(
                            title: "Overdue Reminders",
                            tint: .red,
                            systemImage: "exclamationmark.circle.fill"
                        ) {
                            ForEach(overdueReminders.prefix(4)) { ReminderRow(reminder: $0) }
                        }
                    }

                    if !expiringContracts.isEmpty {
                        AttentionGroup(
                            title: "Bundles Running Low",
                            tint: .orange,
                            systemImage: "creditcard.fill"
                        ) {
                            ForEach(expiringContracts.prefix(4), id: \.contract.id) { item in
                                ExpiringContractRow(contract: item.contract, student: item.student)
                                    .contentShape(Rectangle())
                                    .onTapGesture { openAthlete(item.student) }
                            }
                        }
                    }

                    if !unplannedSessions.isEmpty {
                        AttentionGroup(
                            title: "Unplanned Sessions",
                            tint: .yellow,
                            systemImage: "calendar.badge.exclamationmark"
                        ) {
                            ForEach(unplannedSessions.prefix(4)) { session in
                                UnplannedSessionRow(session: session)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedSession = session }
                            }
                        }
                    }

                    if !programsNeedingPlanning.isEmpty {
                        AttentionGroup(
                            title: "Programs Need Phases",
                            tint: .purple,
                            systemImage: "list.clipboard"
                        ) {
                            ForEach(programsNeedingPlanning.prefix(4)) { program in
                                ProgramPlanningRow(program: program)
                            }
                        }
                    }

                    if !upcomingReminders.isEmpty {
                        AttentionGroup(
                            title: "Upcoming Reminders",
                            tint: .blue,
                            systemImage: "bell.fill"
                        ) {
                            ForEach(upcomingReminders.prefix(4)) { ReminderRow(reminder: $0) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let part: String
        switch hour {
        case 0..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        default: part = "Good evening"
        }
        let name = dataManager.coach.name.split(separator: " ").first.map(String.init) ?? "Coach"
        return "\(part), \(name)."
    }

    private var todaysSessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { Calendar.current.isDateInToday($0.date) && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }
    }

    private var nextUpcomingSession: SessionEvent? {
        let now = currentTime
        return dataManager.sessionEvents
            .filter { $0.startTime > now && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private var todaysPlayers: [Student] {
        var ids = Set<UUID>()
        for session in todaysSessions {
            if !session.attendeeIds.isEmpty {
                ids.formUnion(session.attendeeIds)
            } else if let pid = session.programId,
                      let program = dataManager.programs.first(where: { $0.id == pid }) {
                ids.formUnion(program.enrolledStudentIds)
            }
        }
        return dataManager.students.filter { ids.contains($0.id) }
    }

    private var liveSession: SessionEvent? { LiveSessionEngine.shared.session }

    private var liveGames: [Game] { dataManager.games.filter { $0.status == .live } }

    private var activePrograms: [Program] {
        dataManager.programs.filter { $0.status == .active }
    }

    private var expiringContracts: [(contract: Contract, student: Student)] {
        dataManager.students.compactMap { student in
            guard let contract = dataManager.currentContract(for: student.id) else { return nil }
            guard contract.kind == .privateBundle else { return nil }
            let remaining = contract.bundleRedemptionsRemaining ?? .max
            guard remaining <= 3 else { return nil }
            return (contract, student)
        }.sorted { ($0.contract.bundleRedemptionsRemaining ?? 0) < ($1.contract.bundleRedemptionsRemaining ?? 0) }
    }

    private var unplannedSessions: [SessionEvent] {
        let now = currentTime
        let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.sessionEvents.filter { session in
            session.date >= now &&
            session.date <= horizon &&
            session.status == .scheduled &&
            session.curriculum.totalDrillCount == 0
        }.sorted { $0.date < $1.date }
    }

    private var programsNeedingPlanning: [Program] {
        let now = currentTime
        let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.programs
            .filter { $0.status == .active || $0.status == .draft }
            .filter { program in
                let phases = dataManager.microCycles.filter { $0.programId == program.id }
                guard phases.isEmpty else { return false }
                let hasSoonSessions = dataManager.sessionEvents.contains { session in
                    session.programId == program.id && session.date >= now && session.date <= horizon
                }
                return hasSoonSessions || (program.startDate ?? .distantFuture) <= horizon
            }
    }

    private var overdueReminders: [Reminder] { dataManager.overdueReminders }
    private var upcomingReminders: [Reminder] { dataManager.upcomingReminders }

    private var totalActionItems: Int {
        overdueReminders.count + expiringContracts.count + unplannedSessions.count + programsNeedingPlanning.count + upcomingReminders.count
    }

    private func attendees(for session: SessionEvent) -> [Student] {
        var ids = session.attendeeIds
        if ids.isEmpty, let pid = session.programId,
           let program = dataManager.programs.first(where: { $0.id == pid }) {
            ids = program.enrolledStudentIds
        }
        return dataManager.students.filter { ids.contains($0.id) }
    }
}

// MARK: - Hero pieces

private struct NextSessionPill: View {
    let session: SessionEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next").font(.caption2).foregroundStyle(.secondary)
                Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Text(session.startTime, style: .relative)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

private struct LiveSessionBanner: View {
    let session: SessionEvent
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.red.opacity(0.18)).frame(width: 44, height: 44)
                Circle().fill(.red).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("LIVE NOW").font(.caption.weight(.bold)).foregroundStyle(.red)
                Text(session.title).font(.title3.weight(.semibold))
            }
            Spacer()
            Button {
                NotificationCenter.default.post(name: .macSidebarSelection, object: SidebarSection.sessions.rawValue)
            } label: {
                Label("Open Session", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.red.opacity(0.3), lineWidth: 1))
    }
}

private struct LiveGameBanner: View {
    @EnvironmentObject var dataManager: DataManager
    let game: Game
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Game").font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(matchupTitle).font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text("\(game.homeScore) – \(game.awayScore)")
                .font(.title3.weight(.bold).monospacedDigit())
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange.opacity(0.3), lineWidth: 1))
    }
    private var matchupTitle: String {
        let home = dataManager.teams.first(where: { $0.id == game.homeTeamId })?.name ?? "Home"
        let away = dataManager.teams.first(where: { $0.id == game.awayTeamId })?.name ?? "Away"
        return "\(home) vs \(away)"
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.18))
                Image(systemName: systemImage).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 26, weight: .bold).monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let count: Int?
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Compact inline empty-state row used by section panels in StubViews / SessionsView.
struct EmptyInline: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyPanel: View {
    let systemImage: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Today session card

private struct TodaySessionCard: View {
    let session: SessionEvent
    let attendees: [Student]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // time block
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTime, format: .dateTime.hour().minute())
                    .font(.headline.weight(.bold).monospacedDigit())
                Text(session.endTime, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusTint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(session.title).font(.subheadline.weight(.semibold))
                    SessionStatusBadge(status: session.status)
                }
                HStack(spacing: 10) {
                    if let location = session.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .labelStyle(.titleAndIcon)
                    }
                    Label("\(attendees.count) athletes", systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                    if session.curriculum.totalDrillCount > 0 {
                        Label("\(session.curriculum.totalDrillCount) drills", systemImage: "figure.basketball")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !attendees.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(attendees.prefix(6)) { student in
                            Circle()
                                .fill(Color.avatarColor(student.avatarColor))
                                .overlay(
                                    Text(student.initials)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                )
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                        }
                        if attendees.count > 6 {
                            Text("+\(attendees.count - 6)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        .contentShape(Rectangle())
    }

    private var statusTint: Color {
        switch session.status {
        case .inProgress: return .red
        case .completed: return .green
        case .cancelled, .skipped: return .gray
        case .scheduled: return .accentColor
        }
    }
}

private struct SessionStatusBadge: View {
    let status: SessionEventStatus
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }
    private var tint: Color {
        switch status {
        case .inProgress: return .red
        case .completed: return .green
        case .cancelled: return .gray
        case .skipped: return .gray
        case .scheduled: return .blue
        }
    }
}

// MARK: - Athlete chip

private struct AthleteChip: View {
    let student: Student
    let contract: Contract?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.avatarColor(student.avatarColor))
                .overlay(
                    Text(student.initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                )
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(student.name).font(.caption.weight(.semibold)).lineLimit(1)
                if let contract, let remaining = contract.bundleRedemptionsRemaining {
                    Text("\(remaining) left")
                        .font(.caption2)
                        .foregroundStyle(remaining <= 3 ? .orange : .secondary)
                } else {
                    Text(student.ageGroup?.displayName ?? "—").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

// MARK: - Attention rail building blocks

private struct AttentionGroup<Content: View>: View {
    let title: String
    let tint: Color
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
            }
            VStack(spacing: 6) { content() }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
    }
}

private struct ExpiringContractRow: View {
    let contract: Contract
    let student: Student
    var body: some View {
        HStack {
            Text(student.name).font(.caption.weight(.medium))
            Spacer()
            Text("\(contract.bundleRedemptionsRemaining ?? 0) left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}

private struct UnplannedSessionRow: View {
    let session: SessionEvent
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(session.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct ProgramPlanningRow: View {
    let program: Program
    var body: some View {
        HStack {
            Text(program.name).font(.caption.weight(.medium)).lineLimit(1)
            Spacer()
            Text("No phases").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(reminder.dueDate, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}


// MARK: - Curated by the whistle

/// Assistant-ranked attention cards. Purely additive: offline or keyless,
/// curation returns nothing and Today renders exactly as before.
private struct CuratedRail: View {
    @EnvironmentObject var engine: AssistantEngine

    var body: some View {
        if !engine.curationCards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    WhistleGlyph(size: 16)
                    Text(engine.curationCards.first?.curated == true
                         ? "Curated by the whistle" : "Worth a look")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await engine.runCuration(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh curation")
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(engine.curationCards) { card in
                            Button {
                                open(card)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(card.title)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(card.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(10)
                                .frame(width: 230, alignment: .leading)
                                .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func open(_ card: CurationCard) {
        let center = NotificationCenter.default
        if let athleteId = card.athleteId {
            center.post(name: .macSidebarSelection, object: SidebarSection.athletes.rawValue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                center.post(name: .macOpenAthlete, object: athleteId)
            }
        } else if card.kind == "session" {
            center.post(name: .macSidebarSelection, object: SidebarSection.sessions.rawValue)
        } else if card.kind == "bundleLow" {
            center.post(name: .macSidebarSelection, object: SidebarSection.sales.rawValue)
        }
    }
}
