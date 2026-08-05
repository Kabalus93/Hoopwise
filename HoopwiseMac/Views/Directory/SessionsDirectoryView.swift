import SwiftUI
import AppKit

// MARK: - Sessions directory
//
// The second instance of the directory skeleton — the abstraction validator.
// Content re-mapped only: groups = status ranges + programs, list = sessions
// sectioned by month, card = the existing session detail (roster + attendance
// tabs). No custom groups here — the skeleton simply omits the footer.
struct SessionsDirectoryView: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var selectedGroups: Set<String> = ["fixed:all"]
    @State private var search = ""
    @State private var selection: UUID?
    @State private var showingNew = false
    /// list | calendar — the calendar restores what the old Sessions page
    /// had, inside the directory grammar.
    @AppStorage("sessionsDirectory.viewMode") private var viewMode = "list"
    @State private var calendarDay = Calendar.current.startOfDay(for: Date())

    @StateObject private var keyRouter = DirectoryKeyRouter()
    @State private var keyDispatcher = DirectoryKeyDispatcher()

    private static let monthFormat = Date.FormatStyle().month(.wide).year()

    var body: some View {
        DirectoryView(
            groupSections: groupSections,
            selectedGroups: $selectedGroups,
            items: visibleSessions,
            sectionKey: { $0.date.formatted(Self.monthFormat) },
            searchText: $search,
            searchPrompt: "Search sessions",
            selection: $selection,
            countLabel: "\(visibleSessions.count)",
            storageKey: "sessionsDirectory",
            showsIndexRail: false,
            searchFocusToken: keyRouter.searchFocusToken,
            row: { session in
                SessionDirectoryRow(session: session)
            },
            listAccessory: { AnyView(modeToggle) },
            listOverride: viewMode == "calendar"
                ? { AnyView(SessionCalendarColumn(
                        sessions: visibleSessions,
                        selectedDay: $calendarDay,
                        selection: $selection)) }
                : nil,
            detail: { detailCard }
        )
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("New Session", systemImage: "plus")
                }
            }
        }
        .onAppear {
            wireKeyboard()
            keyDispatcher.install(router: keyRouter)
            autoSelectIfNeeded()
        }
        .onDisappear { keyDispatcher.uninstall() }
        .onChange(of: selectedGroups) { _, _ in autoSelectIfNeeded() }
        .onChange(of: search) { _, _ in autoSelectIfNeeded() }
        .onChange(of: calendarDay) { _, _ in autoSelectIfNeeded() }
        .onChange(of: viewMode) { _, _ in autoSelectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .macNewSession)) { _ in
            showingNew = true
        }
        // Deep link from the Athletes card's Recent Sessions rows.
        .onReceive(NotificationCenter.default.publisher(for: .macOpenSession)) { note in
            guard let id = note.object as? UUID else { return }
            selectedGroups = ["fixed:all"]
            search = ""
            if let session = dataManager.sessionEvents.first(where: { $0.id == id }) {
                calendarDay = Calendar.current.startOfDay(for: session.date)
            }
            selection = id
        }
        .sheet(isPresented: $showingNew) {
            NewSessionSheet().dismissesOnPresentationEscape { showingNew = false }
        }
    }

    private var modeToggle: some View {
        Picker("View", selection: $viewMode) {
            Image(systemName: "list.bullet").tag("list")
            Image(systemName: "calendar").tag("calendar")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("List or calendar view")
    }

    @ViewBuilder
    private var detailCard: some View {
        if let id = selection,
           let session = dataManager.sessionEvents.first(where: { $0.id == id }) {
            SessionDetailView(session: session).id(session.id)
        } else {
            EmptyDetail(systemImage: "calendar", title: "Select a Session")
        }
    }

    // MARK: - Groups

    private var groupSections: [DirectoryGroupSection] {
        let sessions = dataManager.sessionEvents
        var sections: [DirectoryGroupSection] = [
            DirectoryGroupSection(id: "smart", title: nil, groups: [
                DirectoryGroup(id: "fixed:all", title: "All Sessions",
                               icon: "calendar", count: sessions.count),
                DirectoryGroup(id: "fixed:today", title: "Today",
                               icon: "sun.max", count: count("fixed:today")),
                DirectoryGroup(id: "fixed:upcoming", title: "Upcoming",
                               icon: "arrow.forward.circle", count: count("fixed:upcoming")),
                DirectoryGroup(id: "fixed:past", title: "Past",
                               icon: "clock.arrow.circlepath", count: count("fixed:past")),
            ]),
        ]
        let programs = dataManager.programs.filter { program in
            sessions.contains { $0.programId == program.id }
        }
        if !programs.isEmpty {
            sections.append(DirectoryGroupSection(
                id: "programs", title: "Programs",
                groups: programs.map { program in
                    DirectoryGroup(id: "program:\(program.id.uuidString)",
                                   title: program.name,
                                   icon: "list.clipboard",
                                   count: sessions.filter { $0.programId == program.id }.count)
                }))
        }
        return sections
    }

    private func count(_ groupId: String) -> Int { memberIds(of: groupId).count }

    private func memberIds(of groupId: String) -> Set<UUID> {
        let sessions = dataManager.sessionEvents
        let calendar = Calendar.current
        switch groupId {
        case "fixed:all":
            return Set(sessions.map(\.id))
        case "fixed:today":
            return Set(sessions.filter { calendar.isDateInToday($0.date) }.map(\.id))
        case "fixed:upcoming":
            return Set(sessions.filter { $0.date > Date() }.map(\.id))
        case "fixed:past":
            return Set(sessions.filter { $0.date <= Date() }.map(\.id))
        default:
            if groupId.hasPrefix("program:"),
               let uuid = UUID(uuidString: String(groupId.dropFirst("program:".count))) {
                return Set(sessions.filter { $0.programId == uuid }.map(\.id))
            }
            return []
        }
    }

    private var selectedMemberIds: Set<UUID>? {
        let picked = selectedGroups.filter { $0 != "fixed:all" }
        guard !picked.isEmpty, !selectedGroups.contains("fixed:all") else { return nil }
        var union: Set<UUID> = []
        for groupId in picked { union.formUnion(memberIds(of: groupId)) }
        return union
    }

    /// Newest first — sessions read as a reverse-chronological log.
    private var visibleSessions: [SessionEvent] {
        let members = selectedMemberIds
        var base = dataManager.sessionEvents
        if let members { base = base.filter { members.contains($0.id) } }
        if !search.isEmpty {
            base = base.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.location ?? "").localizedCaseInsensitiveContains(search)
            }
        }
        return base.sorted { $0.date > $1.date }
    }

    // MARK: - Keyboard (same dispatch layer, same grammar)

    private func wireKeyboard() {
        keyRouter.moveSelection = { delta in
            let items = viewMode == "calendar" ? sessionsOnCalendarDay : visibleSessions
            guard !items.isEmpty else { return }
            guard let current = selection,
                  let index = items.firstIndex(where: { $0.id == current }) else {
                selection = delta > 0 ? items.first?.id : items.last?.id
                return
            }
            let next = min(max(0, index + delta), items.count - 1)
            selection = items[next].id
        }
        keyRouter.typeToSelect = { buffer in
            if let hit = visibleSessions.first(where: {
                $0.title.lowercased().hasPrefix(buffer)
            }) {
                selection = hit.id
            }
        }
        keyRouter.escape = {
            if !search.isEmpty {
                search = ""
                return true
            }
            return false
        }
        keyRouter.newItem = { showingNew = true }
    }

    private var sessionsOnCalendarDay: [SessionEvent] {
        visibleSessions
            .filter { Calendar.current.isDate($0.date, inSameDayAs: calendarDay) }
            .sorted { $0.startTime < $1.startTime }
    }

    private func autoSelectIfNeeded() {
        let items = viewMode == "calendar" ? sessionsOnCalendarDay : visibleSessions
        if let current = selection, items.contains(where: { $0.id == current }) { return }
        selection = items.first?.id
    }
}

