import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case today, athletes, sessions, programs, drills, playbook, courtEditor, league, hub
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .athletes: return "Athletes"
        case .sessions: return "Sessions"
        case .programs: return "Programs"
        case .drills: return "Drills"
        case .playbook: return "Playbook"
        case .courtEditor: return "Court Editor"
        case .league: return "League"
        case .hub: return "Hub"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .athletes: return "person.2.fill"
        case .sessions: return "calendar"
        case .programs: return "list.clipboard.fill"
        case .drills: return "figure.basketball"
        case .playbook: return "book.pages.fill"
        case .courtEditor: return "sportscourt.fill"
        case .league: return "trophy.fill"
        case .hub: return "building.2.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var dataManager: DataManager
    #if DEBUG
    // Agent verification runs open straight on the editor — synthetic input
    // is unavailable, so the demo scenario cannot click the sidebar itself.
    @State private var selection: SidebarSection? =
        ProcessInfo.processInfo.environment["HOOPWISE_DEMO_SCENARIO"] != nil
        ? .courtEditor : .today
    #else
    @State private var selection: SidebarSection? = .today
    #endif
    /// The court editor's model lives with the WINDOW. NSUndoManager holds its
    /// targets unowned(unsafe); a per-visit model left dangling actions in the
    /// window's undo stack, and Cmd-Z after navigation dereferenced freed
    /// memory. Window lifetime plus purge-on-teardown removes the class.
    @StateObject private var editorModel = PlayEditorModel(diagram: PlayEditorModel.newDiagram())
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 700, ideal: 1000)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSidebarSelection)) { note in
            if let raw = note.object as? String, let s = SidebarSection(rawValue: raw) {
                selection = s
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .today {
        case .today:    TodayView()
        case .athletes: AthletesView()
        case .sessions: SessionsView()
        case .programs: ProgramsView()
        case .drills:   DrillsView()
        case .playbook: PlaybookMacView()
        case .courtEditor: PlayEditorView(model: editorModel)
        case .league:   LeagueMacView()
        case .hub:      HubMacView()
        }
    }
}
