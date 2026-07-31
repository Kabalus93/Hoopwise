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
    @State private var selection: SidebarSection? = .today
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
        case .courtEditor: PlayEditorView()
        case .league:   LeagueMacView()
        case .hub:      HubMacView()
        }
    }
}
