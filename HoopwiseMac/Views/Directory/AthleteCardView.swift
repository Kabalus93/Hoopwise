import SwiftUI
import AppKit

// MARK: - Athlete draft (edit mode's working copy)

/// Everything the card can edit, drafted so Esc discards and Done commits in
/// one undoable step. Contact fields live on the Player's ParentInfo.
struct AthleteDraft {
    var name = ""
    var chineseName = ""
    var schoolGrade: SchoolGrade?
    var programId: UUID?
    var parentName = ""
    var parentRelation = "Parent"
    var parentPhone = ""
    var parentEmail = ""
    var parentWechat = ""

    init() {}

    init(student: Student, player: Player?) {
        name = student.name
        chineseName = student.chineseName ?? ""
        schoolGrade = student.currentSchoolGrade()
        programId = student.programId
        if let info = player?.parentInfo {
            parentName = info.name
            parentRelation = info.relationship
            parentPhone = info.phone
            parentEmail = info.email ?? ""
            parentWechat = info.wechatId ?? ""
        }
    }

    func apply(to student: Student) -> Student {
        var copy = student
        copy.name = name.trimmingCharacters(in: .whitespaces)
        let chinese = chineseName.trimmingCharacters(in: .whitespaces)
        copy.chineseName = chinese.isEmpty ? nil : chinese
        // Re-anchor only on a real change: the draft starts from the CURRENT
        // grade, so an untouched picker must not rewrite the birthdate.
        if schoolGrade != student.currentSchoolGrade() { copy.setSchoolGrade(schoolGrade) }
        copy.programId = programId
        copy.updatedAt = Date()
        return copy
    }

    func parentInfo(existing: ParentInfo) -> ParentInfo {
        var info = existing
        info.name = parentName.trimmingCharacters(in: .whitespaces)
        info.relationship = parentRelation
        info.phone = parentPhone.trimmingCharacters(in: .whitespaces)
        let email = parentEmail.trimmingCharacters(in: .whitespaces)
        info.email = email.isEmpty ? nil : email
        let wechat = parentWechat.trimmingCharacters(in: .whitespaces)
        info.wechatId = wechat.isEmpty ? nil : wechat
        return info
    }

    func makeStudent() -> Student {
        var student = Student(name: name.trimmingCharacters(in: .whitespaces))
        let chinese = chineseName.trimmingCharacters(in: .whitespaces)
        student.chineseName = chinese.isEmpty ? nil : chinese
        student.setSchoolGrade(schoolGrade)
        student.programId = programId
        return student
    }

    func makePlayer(studentId: UUID) -> Player {
        Player(studentId: studentId, parentInfo: parentInfo(existing: ParentInfo()))
    }
}

// MARK: - Athlete card
//
// Contacts' card logic with Hoopwise content: header, calm stat strip,
// segmented tabs, and a read-mode Overview of labeled field groups. Edit is
// EXPLICIT — the card never live-edits in read mode.
struct AthleteCardView: View {
    /// Nil only for the new-athlete flow.
    let student: Student?
    @Binding var draft: AthleteDraft?
    let isNew: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onOpenSession: (UUID) -> Void

    @EnvironmentObject var dataManager: DataManager
    @State private var tab: AthleteDetailView.DetailTab = .overview
    @FocusState private var nameFieldFocused: Bool
    @State private var confirmingDelete = false
    @AppStorage("settings.confirmBeforeDelete") private var confirmBeforeDelete = true

