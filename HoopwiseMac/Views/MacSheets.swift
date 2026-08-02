import SwiftUI

// MARK: - Sheet chrome
//
// The anti-trap contract for presented surfaces: every sheet shows an
// explicit close affordance top-right; Esc dismisses through the
// PresentationKeyDispatcher (dispatch layer), not per-sheet handlers;
// popover-like surfaces use real popovers, which click-out natively.
struct MacSheetChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            content()
        }
        .dismissesOnPresentationEscape(onClose)
    }
}

extension View {
    /// Opts a presented sheet into the app-wide Esc rule: the dispatch layer
    /// posts when Esc lands on a sheet window; the presenting binding clears
    /// here. Only one sheet is ever up, so the broadcast is unambiguous.
    func dismissesOnPresentationEscape(_ close: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default
            .publisher(for: .macDismissPresentedSurface)) { _ in close() }
    }
}

// MARK: - New Athlete Sheet
/// Creates a Student + paired Player. Save is disabled until name is non-empty.
/// Trims whitespace, prevents duplicate names (case-insensitive) within the
/// current dataset, and defaults sensible values.
struct NewAthleteSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var chineseName: String = ""
    @State private var schoolGrade: SchoolGrade? = nil
    @State private var avatarColor: AvatarColor = .blue
    @State private var programId: UUID? = nil
    @State private var birthYear: Int? = nil
    @State private var birthMonth: Int? = nil

    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedChinese: String { chineseName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && error == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Identity") {
                    TextField("English name", text: $name)
                        .onChange(of: name) { _, _ in revalidate() }
                    TextField("Chinese name (optional)", text: $chineseName)
                        .onChange(of: chineseName) { _, _ in revalidate() }
                }
                Section("Education") {
                    Picker("School grade", selection: $schoolGrade) {
                        Text("Not set").tag(SchoolGrade?.none)
                        ForEach(SchoolGrade.allCases, id: \.self) { g in
                            Text(g.displayName).tag(Optional(g))
                        }
                    }
                }
                Section("Birth (optional)") {
                    HStack {
                        Picker("Year", selection: $birthYear) {
                            Text("—").tag(Int?.none)
                            ForEach(yearChoices, id: \.self) { y in
                                Text(String(y)).tag(Optional(y))
                            }
                        }
                        Picker("Month", selection: $birthMonth) {
                            Text("—").tag(Int?.none)
                            ForEach(1...12, id: \.self) { m in
                                Text(monthName(m)).tag(Optional(m))
                            }
                        }
                    }
                }
                Section("Style") {
                    Picker("Avatar color", selection: $avatarColor) {
                        ForEach(AvatarColor.allCases, id: \.self) { c in
                            Label(c.displayName, systemImage: "circle.fill").tag(c)
                        }
                    }
                }
                Section("Program (optional)") {
                    Picker("Enrolled program", selection: $programId) {
                        Text("Not enrolled").tag(UUID?.none)
                        ForEach(dataManager.programs) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.orange.opacity(0.08))
            }

            footer
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Athlete").font(.title2.weight(.semibold))
                Text("Create a roster entry. They'll be ready to enroll in a program.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add Athlete") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(16)
    }

    private var yearChoices: [Int] {
        let now = Calendar.current.component(.year, from: Date())
        return Array((now - 30)...now).reversed()
    }

    private func monthName(_ m: Int) -> String {
        DateFormatter().monthSymbols[m - 1]
    }

    private func revalidate() {
        let normalized = trimmedName.lowercased()
        if !normalized.isEmpty,
           dataManager.students.contains(where: { $0.name.lowercased() == normalized }) {
            error = "An athlete named \"\(trimmedName)\" already exists."
        } else {
            error = nil
        }
    }

    private func save() {
        guard canSave else { return }
        let now = Date()
        var birthdate: Date? = nil
        if let y = birthYear, let m = birthMonth, let d = Calendar.current.date(from: DateComponents(year: y, month: m, day: 1)) {
            birthdate = d
        }
        let student = Student(
            name: trimmedName,
            chineseName: trimmedChinese.isEmpty ? nil : trimmedChinese,
            avatarColor: avatarColor,
            programId: programId,
            birthdate: birthdate,
            birthMonth: birthMonth,
            birthYear: birthYear,
            schoolGrade: schoolGrade,
            createdByCoachId: dataManager.loggedInCoachId,
            createdAt: now,
            updatedAt: now
        )
        let player = Player(studentId: student.id)
        dataManager.addStudent(student, player: player)

        if let pid = programId, var program = dataManager.programs.first(where: { $0.id == pid }) {
            if !program.enrolledStudentIds.contains(student.id) {
                program.enrolledStudentIds.append(student.id)
                program.updatedAt = now
                dataManager.updateProgram(program)
            }
        }
        dismiss()
    }
}

// MARK: - New Session Sheet

