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
            listAccessory: { AnyView(EmptyView()) },
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
        .onReceive(NotificationCenter.default.publisher(for: .macNewSession)) { _ in
            showingNew = true
        }
        // Deep link from the Athletes card's Recent Sessions rows.
        .onReceive(NotificationCenter.default.publisher(for: .macOpenSession)) { note in
            guard let id = note.object as? UUID else { return }
            selectedGroups = ["fixed:all"]
            search = ""
            selection = id
        }
        .sheet(isPresented: $showingNew) { NewSessionSheet() }
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
            let items = visibleSessions
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

    private func autoSelectIfNeeded() {
        let items = visibleSessions
        if let current = selection, items.contains(where: { $0.id == current }) { return }
        selection = items.first?.id
    }
}

// MARK: - Row

private struct SessionDirectoryRow: View {
    let session: SessionEvent

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
        .padding(.vertical, 1)
    }
}