    private var isEditing: Bool { draft != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !isEditing {
                    statStrip
                    Picker("Section", selection: $tab) {
                        ForEach(AthleteDetailView.DetailTab.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    tabContent
                } else {
                    editGroups
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if isNew { nameFieldFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let student {
                EditAvatarButton(
                    currentData: student.profileImageData,
                    initials: student.initials,
                    avatarColor: student.avatarColor,
                    size: 76,
                    onPicked: { data in
                        var copy = student
                        copy.profileImageData = data
                        copy.thumbnailImageData = data
                        copy.updatedAt = Date()
                        dataManager.updateStudent(copy)
                    },
                    onCleared: {
                        var copy = student
                        copy.profileImageData = nil
                        copy.thumbnailImageData = nil
                        copy.updatedAt = Date()
                        dataManager.updateStudent(copy)
                    }
                )
            } else {
                DirectoryAvatar(imageData: nil, initials: "?",
                                color: .gray.opacity(0.5), size: 76)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let working = draft {
                    TextField("Name", text: Binding(
                        get: { working.name }, set: { draft?.name = $0 }))
                        .font(.system(size: 24, weight: .bold))
                        .textFieldStyle(.plain)
                        .focused($nameFieldFocused)
                    TextField("中文名", text: Binding(
                        get: { working.chineseName }, set: { draft?.chineseName = $0 }))
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.secondary)
                } else if let student {
                    HStack(spacing: 10) {
                        Text(student.displayName)
                            .font(.system(size: 24, weight: .bold))
                        if let chinese = student.secondaryNameLine {
                            Text(chinese).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        if let grade = student.currentSchoolGrade() {
                            chip(grade.displayName, systemImage: "graduationcap")
                        }
                        if let contract = dataManager.currentContract(for: student.id) {
                            chip(contract.status.rawValue, systemImage: "doc.text")
                        }
                        if let age = student.age {
                            chip("\(age) yrs", systemImage: "calendar")
                        }
                    }
                }
            }
            Spacer()

            // Explicit edit mode — the core Contacts behaviour. fixedSize so
            // a long name compresses, never the controls.
            if isEditing {
                HStack(spacing: 8) {
                    Button("Cancel") { onCancel() }
                    Button("Done") { onCommit() }
                        .buttonStyle(.borderedProminent)
                        .disabled((draft?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                                  && (draft?.chineseName.trimmingCharacters(in: .whitespaces).isEmpty ?? true))
                }
                .fixedSize()
            } else if let student {
                HStack(spacing: 8) {
                    Menu {
                        Button("Delete Athlete", systemImage: "trash",
                               role: .destructive) {
                            // iOS convention checked: deleteStudent is a HARD
                            // delete cascading contracts and player. Confirm
                            // unless the preference says otherwise.
                            if confirmBeforeDelete { confirmingDelete = true }
                            else { onDelete() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .confirmationDialog(
                        "Delete \(student.displayName)?",
                        isPresented: $confirmingDelete) {
                        Button("Delete Athlete", role: .destructive) { onDelete() }
                    } message: {
                        Text("Deletes the athlete with their contracts and player profile. This cannot be undone.")
                    }
                    Button("Edit") {
                        draft = AthleteDraft(student: student,
                                             player: dataManager.players.first {
                                                 $0.studentId == student.id
                                             })
                    }
                }
                .fixedSize()
            }
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
            .foregroundStyle(.secondary)
    }

    // MARK: - Stat strip (quiet)

    private var statStrip: some View {
        let stats = quickStats
        return HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 { Divider().frame(height: 28) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.value)
                        .font(.headline.monospacedDigit())
                    Text(stat.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var quickStats: [(title: String, value: String)] {
        guard let student else { return [] }
        let attended = dataManager.sessionEvents
            .filter { $0.actualAttendeeIds.contains(student.id) }.count
        let expected = dataManager.sessionEvents.filter {
            $0.attendeeIds.contains(student.id)
                || ($0.programId == student.programId && student.programId != nil)
        }.count
        let pct = expected > 0 ? "\(Int(Double(attended) / Double(expected) * 100))%" : "—"
        let contract = dataManager.currentContract(for: student.id)
        let bundle: String = {
            guard let contract else { return "—" }
            switch contract.kind {
            case .privateBundle: return "\(contract.bundleRedemptionsRemaining ?? 0) left"
            case .privatePayPerSession: return "PAYG"
            case .group: return "Group"
            }
        }()
        return [("Attended", "\(attended)"),
                ("Attendance", pct),
                ("Bundle", bundle),
                ("Status", contract?.status.rawValue ?? "No Contract")]
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabContent: some View {
        if let student {
            switch tab {
            case .overview:    overviewGroups(student)
            case .performance: AthletePerformanceTab(student: student)
            case .contracts:   AthleteContractsTab(student: student)
            case .notes:       AthleteNotesTab(student: student)
            case .history:     AthleteHistoryTab(student: student)
            }
        }
    }

    // MARK: - Overview (read mode: Contacts field groups)

    @ViewBuilder
    private func overviewGroups(_ student: Student) -> some View {
        let player = dataManager.players.first { $0.studentId == student.id }
        let info = player?.parentInfo

        VStack(alignment: .leading, spacing: 16) {
            if let info, hasContact(info) {
                FieldGroup(title: "Contact") {
                    if !info.name.isEmpty {
                        FieldRow(label: info.relationship.isEmpty ? "guardian"
                                 : info.relationship.lowercased(),
                                 value: info.name)
                    }
                    if !info.phone.isEmpty {
                        FieldRow(label: "phone", value: info.phone, tint: .accentColor) {
                            Button("Call", systemImage: "phone") {
                                let digits = info.phone.filter { !$0.isWhitespace }
                                if let url = URL(string: "tel://\(digits)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            copyButton(info.phone)
                        }
                    }
                    if let wechat = info.wechatId, !wechat.isEmpty {
                        FieldRow(label: "wechat", value: wechat) {
                            copyButton(wechat)
                        }
                    }
                    if let email = info.email, !email.isEmpty {
                        FieldRow(label: "email", value: email, tint: .accentColor) {
                            Button("Mail", systemImage: "envelope") {
                                if let url = URL(string: "mailto:\(email)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            copyButton(email)
                        }
                    }
                }
            }

            FieldGroup(title: "Program") {
                if let programId = student.programId,
                   let program = dataManager.programs.first(where: { $0.id == programId }) {
                    FieldRow(label: "program", value: program.name)
                    FieldRow(label: "athletes", value: "\(program.enrolledStudentIds.count)")
                } else {
                    FieldRow(label: "program", value: "Not enrolled")
                }
                if let contract = dataManager.currentContract(for: student.id) {
                    FieldRow(label: "contract", value: contract.status.rawValue)
                    if contract.kind == .privateBundle {
                        FieldRow(label: "remaining",
                                 value: "\(contract.bundleRedemptionsRemaining ?? 0) of \(contract.bundleSize) sessions")
                    }
                }
            }

            if !student.personalBests.isEmpty {
                FieldGroup(title: "Personal Bests") {
                    ForEach(Array(student.personalBests.keys.sorted()), id: \.self) { key in
                        FieldRow(label: key.lowercased(),
                                 value: formatBest(student.personalBests[key] ?? 0))
                    }
                }
            }

            let recent = recentSessions(student)
            if !recent.isEmpty {
                FieldGroup(title: "Recent Sessions") {
                    ForEach(recent) { session in
                        sessionRow(session, student: student)
                    }
                }
            }
        }
    }

    private func hasContact(_ info: ParentInfo) -> Bool {
        !info.name.isEmpty || !info.phone.isEmpty
            || !(info.wechatId ?? "").isEmpty || !(info.email ?? "").isEmpty
    }

    private func copyButton(_ text: String) -> some View {
        Button("Copy", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func recentSessions(_ student: Student) -> [SessionEvent] {
        dataManager.sessionEvents
            .filter {
                $0.attendeeIds.contains(student.id)
                    || ($0.programId != nil && $0.programId == student.programId)
            }
            .sorted { $0.date > $1.date }
            .prefix(6)
            .map { $0 }
    }

    private func sessionRow(_ session: SessionEvent, student: Student) -> some View {
        let attended = session.actualAttendeeIds.contains(student.id)
        return Button {
            onOpenSession(session.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: attended ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(attended ? .green : .secondary)
                    .font(.caption)
                Text(session.title)
                    .lineLimit(1)
                Spacer()
                Text(session.date, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatBest(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    // MARK: - Edit mode

    @ViewBuilder
    private var editGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldGroup(title: "Contact") {
                editRow(label: "guardian", prompt: "Add guardian name…",
                        text: Binding(get: { draft?.parentName ?? "" },
                                      set: { draft?.parentName = $0 }))
                editRow(label: "relation", prompt: "Parent",
                        text: Binding(get: { draft?.parentRelation ?? "" },
                                      set: { draft?.parentRelation = $0 }))
                editRow(label: "phone", prompt: "Add phone number…",
                        text: Binding(get: { draft?.parentPhone ?? "" },
                                      set: { draft?.parentPhone = $0 }))
                editRow(label: "wechat", prompt: "Add WeChat ID…",
                        text: Binding(get: { draft?.parentWechat ?? "" },
                                      set: { draft?.parentWechat = $0 }))
                editRow(label: "email", prompt: "Add email…",
                        text: Binding(get: { draft?.parentEmail ?? "" },
                                      set: { draft?.parentEmail = $0 }))
            }
            FieldGroup(title: "Cohort") {
                HStack {
                    Text("level")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 90, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { draft?.schoolGrade },
                        set: { draft?.schoolGrade = $0 })) {
                        Text("None").tag(SchoolGrade?.none)
                        ForEach(SchoolGrade.allCases, id: \.self) { grade in
                            Text(grade.displayName).tag(Optional(grade))
                        }
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                HStack {
                    Text("program")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 90, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { draft?.programId },
                        set: { draft?.programId = $0 })) {
                        Text("Not enrolled").tag(UUID?.none)
                        ForEach(dataManager.programs) { program in
                            Text(program.name).tag(Optional(program.id))
                        }
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            }
        }
    }

    /// Quiet placeholder rows, Contacts-style: visible in edit, absent in read.
    private func editRow(label: String, prompt: String,
                         text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 90, alignment: .trailing)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - Field group atoms (the Contacts read-mode grammar)

/// Rounded group of label/value rows divided by hairlines.
struct FieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// One Contacts row: secondary label left, value right, inline actions on
/// hover. Click-to-copy is the default action for plain values.
struct FieldRow<Actions: View>: View {
    let label: String
    let value: String
    var tint: Color = .primary
    @ViewBuilder var actions: () -> Actions

    @State private var hovering = false
    @State private var copied = false

    init(label: String, value: String, tint: Color = .primary,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.label = label
        self.value = value
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .foregroundStyle(tint)
                .textSelection(.enabled)
            if copied {
                Text("Copied")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            if hovering {
                HStack(spacing: 2) { actions() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { copied = false }
            }
        }
    }
}
