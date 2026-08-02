import SwiftUI

// MARK: - Programs
struct ProgramsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selected: Program.ID?
    @State private var search = ""
    @State private var filter: StatusFilter = .all
    @State private var showingNew = false

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, active, draft, archived
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        // HSplitView, not a nested NavigationSplitView: a second split-view
        // controller inside RootView's re-bridges its own toolbar during page
        // switches, and with concurrent invalidation (e.g. avatar preloads
        // landing mid-transition) AppKit's update-constraints pass livelocks
        // — the "more Update Constraints in Window passes than there are
        // views" crash. Same two-pane layout, no second NSSplitViewController.
        HSplitView {
            sidebar
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
                .frame(maxHeight: .infinity)
            Group {
                if let id = selected, let program = dataManager.programs.first(where: { $0.id == id }) {
                    ProgramDetailView(program: program).id(program.id)
                } else {
                    EmptyDetail(systemImage: "list.clipboard", title: "Select a Program")
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { autoSelect() }
        .onChange(of: filter) { _, _ in autoSelect() }
        .sheet(isPresented: $showingNew) {
            NewProgramSheet()
                .dismissesOnPresentationEscape { showingNew = false }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search programs", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            Picker("Filter", selection: $filter) {
                ForEach(StatusFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            List(selection: $selected) {
                if filtered.isEmpty {
                    Text("No programs match.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(filtered) { program in
                        ProgramListRow(program: program)
                            .tag(program.id)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(program)
                                }
                            }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Programs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("New Program", systemImage: "plus")
                }
            }
        }
    }

    private var filtered: [Program] {
        let base: [Program]
        switch filter {
        case .all: base = dataManager.programs
        case .active: base = dataManager.programs.filter { $0.status == .active }
        case .draft: base = dataManager.programs.filter { $0.status == .draft }
        case .archived: base = dataManager.programs.filter { $0.status == .archived || $0.status == .completed }
        }
        let searched = search.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return searched.sorted { $0.name < $1.name }
    }

    private func autoSelect() {
        if let s = selected, dataManager.programs.contains(where: { $0.id == s }) { return }
        selected = filtered.first?.id
    }

    private func delete(_ program: Program) {
        var copy = program
        copy.status = .archived
        copy.updatedAt = Date()
        dataManager.updateProgram(copy)
    }
}

private struct ProgramListRow: View {
    let program: Program
    @EnvironmentObject var dataManager: DataManager
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: program.colorHex)).frame(width: 28, height: 28)
                .overlay(Image(systemName: program.programType.icon).font(.caption.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(program.ageGroup.displayName).font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(program.enrolledStudentIds.count) athletes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusPill
        }
        .padding(.vertical, 2)
    }
    private var statusPill: some View {
        Text(program.status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }
    private var tint: Color {
        switch program.status {
        case .active: return .green
        case .draft: return .orange
        case .completed: return .blue
        case .archived: return .gray
        }
    }
}

// MARK: - Detail

private struct ProgramDetailView: View {
    let program: Program
    @EnvironmentObject var dataManager: DataManager
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview, phases, athletes, sessions
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .overview: return "info.circle"
            case .phases: return "rectangle.stack"
            case .athletes: return "person.2"
            case .sessions: return "calendar"
            }
        }
    }

    private var phases: [MicroCycle] {
        dataManager.microCycles.filter { $0.programId == program.id }.sorted { $0.phaseNumber < $1.phaseNumber }
    }
    private var athletes: [Student] {
        dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    private var sessions: [SessionEvent] {
        dataManager.sessionEvents.filter { $0.programId == program.id }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                statRow

                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Label(t.label, systemImage: t.systemImage).tag(t)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()

                Group {
                    switch tab {
                    case .overview: overviewTab
                    case .phases: phasesTab
                    case .athletes: athletesTab
                    case .sessions: sessionsTab
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(program.name)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: program.colorHex).gradient)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: program.programType.icon).font(.system(size: 32, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(program.name).font(.system(size: 28, weight: .bold))
                HStack(spacing: 12) {
                    Label(program.programType.displayName, systemImage: program.programType.icon)
                    Label(program.ageGroup.displayName, systemImage: "person.crop.circle")
                    Label("\(program.durationWeeks) weeks", systemImage: "calendar")
                }
                .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
            Spacer()
        }
    }

    private var statRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatPill(title: "Status", value: program.status.displayName)
            StatPill(title: "Athletes", value: "\(program.enrolledStudentIds.count)")
            StatPill(title: "Phases", value: "\(phases.count)")
            StatPill(title: "Sessions", value: "\(sessions.count)")
        }
    }

    @ViewBuilder
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = program.description, !description.isEmpty {
                SectionBlock(title: "Description") {
                    Text(description).font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            SectionBlock(title: "Schedule") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.shortName)
                                .font(.caption2.weight(.semibold))
                                .frame(width: 36, height: 26)
                                .background(program.recurringDays.contains(day) ? Color.accentColor.opacity(0.18) : Color.clear, in: .capsule)
                                .foregroundStyle(program.recurringDays.contains(day) ? Color.accentColor : .secondary)
                        }
                    }
                    if let start = program.startDate {
                        Label {
                            Text(start, format: .dateTime.month().day().year())
                            if let end = program.endDate {
                                Text(" – ").foregroundStyle(.tertiary)
                                Text(end, format: .dateTime.month().day().year())
                            }
                        } icon: { Image(systemName: "calendar.badge.clock") }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !program.objectives.isEmpty {
                SectionBlock(title: "Objectives") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(program.objectives, id: \.self) { obj in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                                Text(obj).font(.subheadline)
                                Spacer()
                            }
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var phasesTab: some View {
        if phases.isEmpty {
            EmptyPanel(systemImage: "rectangle.stack", text: "No phases yet. Create phases on iOS to plan training cycles.")
        } else {
            VStack(spacing: 10) {
                ForEach(phases) { phase in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(phase.phaseNumber)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.title).font(.subheadline.weight(.semibold))
                            HStack(spacing: 10) {
                                Label("\(phase.durationWeeks) wks", systemImage: "calendar")
                                Label("Intensity \(phase.intensity)", systemImage: "flame")
                                Label("Volume \(phase.volume)", systemImage: "speedometer")
                            }
                            .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                            if !phase.focus.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(phase.focus, id: \.self) { f in
                                        Text(f.rawValue.capitalized)
                                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.quaternary, in: .capsule)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var athletesTab: some View {
        if athletes.isEmpty {
            EmptyPanel(systemImage: "person.2", text: "No athletes enrolled yet.")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(athletes) { student in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.avatarColor(student.avatarColor))
                            .overlay(Text(student.initials).font(.caption.weight(.bold)).foregroundStyle(.white))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                            if let grade = student.schoolGrade {
                                Text(grade.shortName).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var sessionsTab: some View {
        if sessions.isEmpty {
            EmptyPanel(systemImage: "calendar", text: "No sessions scheduled.")
        } else {
            VStack(spacing: 6) {
                ForEach(sessions) { session in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.date, format: .dateTime.month().day().year())
                                .font(.caption.weight(.medium))
                            Text(session.startTime, format: .dateTime.hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 96, alignment: .leading)
                        Text(session.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(session.status.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}
