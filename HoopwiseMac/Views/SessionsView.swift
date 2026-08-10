import SwiftUI

// MARK: - Sessions
/// Mac-native sessions screen. Inner NavigationSplitView so the user keeps
/// the calendar/list visible while reading detail. Detail pane is tabbed
/// (Plan / Roll Call / Notes / Stats), each writing back through
/// `dataManager.updateSessionEvent`.
struct SessionsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedDate: Date = .now
    @State private var selectedID: SessionEvent.ID?
    @State private var search: String = ""
    @State private var filter: SessionFilter = .all
    @State private var showingNew = false

    enum SessionFilter: String, CaseIterable, Identifiable {
        case all, today, upcoming, past
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .today: return "Today"
            case .upcoming: return "Upcoming"
            case .past: return "Past"
            }
        }
        var systemImage: String {
            switch self {
            case .all: return "calendar"
            case .today: return "sun.max.fill"
            case .upcoming: return "arrow.forward.circle.fill"
            case .past: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 360, idealWidth: 380)
        } detail: {
            if let id = selectedID, let session = dataManager.sessionEvents.first(where: { $0.id == id }) {
                SessionDetailView(session: session)
                    .id(session.id)
            } else {
                EmptyDetail(systemImage: "calendar", title: "Select a Session")
            }
        }
        .onAppear { autoSelectIfNeeded() }
        .onChange(of: filter) { _, _ in autoSelectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .macNewSession)) { _ in
            showingNew = true
        }
        // Deep link from the Athletes card's Recent Sessions rows.
        .onReceive(NotificationCenter.default.publisher(for: .macOpenSession)) { note in
            guard let id = note.object as? UUID,
                  let session = dataManager.sessionEvents.first(where: { $0.id == id })
            else { return }
            filter = .all
            selectedDate = session.date
            selectedID = id
        }
        .sheet(isPresented: $showingNew) { NewSessionSheet() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterPicker
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            Divider()

            sessionsList
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("New Session", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(SessionFilter.allCases) { f in
                Label(f.label, systemImage: f.systemImage).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search sessions or location", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.quinary, in: .rect(cornerRadius: 6))
    }

    private var sessionsList: some View {
        List(selection: $selectedID) {
            if grouped.isEmpty {
                Text("No sessions match.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            SessionListRow(session: session)
                                .tag(session.id)
                                .contextMenu {
                                    sessionContextMenu(session: session)
                                }
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).month().day())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func sessionContextMenu(session: SessionEvent) -> some View {
        // Through the state machine, and offered only where it allows the
        // transition. Setting status directly used to offer "Cancel Session"
        // on a session that had already been skipped — a transition isAllowed
        // forbids, performed anyway because the menu never asked it.
        switch session.status {
        case .scheduled:
            Button("Start Session", systemImage: "play.fill") { transition(session, .start) }
        case .inProgress:
            Button("Complete", systemImage: "checkmark.circle") { transition(session, .complete) }
        default:
            EmptyView()
        }
        if SessionLifecycle.isAllowed(.cancel, from: session.status) {
            Button("Cancel Session", systemImage: "xmark.circle", role: .destructive) {
                transition(session, .cancel)
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            dataManager.deleteSessionEvent(session)
            if selectedID == session.id { selectedID = nil }
        }
    }

    // MARK: - Filtering

    private struct DayGroup {
        let day: Date
        let sessions: [SessionEvent]
    }

    private var filtered: [SessionEvent] {
        let now = Date()
        let cal = Calendar.current
        let base: [SessionEvent]
        switch filter {
        case .all:      base = dataManager.sessionEvents
        case .today:    base = dataManager.sessionEvents.filter { cal.isDateInToday($0.date) }
        case .upcoming: base = dataManager.sessionEvents.filter { $0.date >= now && !SessionLifecycle.didNotHappen($0) }
        case .past:     base = dataManager.sessionEvents.filter { $0.date < now || $0.status == .completed || SessionLifecycle.didNotHappen($0) }
        }
        let searched = search.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            ($0.location ?? "").localizedCaseInsensitiveContains(search)
        }
        return searched.sorted { $0.startTime < $1.startTime }
    }

    private var grouped: [DayGroup] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return buckets.keys.sorted().map { day in
            DayGroup(day: day, sessions: buckets[day] ?? [])
        }
    }

    private func autoSelectIfNeeded() {
        if let current = selectedID, dataManager.sessionEvents.contains(where: { $0.id == current }) { return }
        selectedID = filtered.first?.id
    }

    private func mutate(_ session: SessionEvent, _ block: (inout SessionEvent) -> Void) {
        var copy = session
        block(&copy)
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }

    /// Status changes go through SessionLifecycle, which refuses a transition
    /// its own gate disallows.
    private func transition(_ session: SessionEvent, _ transition: SessionLifecycle.Transition) {
        var copy = session
        guard SessionLifecycle.apply(transition, to: &copy) else { return }
        dataManager.updateSessionEvent(copy)
    }
}

// MARK: - Sidebar Row

private struct SessionListRow: View {
    let session: SessionEvent
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.startTime, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(session.endTime, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, alignment: .leading)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(statusTint)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let loc = session.location, !loc.isEmpty {
                        Text(loc).lineLimit(1)
                    }
                    if !(session.location ?? "").isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text("\(session.attendeeIds.count) athletes")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            statusBadge
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text(session.status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(statusTint.opacity(0.18), in: .capsule)
            .foregroundStyle(statusTint)
    }

    private var statusTint: Color {
        switch session.status {
        case .inProgress: return .red
        case .completed: return .green
        case .cancelled, .skipped: return .gray
        case .scheduled: return .blue
        }
    }
}

// MARK: - Detail

struct SessionDetailView: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @State private var tab: DetailTab = .plan
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case plan, rollCall, notes, stats
        var id: String { rawValue }
        var label: String {
            switch self {
            case .plan: return "Plan"
            case .rollCall: return "Roll Call"
            case .notes: return "Notes"
            case .stats: return "Stats"
            }
        }
        var systemImage: String {
            switch self {
            case .plan: return "list.bullet.rectangle"
            case .rollCall: return "checkmark.circle"
            case .notes: return "note.text"
            case .stats: return "chart.bar.fill"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                actionBar

                statRow

                tabPicker

                Group {
                    switch tab {
                    case .plan:     PlanTab(session: session)
                    case .rollCall: RollCallTab(session: session)
                    case .notes:    NotesTab(session: session)
                    case .stats:    StatsTab(session: session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(session.title)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(session.startTime, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }
            Text(session.title).font(.system(size: 30, weight: .bold))
            HStack(spacing: 14) {
                Label {
                    Text("\(session.startTime, format: .dateTime.hour().minute()) – \(session.endTime, format: .dateTime.hour().minute())")
                } icon: { Image(systemName: "clock") }
                if let loc = session.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                }
                Label("\(session.durationMinutes) min", systemImage: "timer")
            }
            .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
    }

    /// Every status change goes through SessionLifecycle — the SAME state
    /// machine iOS runs, extracted to the shared layer. Gating comes from
    /// isAllowed, so Mac can never offer a transition iOS forbids.
    private var actionBar: some View {
        HStack(spacing: 8) {
            primaryActionButton

            if SessionLifecycle.isAllowed(.skip(.other), from: session.status) {
                Menu {
                    ForEach(SkipReason.allCases) { reason in
                        Button {
                            applyTransition(.skip(reason))
                        } label: {
                            Label(reason.displayName, systemImage: reason.icon)
                        }
                    }
                } label: {
                    Label("Skip…", systemImage: "forward.end")
                }
                .fixedSize()
            }

            Button {
                applyTransition(.cancel)
            } label: {
                Label("Cancel Session", systemImage: "xmark.circle")
            }
            .disabled(!SessionLifecycle.isAllowed(.cancel, from: session.status))

            Button {
                showingEdit = true
            } label: {
                Label("Edit…", systemImage: "square.and.pencil")
            }

            Spacer()

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .confirmationDialog("Delete \"\(session.title)\"?",
                                isPresented: $confirmingDelete) {
                Button("Delete Session", role: .destructive) {
                    dataManager.deleteSessionEvent(session)
                }
            } message: {
                Text("Attendance records for this session are removed. This cannot be undone.")
            }
        }
        .controlSize(.large)
        .sheet(isPresented: $showingEdit) {
            SessionEditSheet(session: session)
                .dismissesOnPresentationEscape { showingEdit = false }
        }
    }

    private func applyTransition(_ transition: SessionLifecycle.Transition) {
        var copy = session
        guard SessionLifecycle.apply(transition, to: &copy) else { return }
        dataManager.updateSessionEvent(copy)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch session.status {
        case .scheduled:
            Button {
                applyTransition(.start)
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        case .inProgress:
            Button {
                applyTransition(.complete)
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        case .completed:
            Button {
                applyTransition(.resetToScheduled)
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward.circle")
            }
        case .cancelled, .skipped:
            Button {
                applyTransition(.resetToScheduled)
            } label: {
                Label("Restore", systemImage: "arrow.clockwise")
            }
        }
    }

    private var statRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatPill(title: "Status", value: session.status.rawValue.capitalized)
            StatPill(title: "Roster", value: "\(session.attendeeIds.count)")
            StatPill(title: "Attended", value: "\(session.actualAttendeeIds.count)")
            StatPill(title: "Drills", value: "\(session.curriculum.totalDrillCount)")
        }
    }

    private var tabPicker: some View {
        Picker("Section", selection: $tab) {
            ForEach(DetailTab.allCases) { t in
                Label(t.label, systemImage: t.systemImage).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var statusBadge: some View {
        Text(session.status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(statusTint.opacity(0.18), in: .capsule)
            .foregroundStyle(statusTint)
    }

    private var statusTint: Color {
        switch session.status {
        case .inProgress: return .red
        case .completed: return .green
        case .cancelled, .skipped: return .gray
        case .scheduled: return .blue
        }
    }

    private func mutate(_ block: (inout SessionEvent) -> Void) {
        var copy = session
        block(&copy)
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }
}

// MARK: - Plan tab

private struct PlanTab: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button { showingPicker = true } label: {
                    Label("Edit Plan", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
            durationBar

            phaseSection(
                title: "Warmup",
                tint: .orange,
                systemImage: "flame.fill",
                minutes: session.curriculum.warmupMinutes,
                drillIds: session.curriculum.warmupDrillIds
            )
            phaseSection(
                title: "Skills",
                tint: .blue,
                systemImage: "figure.basketball",
                minutes: session.curriculum.skillsMinutes,
                drillIds: session.curriculum.skillDrillIds
            )
            phaseSection(
                title: "Games",
                tint: .purple,
                systemImage: "trophy.fill",
                minutes: session.curriculum.gameMinutes,
                drillIds: session.curriculum.gameDrillIds
            )

            if let notes = session.curriculum.notes, !notes.isEmpty {
                SectionBlock(title: "Plan Notes") {
                    Text(notes)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            DrillPickerSheet(session: session)
                .dismissesOnPresentationEscape { showingPicker = false }
        }
    }

    private var durationBar: some View {
        let total = max(session.curriculum.totalMinutes, 1)
        let warmup = Double(session.curriculum.warmupMinutes) / Double(total)
        let skills = Double(session.curriculum.skillsMinutes) / Double(total)
        let games = Double(session.curriculum.gameMinutes) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time Allocation")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(session.curriculum.totalMinutes) min")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(.orange).frame(width: geo.size.width * warmup)
                    Rectangle().fill(.blue).frame(width: geo.size.width * skills)
                    Rectangle().fill(.purple).frame(width: geo.size.width * games)
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                legendDot(color: .orange, label: "Warmup \(session.curriculum.warmupMinutes)m")
                legendDot(color: .blue, label: "Skills \(session.curriculum.skillsMinutes)m")
                legendDot(color: .purple, label: "Games \(session.curriculum.gameMinutes)m")
                Spacer()
            }
            .font(.caption)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func phaseSection(title: String, tint: Color, systemImage: String, minutes: Int, drillIds: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold))
                Text("·").foregroundStyle(.tertiary)
                Text("\(minutes)m").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(drillIds.count) drills").font(.caption).foregroundStyle(.secondary)
            }
            if drillIds.isEmpty {
                EmptyPanel(systemImage: "questionmark.circle", text: "No drills planned for this phase.")
            } else {
                VStack(spacing: 6) {
                    ForEach(drillIds, id: \.self) { id in
                        DrillRow(drill: dataManager.cachedDrills.first(where: { $0.id == id }), tint: tint)
                    }
                }
            }
        }
    }
}

private struct DrillRow: View {
    let drill: DrillItem?
    let tint: Color
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(drill?.name ?? "Unknown Drill").font(.subheadline.weight(.medium)).lineLimit(1)
                if let drill {
                    HStack(spacing: 8) {
                        Text(drill.category.displayName).font(.caption2).foregroundStyle(.secondary)
                        if drill.durationMinutes > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(drill.durationMinutes)m").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Roll Call tab

private struct RollCallTab: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @State private var showingRosterEditor = false

    // FOUR states, matching iOS's AttendanceMarkControl exactly: unmarked is
    // NOT absent, present and unexcused-absent consume a bundle session,
    // excused and unmarked do not. Every write goes through
    // setStudentAttendanceState — the shared authority that keeps contracts
    // in lockstep (redeemPrivateAttendance, FIFO). The previous Mac tab
    // cycled three states and wrote arrays wholesale, so marking present
    // here never deducted — the exact parity break this replaces.

    private var roster: [Student] {
        let ids = Set(AttendanceMath.expectedIds(of: session, programs: dataManager.programs))
        return dataManager.students.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Attendance")
                    .font(.subheadline.weight(.semibold))
                Text("\(session.actualAttendeeIds.count) / \(roster.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.green.opacity(0.18), in: .capsule)
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    showingRosterEditor = true
                } label: {
                    Label("Edit Roster", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    for student in roster {
                        dataManager.setStudentAttendanceState(
                            sessionId: session.id, studentId: student.id, state: .present)
                    }
                } label: {
                    Label("Mark All Present", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(roster.isEmpty)

                Button {
                    // Clear = UNMARKED, never absent: clearing must never
                    // charge (and un-charging past redemptions is refund
                    // territory, handled by the shared authority).
                    for student in roster {
                        dataManager.setStudentAttendanceState(
                            sessionId: session.id, studentId: student.id, state: .unmarked)
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session.actualAttendeeIds.isEmpty
                          && session.excusedAbsences.isEmpty
                          && session.unexcusedAbsences.isEmpty)
            }

            if roster.isEmpty {
                EmptyPanel(systemImage: "person.2", text: "No athletes assigned to this session yet.")
            } else {
                VStack(spacing: 6) {
                    ForEach(roster) { student in
                        MacAttendanceRow(
                            student: student,
                            state: state(for: student.id),
                            consumes: consumesBundle(student.id),
                            onSet: { newState in
                                dataManager.setStudentAttendanceState(
                                    sessionId: session.id,
                                    studentId: student.id,
                                    state: newState)
                            })
                    }
                }
            }
        }
        .sheet(isPresented: $showingRosterEditor) {
            SessionRosterSheet(session: session)
                .dismissesOnPresentationEscape { showingRosterEditor = false }
        }
    }

    private func state(for id: UUID) -> AttendanceTriState {
        if session.actualAttendeeIds.contains(id) { return .present }
        if session.excusedAbsences.contains(id) { return .excused }
        if session.unexcusedAbsences.contains(id) { return .absent }
        return .unmarked
    }

    /// Whether marking this student present/absent charges a bundle session —
    /// drives the money-consequence hint, worded like the iOS control.
    private func consumesBundle(_ id: UUID) -> Bool {
        guard let contract = dataManager.currentContract(for: id) else { return false }
        return contract.kind == .privateBundle
    }
}

/// Four-state Mac attendance row: segmented state control plus the money
/// consequence in words, because two of the four states charge the client.
private struct MacAttendanceRow: View {
    let student: Student
    let state: AttendanceTriState
    let consumes: Bool
    let onSet: (AttendanceTriState) -> Void

    var body: some View {
        HStack(spacing: 10) {
            AthletePhoto(imageData: student.thumbnailImageData ?? student.profileImageData,
                         initials: student.initials,
                         color: Color.avatarColor(student.avatarColor),
                         size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(student.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                if consumes {
                    Text(consequenceText)
                        .font(.caption2)
                        .foregroundStyle(chargesNow ? .orange : .secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(get: { state }, set: { onSet($0) })) {
                Text("—").tag(AttendanceTriState.unmarked)
                Text("Present").tag(AttendanceTriState.present)
                Text("Excused").tag(AttendanceTriState.excused)
                Text("Absent").tag(AttendanceTriState.absent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(state == .unmarked ? Color.secondary.opacity(0.35) : .clear,
                              style: StrokeStyle(lineWidth: 1, dash: state == .unmarked ? [4, 3] : []))
        )
    }

    private var chargesNow: Bool { state == .present || state == .absent }

    private var consequenceText: String {
        switch state {
        case .present:  return "Deducts 1 session"
        case .absent:   return "Deducts 1 session (unexcused)"
        case .excused:  return "No session deducted"
        case .unmarked: return "Not marked — no session deducted"
        }
    }

    private var rowBackground: some ShapeStyle {
        switch state {
        case .present:  return AnyShapeStyle(Color.green.opacity(0.10))
        case .excused:  return AnyShapeStyle(Color.orange.opacity(0.10))
        case .absent:   return AnyShapeStyle(Color.red.opacity(0.10))
        case .unmarked: return AnyShapeStyle(Color.secondary.opacity(0.05))
        }
    }
}

/// Session roster editing: membership in session.attendeeIds — the same
/// array iOS reads. Attendance state is untouched by roster edits.
private struct SessionRosterSheet: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        MacSheetChrome(title: "Session Roster") { dismiss() } content: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search athletes", text: $search).textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quinary, in: .rect(cornerRadius: 6))
                .padding(12)

                List {
                    ForEach(filtered) { student in
                        HStack(spacing: 10) {
                            AthletePhoto(imageData: student.thumbnailImageData ?? student.profileImageData,
                                         initials: student.initials,
                                         color: Color.avatarColor(student.avatarColor),
                                         size: 26)
                            Text(student.displayName)
                            if let chinese = student.chineseName, chinese != student.displayName {
                                Text(chinese).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.attendeeIds.contains(student.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(student.id) }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 420, minHeight: 440)
        }
    }

    private var filtered: [Student] {
        let base = dataManager.students
        guard !search.isEmpty else {
            return base.sorted { $0.name < $1.name }
        }
        return base.filter {
            NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(search)
        }.sorted { $0.name < $1.name }
    }

    private func toggle(_ id: UUID) {
        var copy = session
        if copy.attendeeIds.contains(id) {
            copy.attendeeIds.removeAll { $0 == id }
        } else {
            copy.attendeeIds.append(id)
        }
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }
}

// MARK: - Notes tab

private struct NotesTab: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @State private var planDraft: String = ""
    @State private var reflectionDraft: String = ""
    @State private var dirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionBlock(title: "Pre-Session Plan") {
                TextEditor(text: $planDraft)
                    .font(.subheadline)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
                    .onChange(of: planDraft) { _, _ in dirty = true }
            }

            SectionBlock(title: "Coach Reflections") {
                TextEditor(text: $reflectionDraft)
                    .font(.subheadline)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
                    .onChange(of: reflectionDraft) { _, _ in dirty = true }
            }

            HStack {
                if dirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    revert()
                } label: { Text("Discard") }
                .disabled(!dirty)

                Button {
                    save()
                } label: { Text("Save Notes") }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!dirty)
            }
        }
        .onAppear { loadDrafts() }
        .onChange(of: session.id) { _, _ in loadDrafts() }
    }

    private func loadDrafts() {
        planDraft = session.notes ?? ""
        reflectionDraft = session.coachNotes ?? ""
        dirty = false
    }

    private func revert() { loadDrafts() }

    private func save() {
        var copy = session
        copy.notes = planDraft.isEmpty ? nil : planDraft
        copy.coachNotes = reflectionDraft.isEmpty ? nil : reflectionDraft
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
        dirty = false
    }
}

// MARK: - Stats tab

private struct StatsTab: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                StatPill(title: "Attendance", value: attendancePercentage)
                StatPill(title: "Drills Completed", value: "\(session.drillsCompleted.count) / \(session.curriculum.totalDrillCount)")
                StatPill(title: "Rating", value: ratingDisplay)
            }

            SectionBlock(title: "Development Focus") {
                if session.developmentFocus.isEmpty {
                    EmptyPanel(systemImage: "target", text: "No focus areas tagged for this session.")
                } else {
                    HStack(spacing: 8) {
                        ForEach(session.developmentFocus, id: \.self) { focus in
                            Text(focus.rawValue.capitalized)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.regularMaterial, in: .capsule)
                        }
                    }
                }
            }

            SectionBlock(title: "Man of the Match") {
                if let id = session.manOfTheMatchId,
                   let student = dataManager.students.first(where: { $0.id == id }) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.avatarColor(student.avatarColor))
                            .overlay(
                                Text(student.initials)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            )
                            .frame(width: 40, height: 40)
                        Text(student.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    EmptyPanel(systemImage: "star", text: "Not yet selected.")
                }
            }
        }
    }

    private var attendancePercentage: String {
        let total = session.attendeeIds.count
        guard total > 0 else { return "—" }
        let pct = Int((Double(session.actualAttendeeIds.count) / Double(total)) * 100)
        return "\(pct)%"
    }

    private var ratingDisplay: String {
        if let rating = session.rating { return "\(rating) / 5" }
        return "—"
    }
}
