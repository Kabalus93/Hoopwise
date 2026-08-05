import SwiftUI
import AppKit
import os

// MARK: - Athletes directory
//
// The Contacts pattern applied to the roster: groups → indexed list → card.
// This page owns the DATA logic — group membership, pinyin collation, search,
// selection coherence — and hands layout to DirectoryView.
struct AthletesDirectoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.undoManager) private var undoManager

    @State private var selectedGroups: Set<String> = [Self.allGroupId]
    @State private var search = ""
    @State private var selection: UUID?
    /// Non-nil while the card is in EDIT mode (explicit, Contacts-style).
    @State private var draft: AthleteDraft?
    /// The draft creates a new athlete rather than editing the selection.
    @State private var draftIsNew = false

    @StateObject private var keyRouter = DirectoryKeyRouter()
    @State private var keyDispatcher = DirectoryKeyDispatcher()

    @AppStorage("athletesDirectory.sort") private var sortRaw = AthleteSort.name.rawValue
    /// The smart group's editable rule. A preference rather than a synced
    /// record: the GROUP is virtual; only its threshold is remembered.
    @AppStorage("athletesDirectory.lowAttendanceThreshold") private var lowAttendanceThreshold = 0.6
    @State private var editingSmartRule = false

    private static let allGroupId = "fixed:all"

    enum AthleteSort: String, CaseIterable, Identifiable {
        case name, recent, attendance
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .recent: return "Recent"
            case .attendance: return "Attendance"
            }
        }
    }

    var body: some View {
        DirectoryView(
            groupSections: groupSections,
            selectedGroups: $selectedGroups,
            items: visibleStudents,
            sectionKey: { sectionKey(for: $0) },
            searchText: $search,
            searchPrompt: "Search name, 中文 or pinyin",
            selection: $selection,
            countLabel: "\(visibleStudents.count)",
            storageKey: "athletesDirectory",
            searchFocusToken: keyRouter.searchFocusToken,
            onDropMembers: { group, ids in
                guard let uuid = customGroupUUID(group.id) else { return }
                dataManager.addToDirectoryGroup(id: uuid, memberIds: ids)
            },
            onCreateGroup: {
                dataManager.createDirectoryGroup(kind: "athlete", name: "New Group")
            },
            onRenameGroup: { group, name in
                guard let uuid = customGroupUUID(group.id) else { return }
                dataManager.renameDirectoryGroup(id: uuid, to: name)
            },
            onDeleteGroup: { group in
                guard let uuid = customGroupUUID(group.id) else { return }
                selectedGroups.remove(group.id)
                if selectedGroups.isEmpty { selectedGroups = [Self.allGroupId] }
                dataManager.deleteDirectoryGroup(id: uuid)
            },
            onEditSmartRule: { _ in editingSmartRule = true },
            row: { student in
                AthleteDirectoryRow(student: student,
                                    index: nameIndex(for: student))
                    .contextMenu {
                        customGroupMenu(for: student)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(student)
                        }
                    }
            },
            listAccessory: { AnyView(sortMenu) },
            detail: { detailCard }
        )
        .navigationTitle("Athletes")
        .onAppear {
            wireKeyboard()
            keyDispatcher.install(router: keyRouter)
            autoSelectIfNeeded()
            #if DEBUG
            applyDemoEnvironment()
            #endif
        }
        .onDisappear { keyDispatcher.uninstall() }
        .onChange(of: selectedGroups) { _, _ in autoSelectIfNeeded() }
        .onChange(of: search) { _, _ in autoSelectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .macNewAthlete)) { _ in
            beginNewAthlete()
        }
        // Deep link from Today: land with the athlete's row selected. Filters
        // reset to All so the target can never be hidden by a stale group.
        .onReceive(NotificationCenter.default.publisher(for: .macOpenAthlete)) { note in
            guard let id = note.object as? UUID else { return }
            selectedGroups = [Self.allGroupId]
            search = ""
            selection = id
        }
        .sheet(isPresented: $editingSmartRule) {
            smartRuleSheet.dismissesOnPresentationEscape { editingSmartRule = false }
        }
    }

    // MARK: - Detail slot

    @ViewBuilder
    private var detailCard: some View {
        if draftIsNew, draft != nil {
            AthleteCardView(student: nil, draft: $draft, isNew: true,
                            onCommit: commitDraft, onCancel: cancelDraft,
                            onDelete: {}, onOpenSession: openSession)
        } else if let id = selection,
                  let student = dataManager.students.first(where: { $0.id == id }) {
            AthleteCardView(student: student, draft: $draft, isNew: false,
                            onCommit: commitDraft, onCancel: cancelDraft,
                            onDelete: { delete(student) }, onOpenSession: openSession)
                .id(student.id)
        } else {
            EmptyDetail(systemImage: "person.2", title: "Select an Athlete")
        }
    }

    // MARK: - Collation + search (the pinyin core)

    private func nameIndex(for student: Student) -> NameIndex {
        NameIndex.cached(name: student.name, secondary: student.chineseName)
    }

    private func sectionKey(for student: Student) -> String {
        sort == .name ? nameIndex(for: student).section : " "
    }

    private var sort: AthleteSort {
        AthleteSort(rawValue: sortRaw) ?? .name
    }

    private var sortMenu: some View {
        Picker("Sort", selection: $sortRaw) {
            ForEach(AthleteSort.allCases) { option in
                Text(option.label).tag(option.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }

    /// Group-filtered, searched, sorted — the single ordering behind the
    /// list, its sections, and keyboard navigation.
    private var visibleStudents: [Student] {
        let members = selectedMemberIds
        var base = dataManager.students
        if let members { base = base.filter { members.contains($0.id) } }
        if !search.isEmpty {
            base = base.filter { nameIndex(for: $0).matches(search) }
        }
        switch sort {
        case .name:
            return base.sorted {
                let l = nameIndex(for: $0), r = nameIndex(for: $1)
                if l.sortKey != r.sortKey { return l.sortKey < r.sortKey }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .recent:
            return base.sorted { $0.createdAt > $1.createdAt }
        case .attendance:
            let attended = attendedCounts
            return base.sorted { (attended[$0.id] ?? 0) > (attended[$1.id] ?? 0) }
        }
    }

    // MARK: - Groups

    private var groupSections: [DirectoryGroupSection] {
        let students = dataManager.students
        var sections: [DirectoryGroupSection] = []

        let pct = Int(lowAttendanceThreshold * 100)
        sections.append(DirectoryGroupSection(id: "smart", title: nil, groups: [
            DirectoryGroup(id: Self.allGroupId, title: "All Athletes",
                           icon: "person.2", count: students.count),
            DirectoryGroup(id: "fixed:active", title: "Active",
                           icon: "person.crop.circle.badge.checkmark",
                           count: count("fixed:active")),
            DirectoryGroup(id: "fixed:inactive", title: "Inactive",
                           icon: "person.crop.circle.badge.minus",
                           count: count("fixed:inactive")),
            DirectoryGroup(id: "fixed:bundleLow", title: "Bundle Low",
                           icon: "exclamationmark.triangle",
                           count: count("fixed:bundleLow")),
            DirectoryGroup(id: "smart:lowAttendance",
                           title: "Attendance < \(pct)%",
                           icon: "chart.line.downtrend.xyaxis",
                           count: count("smart:lowAttendance"),
                           isEditableSmart: true),
        ]))

        let levels = Set(students.compactMap { $0.schoolGrade })
        if !levels.isEmpty {
            let ordered = SchoolGrade.allCases.filter { levels.contains($0) }
            sections.append(DirectoryGroupSection(
                id: "levels", title: "Levels",
                groups: ordered.map { grade in
                    DirectoryGroup(id: "level:\(grade.rawValue)",
                                   title: grade.displayName,
                                   icon: "graduationcap",
                                   count: students.filter { $0.schoolGrade == grade }.count)
                }))
        }

        let programs = dataManager.programs.filter { !$0.enrolledStudentIds.isEmpty }
        if !programs.isEmpty {
            sections.append(DirectoryGroupSection(
                id: "programs", title: "Programs",
                groups: programs.map { program in
                    DirectoryGroup(id: "program:\(program.id.uuidString)",
                                   title: program.name,
                                   icon: "list.clipboard",
                                   count: programMemberIds(program).count)
                }))
        }

        let custom = dataManager.directoryGroups(kind: "athlete")
        if !custom.isEmpty {
            sections.append(DirectoryGroupSection(
                id: "custom", title: "My Groups",
                groups: custom.map { group in
                    DirectoryGroup(id: "custom:\(group.id.uuidString)",
                                   title: group.name,
                                   icon: "folder",
                                   count: group.memberIds.count,
                                   isUserGroup: true)
                }))
        }
        return sections
    }

    /// ⌘-clicked groups UNION. Nil means unfiltered (All or nothing picked).
    private var selectedMemberIds: Set<UUID>? {
        let picked = selectedGroups.filter { $0 != Self.allGroupId }
        guard !picked.isEmpty, !selectedGroups.contains(Self.allGroupId) else { return nil }
        var union: Set<UUID> = []
        for groupId in picked { union.formUnion(memberIds(of: groupId)) }
        return union
    }

    private func count(_ groupId: String) -> Int { memberIds(of: groupId).count }

    private func memberIds(of groupId: String) -> Set<UUID> {
        let students = dataManager.students
        switch groupId {
        case Self.allGroupId:
            return Set(students.map(\.id))
        case "fixed:active":
            return Set(students.filter {
                dataManager.currentContract(for: $0.id)?.status == .active
            }.map(\.id))
        case "fixed:inactive":
            return Set(students.filter {
                let status = dataManager.currentContract(for: $0.id)?.status
                return status == nil || status == .expired || status == .cancelled
                    || status == .completed
            }.map(\.id))
        case "fixed:bundleLow":
            return Set(students.filter {
                guard let c = dataManager.currentContract(for: $0.id),
                      c.kind == .privateBundle else { return false }
                return (c.bundleRedemptionsRemaining ?? .max) <= 3
            }.map(\.id))
        case "smart:lowAttendance":
            let attended = attendedCounts
            let expected = expectedCounts
            return Set(students.filter {
                let e = expected[$0.id] ?? 0
                guard e > 0 else { return false }
                return Double(attended[$0.id] ?? 0) / Double(e) < lowAttendanceThreshold
            }.map(\.id))
        default:
            if groupId.hasPrefix("level:") {
                let raw = String(groupId.dropFirst("level:".count))
                return Set(students.filter { $0.schoolGrade?.rawValue == raw }.map(\.id))
            }
            if groupId.hasPrefix("program:"),
               let uuid = UUID(uuidString: String(groupId.dropFirst("program:".count))),
               let program = dataManager.programs.first(where: { $0.id == uuid }) {
                return programMemberIds(program)
            }
            if let uuid = customGroupUUID(groupId),
               let group = dataManager.directoryGroups(kind: "athlete")
                    .first(where: { $0.id == uuid }) {
                return Set(group.memberIds)
            }
            return []
        }
    }

    /// Program membership is the UNION of the program's enrolled list and
    /// students pointing at it — the two link sources drift in legacy data,
    /// and a group that undercounts reads as data loss.
    private func programMemberIds(_ program: Program) -> Set<UUID> {
        var members = Set(program.enrolledStudentIds)
        for student in dataManager.students where student.programId == program.id {
            members.insert(student.id)
        }
        let known = Set(dataManager.students.map(\.id))
        return members.intersection(known)
    }

    private func customGroupUUID(_ groupId: String) -> UUID? {
        guard groupId.hasPrefix("custom:") else { return nil }
        return UUID(uuidString: String(groupId.dropFirst("custom:".count)))
    }

    @ViewBuilder
    private func customGroupMenu(for student: Student) -> some View {
        let groups = dataManager.directoryGroups(kind: "athlete")
        if !groups.isEmpty {
            Menu("Add to Group") {
                ForEach(groups) { group in
                    Button(group.name) {
                        dataManager.addToDirectoryGroup(id: group.id,
                                                        memberIds: [student.id])
                    }
                }
            }
        }
    }

    // MARK: - Attendance tallies (one pass, reused by group + sort + smart)

    private var attendedCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for session in dataManager.sessionEvents {
            for id in session.actualAttendeeIds { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private var expectedCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        let programOf = Dictionary(uniqueKeysWithValues:
            dataManager.students.map { ($0.id, $0.programId) })
        for session in dataManager.sessionEvents {
            var expected = Set(session.attendeeIds)
            if let programId = session.programId {
                for (student, program) in programOf where program == programId {
                    expected.insert(student)
                }
            }
            for id in expected { counts[id, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - Keyboard (rides the shared dispatch layer)

    private func wireKeyboard() {
        keyRouter.moveSelection = { delta in
            let items = visibleStudents
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
            let items = visibleStudents
            if let hit = items.first(where: {
                nameIndex(for: $0).sortKey.hasPrefix(buffer)
            }) ?? items.first(where: {
                nameIndex(for: $0).matches(buffer)
            }) {
                selection = hit.id
            }
        }
        keyRouter.escape = {
            if draft != nil {
                cancelDraft()
                return true
            }
            if !search.isEmpty {
                search = ""
                return true
            }
            return false
        }
        keyRouter.newItem = { beginNewAthlete() }
    }

    // MARK: - Selection coherence + mutations

    private func autoSelectIfNeeded() {
        let items = visibleStudents
        if let current = selection, items.contains(where: { $0.id == current }) { return }
        selection = items.first?.id
    }

    /// Deleting selects the NEXT row — never a stale card.
    private func delete(_ student: Student) {
        let items = visibleStudents
        let index = items.firstIndex(where: { $0.id == student.id })
        dataManager.deleteStudent(student)
        if selection == student.id {
            let remaining = items.filter { $0.id != student.id }
            if let index, !remaining.isEmpty {
                selection = remaining[min(index, remaining.count - 1)].id
            } else {
                selection = nil
            }
        }
    }

    private func beginNewAthlete() {
        draft = AthleteDraft()
        draftIsNew = true
    }

    private func cancelDraft() {
        draft = nil
        draftIsNew = false
    }

    /// Done: ONE undoable commit covering student + guardian contact.
    private func commitDraft() {
        guard let committed = draft else { return }
        if draftIsNew {
            let student = committed.makeStudent()
            let player = committed.makePlayer(studentId: student.id)
            dataManager.addStudent(student, player: player)
            if let programId = committed.programId {
                dataManager.setStudentEnrollment(studentId: student.id,
                                                 programId: programId)
            }
            let created = student
            undoManager?.registerUndo(withTarget: dataManager) { manager in
                manager.deleteStudent(created)
            }
            undoManager?.setActionName("Add Athlete")
            selection = student.id
        } else if let id = selection,
                  let old = dataManager.students.first(where: { $0.id == id }) {
            let oldPlayer = dataManager.players.first(where: { $0.studentId == id })
            let updated = committed.apply(to: old)
            dataManager.updateStudent(updated)
            // Enrollment is ONE relation written from both ends — the shared
            // writer keeps program.enrolledStudentIds in lockstep.
            if old.programId != committed.programId {
                dataManager.setStudentEnrollment(studentId: id,
                                                 programId: committed.programId)
            }
            if var player = oldPlayer {
                let previous = player
                player.parentInfo = committed.parentInfo(existing: player.parentInfo)
                player.updatedAt = Date()
                dataManager.updatePlayer(player)
                undoManager?.registerUndo(withTarget: dataManager) { manager in
                    manager.updateStudent(old)
                    manager.updatePlayer(previous)
                }
            } else {
                undoManager?.registerUndo(withTarget: dataManager) { manager in
                    manager.updateStudent(old)
                }
            }
            undoManager?.setActionName("Edit Athlete")
        }
        draft = nil
        draftIsNew = false
    }

    private func openSession(_ sessionId: UUID) {
        NotificationCenter.default.post(name: .macSidebarSelection,
                                        object: SidebarSection.sessions.rawValue)
        // Give the Sessions page a beat to appear before targeting it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .macOpenSession, object: sessionId)
        }
    }

    #if DEBUG
    /// Agent verification hooks (no Accessibility on this Mac): inject a
    /// search query, dump the real roster's collation to the unified log.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let query = env["HOOPWISE_DEMO_DIR_SEARCH"] { search = query }
        if env["HOOPWISE_DEMO_PHOTO_AUDIT"] == "1" {
            let logger = os.Logger(subsystem: "hoopwise.demo", category: "photos")
            var withData = 0, withThumbOnly = 0, urlOnly = 0, none = 0
            for student in dataManager.students {
                let hasData = !(student.profileImageData ?? Data()).isEmpty
                let hasThumb = !(student.thumbnailImageData ?? Data()).isEmpty
                let hasUrl = !(student.profileImageUrl ?? "").isEmpty
                if hasData { withData += 1 }
                else if hasThumb { withThumbOnly += 1 }
                else if hasUrl {
                    urlOnly += 1
                    logger.notice("PHOTO: URL-only \(student.displayName, privacy: .public) url=\(student.profileImageUrl ?? "", privacy: .public)")
                } else { none += 1 }
            }
            logger.notice("PHOTO: total=\(dataManager.students.count) withData=\(withData) thumbOnly=\(withThumbOnly) urlOnly=\(urlOnly) none=\(none)")
        }
        if env["HOOPWISE_DEMO_DIR_LOG"] == "1" {
            let logger = os.Logger(subsystem: "hoopwise.demo", category: "directory")
            let items = visibleStudents
            logger.notice("DIR: \(items.count, privacy: .public) athletes, search='\(search, privacy: .public)'")
            for student in items {
                let index = nameIndex(for: student)
                logger.notice("DIR: \(index.section, privacy: .public) | \(index.sortKey, privacy: .public) | \(student.displayName, privacy: .public) | \(student.chineseName ?? "-", privacy: .public)")
            }
        }
    }
    #endif

    // MARK: - Smart rule editor

    private var smartRuleSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Attendance Group Rule").font(.headline)
            Text("Athletes whose attendance falls below the threshold appear in this group.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Below")
                Slider(value: $lowAttendanceThreshold, in: 0.1...0.95, step: 0.05)
                Text("\(Int(lowAttendanceThreshold * 100))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button("Done") { editingSmartRule = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

// MARK: - Row

/// Contacts-density row: avatar, name with secondary name, level chip.
private struct AthleteDirectoryRow: View {
    let student: Student
    let index: NameIndex
    @AppStorage("settings.listDensity") private var listDensity = "comfortable"

    private var compact: Bool { listDensity == "compact" }

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            DirectoryAvatar(imageData: student.thumbnailImageData ?? student.profileImageData,
                            initials: student.initials,
                            color: Color.avatarColor(student.avatarColor),
                            size: compact ? 22 : 30)
            HStack(spacing: 6) {
                Text(student.displayName)
                    .font(.body)
                    .lineLimit(1)
                if let secondary = secondaryName {
                    Text(secondary)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let grade = student.schoolGrade {
                Text(grade.shortName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, compact ? -2 : 1)
    }

    private var secondaryName: String? {
        guard let secondary = student.chineseName, !secondary.isEmpty,
              secondary != student.displayName else { return nil }
        return secondary
    }
}

/// Thin alias over AthletePhoto — kept so existing call sites read the same.
struct DirectoryAvatar: View {
    let imageData: Data?
    let initials: String
    let color: Color
    let size: CGFloat

    var body: some View {
        AthletePhoto(imageData: imageData, initials: initials,
                     color: color, size: size)
    }
}
