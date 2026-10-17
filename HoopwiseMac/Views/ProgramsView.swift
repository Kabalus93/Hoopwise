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
    @State private var showingEdit = false
    @State private var showingRoster = false
    @State private var confirmingDelete = false
    @State private var renamingPhase: MicroCycle?
    @State private var phaseNameDraft = ""
    @AppStorage("settings.confirmBeforeDelete") private var confirmBeforeDelete = true

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
                programActionBar
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

    /// Sessions referencing the program block deletion — archive instead,
    /// so history stays intact. The same rule iOS's data model implies:
    /// sessions carry programId and orphaning them corrupts attendance
    /// context.
    private var referencedBySessions: Bool {
        dataManager.sessionEvents.contains { $0.programId == program.id }
    }

    private var programActionBar: some View {
        HStack(spacing: 8) {
            Button {
                showingEdit = true
            } label: {
                Label("Edit…", systemImage: "square.and.pencil")
            }
            Button {
                showingRoster = true
            } label: {
                Label("Roster…", systemImage: "person.badge.plus")
            }
            if program.status != .archived {
                Button {
                    var copy = program
                    copy.status = .archived
                    copy.updatedAt = Date()
                    dataManager.updateProgram(copy)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else {
                Button {
                    var copy = program
                    copy.status = .active
                    copy.updatedAt = Date()
                    dataManager.updateProgram(copy)
                } label: {
                    Label("Unarchive", systemImage: "arrow.up.bin")
                }
            }
            Spacer()
            Button(role: .destructive) {
                if confirmBeforeDelete { confirmingDelete = true }
                else { dataManager.deleteProgram(program) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(referencedBySessions)
            .help(referencedBySessions
                  ? "Sessions reference this program — archive it instead."
                  : "Delete program")
            .confirmationDialog("Delete \"\(program.name)\"?",
                                isPresented: $confirmingDelete) {
                Button("Delete Program", role: .destructive) {
                    dataManager.deleteProgram(program)
                }
            }
        }
        .controlSize(.large)
        .sheet(isPresented: $showingEdit) {
            ProgramEditSheet(program: program)
                .dismissesOnPresentationEscape { showingEdit = false }
        }
        .sheet(isPresented: $showingRoster) {
            ProgramRosterSheet(program: program)
                .dismissesOnPresentationEscape { showingRoster = false }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button {
                    // Same MicroCycle records iOS creates; next number in line.
                    let next = (phases.map(\.phaseNumber).max() ?? 0) + 1
                    dataManager.addMicroCycle(MicroCycle(programId: program.id,
                                                         phaseNumber: next,
                                                         title: "Phase \(next)"))
                } label: {
                    Label("Add Phase", systemImage: "plus")
                }
                .controlSize(.small)
            }
            if phases.isEmpty {
                EmptyPanel(systemImage: "rectangle.stack", text: "No phases yet.")
            } else {
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
                    .contextMenu {
                        Button("Rename…") {
                            renamingPhase = phase
                            phaseNameDraft = phase.title
                        }
                        Button("Move Up") { movePhase(phase, direction: -1) }
                            .disabled(phase.id == phases.first?.id)
                        Button("Move Down") { movePhase(phase, direction: 1) }
                            .disabled(phase.id == phases.last?.id)
                        Divider()
                        Button("Delete Phase", role: .destructive) {
                            dataManager.deleteMicroCycle(phase)
                        }
                    }
                }
            }
        }
        .alert("Rename Phase", isPresented: Binding(
            get: { renamingPhase != nil },
            set: { if !$0 { renamingPhase = nil } })) {
            TextField("Title", text: $phaseNameDraft)
            Button("Cancel", role: .cancel) { renamingPhase = nil }
            Button("Rename") {
                if var phase = renamingPhase {
                    phase.title = phaseNameDraft
                    phase.updatedAt = Date()
                    dataManager.updateMicroCycle(phase)
                }
                renamingPhase = nil
            }
        }
    }

    /// Reorder = swap phaseNumbers with the neighbour — the ordering field
    /// iOS sorts by, so both platforms agree on sequence.
    private func movePhase(_ phase: MicroCycle, direction: Int) {
        guard let index = phases.firstIndex(where: { $0.id == phase.id }) else { return }
        let target = index + direction
        guard target >= 0, target < phases.count else { return }
        var a = phases[index], b = phases[target]
        swap(&a.phaseNumber, &b.phaseNumber)
        a.updatedAt = Date(); b.updatedAt = Date()
        dataManager.updateMicroCycle(a)
        dataManager.updateMicroCycle(b)
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
                            if let grade = student.currentSchoolGrade() {
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


// MARK: - Program editing

/// Small transaction per Done; one undo step. Writes the SAME Program
/// record iOS reads — no Mac-only fields.
struct ProgramEditSheet: View {
    let program: Program
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var ageGroup: AgeGroup = .u10
    @State private var programType: ProgramType = .group
    @State private var status: ProgramStatus = .active
    @State private var recurringDays: Set<Weekday> = []
    @State private var loaded = false

    var body: some View {
        MacSheetChrome(title: "Edit Program") { dismiss() } content: {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $descriptionText, axis: .vertical)
                Picker("Type", selection: $programType) {
                    ForEach(ProgramType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Age band", selection: $ageGroup) {
                    ForEach(AgeGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Status", selection: $status) {
                    ForEach(ProgramStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Section("Schedule") {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Toggle(day.displayName, isOn: Binding(
                            get: { recurringDays.contains(day) },
                            set: { on in
                                if on { recurringDays.insert(day) } else { recurringDays.remove(day) }
                            }))
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Done") { commit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 480)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = program.name
            descriptionText = program.description ?? ""
            ageGroup = program.ageGroup
            programType = program.programType
            status = program.status
            recurringDays = Set(program.recurringDays)
        }
    }

    private func commit() {
        let old = program
        var copy = program
        copy.name = name.trimmingCharacters(in: .whitespaces)
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.description = trimmed.isEmpty ? nil : trimmed
        copy.ageGroup = ageGroup
        copy.programType = programType
        copy.status = status
        copy.recurringDays = Array(recurringDays)
        copy.updatedAt = Date()
        dataManager.updateProgram(copy)
        undoManager?.registerUndo(withTarget: dataManager) { manager in
            manager.updateProgram(old)
        }
        undoManager?.setActionName("Edit Program")
        dismiss()
    }
}

/// Program roster editor — the SAME relation as the athlete card's program
/// picker, through the one shared enrollment writer.
struct ProgramRosterSheet: View {
    let program: Program
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        MacSheetChrome(title: "Roster — \(program.name)") { dismiss() } content: {
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
                        let enrolled = isEnrolled(student)
                        HStack(spacing: 10) {
                            AthletePhoto(imageData: student.thumbnailImageData ?? student.profileImageData,
                                         initials: student.initials,
                                         color: Color.avatarColor(student.avatarColor),
                                         size: 26)
                            Text(student.displayName)
                            if let chinese = student.secondaryNameLine {
                                Text(chinese).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if enrolled {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dataManager.setStudentEnrollment(
                                studentId: student.id,
                                programId: enrolled ? nil : program.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 440, minHeight: 460)
        }
    }

    private func isEnrolled(_ student: Student) -> Bool {
        program.enrolledStudentIds.contains(student.id) || student.programId == program.id
    }

    private var filtered: [Student] {
        let base = dataManager.students
        guard !search.isEmpty else { return base.sorted { $0.name < $1.name } }
        return base.filter {
            NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(search)
        }.sorted { $0.name < $1.name }
    }
}
