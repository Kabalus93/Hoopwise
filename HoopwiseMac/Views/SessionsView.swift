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
        switch session.status {
        case .scheduled:
            Button("Start Session", systemImage: "play.fill") { mutate(session) { $0.status = .inProgress } }
        case .inProgress:
            Button("Complete", systemImage: "checkmark.circle") { mutate(session) { $0.status = .completed } }
        default:
            EmptyView()
        }
        if session.status != .cancelled {
            Button("Cancel Session", systemImage: "xmark.circle", role: .destructive) {
                mutate(session) { $0.status = .cancelled }
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
        case .upcoming: base = dataManager.sessionEvents.filter { $0.date >= now && $0.status != .cancelled }
        case .past:     base = dataManager.sessionEvents.filter { $0.date < now || $0.status == .completed || $0.status == .cancelled }
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

    private var actionBar: some View {
        HStack(spacing: 8) {
            primaryActionButton
            Button {
                mutate { $0.status = .cancelled }
            } label: {
                Label("Cancel Session", systemImage: "xmark.circle")
            }
            .disabled(session.status == .cancelled || session.status == .completed)

            Spacer()

            Button(role: .destructive) {
                dataManager.deleteSessionEvent(session)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch session.status {
        case .scheduled:
            Button {
                mutate { $0.status = .inProgress }
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        case .inProgress:
            Button {
                mutate { $0.status = .completed }
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        case .completed:
            Button {
                mutate { $0.status = .scheduled }
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward.circle")
            }
        case .cancelled, .skipped:
            Button {
                mutate { $0.status = .scheduled }
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
        .sheet(isPresented: $showingPicker) { DrillPickerSheet(session: session) }
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

    private var roster: [Student] {
        var ids = Set(session.attendeeIds)
        if ids.isEmpty, let pid = session.programId,
           let program = dataManager.programs.first(where: { $0.id == pid }) {
            ids = Set(program.enrolledStudentIds)
        }
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
                    setAllPresent()
                } label: {
                    Label("Mark All Present", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(roster.isEmpty)

                Button {
                    clearAttendance()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session.actualAttendeeIds.isEmpty && session.excusedAbsences.isEmpty)
            }

            if roster.isEmpty {
                EmptyPanel(systemImage: "person.2", text: "No athletes assigned to this session yet.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(roster) { student in
                        AttendeeCell(
                            student: student,
                            state: state(for: student.id),
                            onCycle: { cycle(student.id) }
                        )
                    }
                }
            }
        }
    }

    private enum AttendeeState { case unmarked, present, excused }

    private func state(for id: UUID) -> AttendeeState {
        if session.actualAttendeeIds.contains(id) { return .present }
        if session.excusedAbsences.contains(id) { return .excused }
        return .unmarked
    }

    private func cycle(_ id: UUID) {
        var copy = session
        switch state(for: id) {
        case .unmarked:
            copy.actualAttendeeIds.append(id)
        case .present:
            copy.actualAttendeeIds.removeAll { $0 == id }
            copy.excusedAbsences.append(id)
        case .excused:
            copy.excusedAbsences.removeAll { $0 == id }
        }
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }

    private func setAllPresent() {
        var copy = session
        copy.actualAttendeeIds = roster.map(\.id)
        copy.excusedAbsences = []
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }

    private func clearAttendance() {
        var copy = session
        copy.actualAttendeeIds = []
        copy.excusedAbsences = []
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
    }

    private struct AttendeeCell: View {
        let student: Student
        let state: AttendeeState
        let onCycle: () -> Void

        var body: some View {
            Button(action: onCycle) {
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
                        Text(student.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(stateLabel)
                            .font(.caption2)
                            .foregroundStyle(stateTint)
                    }
                    Spacer()
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateTint)
                        .font(.title3)
                }
                .padding(10)
                .background(stateBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stateTint.opacity(state == .unmarked ? 0.0 : 0.3), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var stateLabel: String {
            switch state {
            case .unmarked: return "Tap to mark present"
            case .present: return "Present"
            case .excused: return "Excused"
            }
        }
        private var stateIcon: String {
            switch state {
            case .unmarked: return "circle.dashed"
            case .present: return "checkmark.circle.fill"
            case .excused: return "minus.circle.fill"
            }
        }
        private var stateTint: Color {
            switch state {
            case .unmarked: return .secondary
            case .present: return .green
            case .excused: return .orange
            }
        }
        private var stateBackground: AnyShapeStyle {
            switch state {
            case .unmarked: return AnyShapeStyle(Material.regular)
            case .present: return AnyShapeStyle(Color.green.opacity(0.10))
            case .excused: return AnyShapeStyle(Color.orange.opacity(0.10))
            }
        }
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
