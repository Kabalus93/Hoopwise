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
    @State private var selection: SidebarSection? = {
        let env = ProcessInfo.processInfo.environment
        if env["HOOPWISE_DEMO_SCENARIO"] != nil { return .courtEditor }
        if env["HOOPWISE_DEMO_DIR_LOG"] != nil || env["HOOPWISE_DEMO_DIR_SEARCH"] != nil {
            return .athletes
        }
        if env["HOOPWISE_DEMO_SESSIONS"] != nil { return .sessions }
        if env["HOOPWISE_DEMO_PAGE"] != nil {
            return SidebarSection(rawValue: env["HOOPWISE_DEMO_PAGE"]!) ?? .today
        }
        return .today
    }()
    #else
    @State private var selection: SidebarSection? = .today
    #endif
    /// The court editor's model lives with the WINDOW. NSUndoManager holds its
    /// targets unowned(unsafe); a per-visit model left dangling actions in the
    /// window's undo stack, and Cmd-Z after navigation dereferenced freed
    /// memory. Window lifetime plus purge-on-teardown removes the class.
    @StateObject private var editorModel = PlayEditorModel(diagram: PlayEditorModel.newDiagram())
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// App-wide Esc-dismisses-sheets rule; lives as long as the window.
    @State private var presentationKeys = PresentationKeyDispatcher()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // No column-width IDEAL here: an ideal wider than the window minus
            // the sidebar makes AppKit break the SIDEBAR's min constraint and
            // crop it. The detail takes whatever remains; pages own their
            // interior minimums and collapse their own columns first.
            detailView
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSidebarSelection)) { note in
            if let raw = note.object as? String, let s = SidebarSection(rawValue: raw) {
                selection = s
            }
        }
        .onAppear {
            presentationKeys.install()
            #if DEBUG
            // Agent window sizing: constraint-exception sweeps at min size.
            if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_WINDOW"] == "min" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSApp.windows.first { $0.isVisible }?
                        .setFrame(NSRect(x: 60, y: 60, width: 1100, height: 700),
                                  display: true)
                }
            }
            // Agent navigation: simulate sidebar clicks in sequence.
            if let sequence = ProcessInfo.processInfo.environment["HOOPWISE_DEMO_PAGE_SEQUENCE"] {
                let pages = sequence.split(separator: ",").map(String.init)
                for (index, page) in pages.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 2.5) {
                        NotificationCenter.default.post(name: .macSidebarSelection, object: page)
                    }
                }
            }
            // Agent keys: post a real Esc key-down through the event stream at
            // +N seconds, so the dispatch-layer dismissal is testable without
            // Accessibility. In-process NSApp.postEvent reaches local monitors.
            if let raw = ProcessInfo.processInfo.environment["HOOPWISE_DEMO_PRESS_ESC_AT"],
               let delay = Double(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let target = NSApp.keyWindow ?? NSApp.mainWindow
                    guard let window = target,
                          let esc = NSEvent.keyEvent(
                            with: .keyDown, location: .zero, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil,
                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                            isARepeat: false, keyCode: 53) else { return }
                    NSApp.postEvent(esc, atStart: false)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .today {
        case .today:    TodayView()
        case .athletes: AthletesDirectoryView()
        case .sessions: SessionsDirectoryView()
        case .programs: ProgramsView()
        case .drills:   DrillsView()
        case .playbook: PlaybookMacView()
        case .courtEditor: PlayEditorView(model: editorModel)
        case .league:   LeagueMacView()
        case .hub:      HubMacView()
        }
    }
}