// MARK: - Row

private struct SessionDirectoryRow: View {
    let session: SessionEvent
    @AppStorage("settings.listDensity") private var listDensity = "comfortable"

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)
                Text(session.date, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            Spacer(minLength: 4)
            if !session.actualAttendeeIds.isEmpty {
                Text("\(session.actualAttendeeIds.count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, listDensity == "compact" ? -2 : 1)
    }
}


// MARK: - Calendar column

/// Month grid in the app's grammar: quinary surfaces, accent selection,
/// dot indicators for days with sessions. Selecting a day lists its
/// sessions below; the rows drive the same selection as the list view.
private struct SessionCalendarColumn: View {
    let sessions: [SessionEvent]
    @Binding var selectedDay: Date
    @Binding var selection: UUID?

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var hoveredDay: Date?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            dayGrid
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            Divider()
            daySessionList
        }
        .onAppear { displayedMonth = monthStart(of: selectedDay) }
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
                .frame(minWidth: 130)
                .contentTransition(.numericText())
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Button("Today") {
                withAnimation(.snappy(duration: 0.2)) {
                    selectedDay = calendar.startOfDay(for: Date())
                    displayedMonth = monthStart(of: selectedDay)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols
        return HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private var dayGrid: some View {
        let days = gridDays
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .animation(.snappy(duration: 0.16), value: displayedMonth)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let count = sessionCountsByDay[day] ?? 0
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white
                                     : inMonth ? Color.primary : Color.secondary.opacity(0.45))
                // The at-a-glance indicator: dots say "sessions here".
                HStack(spacing: 2) {
                    if count == 0 {
                        Circle().fill(Color.clear).frame(width: 4, height: 4)
                    } else {
                        ForEach(0..<min(count, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white : Color.accentColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor)
                          : hoveredDay == day ? AnyShapeStyle(.quaternary.opacity(0.6))
                          : AnyShapeStyle(Color.clear)))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isToday && !isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 1.4))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredDay = inside ? day : nil }
    }

    private var daySessionList: some View {
        let daySessions = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.startTime < $1.startTime }
        return VStack(spacing: 0) {
            HStack {
                Text(selectedDay, format: .dateTime.weekday(.wide).month().day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !daySessions.isEmpty {
                    Text("\(daySessions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            if daySessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No sessions this day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(daySessions) { session in
                        SessionDirectoryRow(session: session)
                            .tag(session.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func monthStart(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func step(_ direction: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            displayedMonth = calendar.date(byAdding: .month, value: direction,
                                           to: displayedMonth) ?? displayedMonth
        }
    }

    /// Full weeks covering the displayed month — always 42 cells so the
    /// grid never jumps height between months.
    private var gridDays: [Date] {
        let start = monthStart(of: displayedMonth)
        let weekdayOffset = (calendar.component(.weekday, from: start)
            - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: start)
        else { return [] }
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }.map { calendar.startOfDay(for: $0) }
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var sessionCountsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for session in sessions {
            counts[calendar.startOfDay(for: session.date), default: 0] += 1
        }
        return counts
    }
}