struct NewSessionSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = Self.defaultStart()
    @State private var durationMinutes: Int = 90
    @State private var location: String = ""
    @State private var locationId: UUID? = nil
    @State private var programId: UUID? = nil
    @State private var sessionType: SessionType = .training
    @State private var attendeeIds: Set<UUID> = []

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && durationMinutes > 0
    }

    private var endTime: Date {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: date) ?? date
    }

    private var enrolledFromProgram: [Student] {
        guard let pid = programId, let program = dataManager.programs.first(where: { $0.id == pid }) else { return [] }
        return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }

    private var availableStudents: [Student] {
        if !enrolledFromProgram.isEmpty { return enrolledFromProgram }
        return dataManager.students.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Session").font(.title2.weight(.semibold))
                    Text("Schedule a training session, attach a program, and pick attendees.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            Form {
                Section("Title") {
                    TextField("Session title", text: $title)
                    Picker("Type", selection: $sessionType) {
                        ForEach(SessionType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                }
                Section("When") {
                    DatePicker("Start", selection: $date)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                    HStack {
                        Text("Ends at").foregroundStyle(.secondary)
                        Text(endTime, format: .dateTime.hour().minute()).font(.callout.monospacedDigit())
                    }
                }
                Section("Where") {
                    Picker("Saved location", selection: $locationId) {
                        Text("Custom").tag(UUID?.none)
                        ForEach(dataManager.locations) { l in
                            Text(l.name).tag(Optional(l.id))
                        }
                    }
                    .onChange(of: locationId) { _, newValue in
                        if let id = newValue, let loc = dataManager.locations.first(where: { $0.id == id }) {
                            location = loc.name
                        }
                    }
                    TextField("Location label", text: $location)
                }
                Section("Program (optional)") {
                    Picker("Program", selection: $programId) {
                        Text("Standalone").tag(UUID?.none)
                        ForEach(dataManager.programs) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .onChange(of: programId) { _, _ in
                        // Reset attendees when program scope changes
                        attendeeIds = Set(enrolledFromProgram.map(\.id))
                    }
                }
                Section("Attendees (\(attendeeIds.count))") {
                    if availableStudents.isEmpty {
                        Text("No athletes available.").foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 6) {
                                ForEach(availableStudents) { student in
                                    AttendeeToggleRow(
                                        student: student,
                                        isOn: Binding(
                                            get: { attendeeIds.contains(student.id) },
                                            set: { newValue in
                                                if newValue { attendeeIds.insert(student.id) }
                                                else { attendeeIds.remove(student.id) }
                                            }
                                        )
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        HStack {
                            Button("Select all") { attendeeIds = Set(availableStudents.map(\.id)) }
                            Button("Clear") { attendeeIds.removeAll() }
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Session") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let now = Date()
        // Snap to next 15 minutes
        let minute = cal.component(.minute, from: now)
        let bump = (15 - (minute % 15)) % 15
        return cal.date(byAdding: .minute, value: bump == 0 ? 15 : bump, to: now) ?? now
    }

    private func save() {
        guard canSave else { return }
        let now = Date()
        let session = SessionEvent(
            id: UUID(),
            programId: programId,
            sessionType: sessionType,
            title: trimmedTitle,
            date: date,
            startTime: date,
            endTime: endTime,
            location: location.isEmpty ? nil : location,
            attendeeIds: Array(attendeeIds),
            createdByCoachId: dataManager.loggedInCoachId,
            createdAt: now,
            updatedAt: now
        )
        dataManager.addSessionEvent(session)
        dismiss()
    }
}

private struct AttendeeToggleRow: View {
    let student: Student
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Circle().fill(Color.avatarColor(student.avatarColor))
                    .overlay(Text(student.initials).font(.caption2.weight(.bold)).foregroundStyle(.white))
                    .frame(width: 22, height: 22)
                Text(student.displayName).font(.caption).lineLimit(1)
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - New Program Sheet

struct NewProgramSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var programType: ProgramType = .group
    @State private var ageGroup: AgeGroup = .u12
    @State private var durationWeeks: Int = 12
    @State private var coachId: UUID? = nil
    @State private var locationId: UUID? = nil
    @State private var startDate: Date = Date()
    @State private var description: String = ""
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && error == nil && durationWeeks > 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Program").font(.title2.weight(.semibold))
                    Text("Programs hold phases, athletes, and recurring sessions.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            Form {
                Section("Identity") {
                    TextField("Program name", text: $name)
                        .onChange(of: name) { _, _ in revalidate() }
                    Picker("Type", selection: $programType) {
                        ForEach(ProgramType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                    Picker("Age group", selection: $ageGroup) {
                        ForEach(AgeGroup.allCases, id: \.self) { g in
                            Text(g.displayName).tag(g)
                        }
                    }
                }
                Section("Schedule") {
                    Stepper("Duration: \(durationWeeks) weeks", value: $durationWeeks, in: 1...52)
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }
                Section("Assignments") {
                    Picker("Lead coach", selection: $coachId) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(dataManager.staffCoaches) { c in
                            Text(c.displayName).tag(Optional(c.id))
                        }
                    }
                    Picker("Default location", selection: $locationId) {
                        Text("None").tag(UUID?.none)
                        ForEach(dataManager.locations) { l in
                            Text(l.name).tag(Optional(l.id))
                        }
                    }
                }
                Section("Description") {
                    TextEditor(text: $description).frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.orange.opacity(0.08))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Program") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 580)
    }

    private func revalidate() {
        let lower = trimmedName.lowercased()
        if !lower.isEmpty, dataManager.programs.contains(where: { $0.name.lowercased() == lower }) {
            error = "A program named \"\(trimmedName)\" already exists."
        } else {
            error = nil
        }
    }

    private func save() {
        guard canSave else { return }
        let now = Date()
        let locationName = locationId.flatMap { id in dataManager.locations.first(where: { $0.id == id })?.name }
        let program = Program(
            name: trimmedName,
            programType: programType,
            ageGroup: ageGroup,
            durationWeeks: durationWeeks,
            description: description.isEmpty ? nil : description,
            coachId: coachId,
            createdByCoachId: dataManager.loggedInCoachId,
            status: .draft,
            startDate: startDate,
            createdAt: now,
            updatedAt: now,
            locationId: locationId,
            locationName: locationName
        )
        dataManager.addProgram(program)
        dismiss()
    }
}

// MARK: - New Team Sheet

struct NewTeamSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var shortName: String = ""
    @State private var colorHex: String = "#E94560"
    @State private var coachId: UUID? = nil
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedShort: String { shortName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedShort.count >= 2 && trimmedShort.count <= 4 && error == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Team").font(.title2.weight(.semibold))
                    Text("Teams compete in games and have rosters drawn from your athletes.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            Form {
                Section("Identity") {
                    TextField("Team name", text: $name).onChange(of: name) { _, _ in revalidate() }
                    TextField("Short name (2–4 letters)", text: $shortName)
                        .onChange(of: shortName) { _, _ in revalidate() }
                }
                Section("Style") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }
                Section("Coach") {
                    Picker("Lead coach", selection: $coachId) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(dataManager.staffCoaches) { c in
                            Text(c.displayName).tag(Optional(c.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.orange.opacity(0.08))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Team") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 460)
    }

    private func revalidate() {
        let lower = trimmedName.lowercased()
        if !lower.isEmpty, dataManager.teams.contains(where: { $0.name.lowercased() == lower }) {
            error = "A team named \"\(trimmedName)\" already exists."
            return
        }
        if !trimmedShort.isEmpty, dataManager.teams.contains(where: { $0.shortName.uppercased() == trimmedShort }) {
            error = "Short name \"\(trimmedShort)\" is already in use."
            return
        }
        error = nil
    }

    private func save() {
        guard canSave else { return }
        let team = Team(
            name: trimmedName,
            shortName: trimmedShort,
            colorHex: colorHex,
            coachId: coachId,
            createdByCoachId: dataManager.loggedInCoachId
        )
        dataManager.addTeam(team)
        dismiss()
    }
}

// MARK: - New Game Sheet

struct NewGameSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var date: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var venue: String = ""
    @State private var error: String?

    private var canSave: Bool {
        homeTeamId != nil && awayTeamId != nil && homeTeamId != awayTeamId && error == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Game").font(.title2.weight(.semibold))
                    Text("Schedule a matchup between two of your teams.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            Form {
                Section("Matchup") {
                    Picker("Home", selection: $homeTeamId) {
                        Text("Select home").tag(UUID?.none)
                        ForEach(dataManager.teams) { t in
                            Text(t.name).tag(Optional(t.id))
                        }
                    }
                    .onChange(of: homeTeamId) { _, _ in revalidate() }
                    Picker("Away", selection: $awayTeamId) {
                        Text("Select away").tag(UUID?.none)
                        ForEach(dataManager.teams) { t in
                            Text(t.name).tag(Optional(t.id))
                        }
                    }
                    .onChange(of: awayTeamId) { _, _ in revalidate() }
                }
                Section("Where & When") {
                    DatePicker("Tip-off", selection: $date)
                    TextField("Venue", text: $venue)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.orange.opacity(0.08))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Schedule Game") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func revalidate() {
        if let h = homeTeamId, let a = awayTeamId, h == a {
            error = "Home and away teams must differ."
        } else {
            error = nil
        }
    }

    private func save() {
        guard let h = homeTeamId, let a = awayTeamId, h != a else { return }
        let game = Game(
            homeTeamId: h,
            awayTeamId: a,
            date: date,
            venue: venue.isEmpty ? nil : venue
        )
        dataManager.addGame(game)
        dismiss()
    }
}

// MARK: - Color Swatch Picker

private struct ColorSwatchPicker: View {
    @Binding var selectedHex: String
    private let swatches: [String] = [
        "#E94560", "#F97316", "#FACC15", "#22C55E", "#10B981",
        "#06B6D4", "#3B82F6", "#6366F1", "#8B5CF6", "#EC4899",
        "#1F2937", "#7C2D12"
    ]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(swatches, id: \.self) { hex in
                Button { selectedHex = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle().strokeBorder(selectedHex == hex ? Color.primary : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
