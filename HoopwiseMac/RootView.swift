import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case today, assistant, athletes, sessions, programs, drills, playbook, courtEditor, sales, league, hub
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .assistant: return "Assistant"
        case .athletes: return "Athletes"
        case .sessions: return "Sessions"
        case .programs: return "Programs"
        case .drills: return "Drills"
        case .playbook: return "Playbook"
        case .courtEditor: return "Court Editor"
        case .sales: return "Sales"
        case .league: return "League"
        case .hub: return "Hub"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .assistant: return "bubble.left.and.text.bubble.right.fill"
        case .athletes: return "person.2.fill"
        case .sessions: return "calendar"
        case .programs: return "list.clipboard.fill"
        case .drills: return "figure.basketball"
        case .playbook: return "book.pages.fill"
        case .courtEditor: return "sportscourt.fill"
        case .sales: return "creditcard.fill"
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
        if env["HOOPWISE_DEMO_ASSISTANT"] != nil { return .assistant }
        if env["HOOPWISE_DEMO_PAGE"] != nil {
            return SidebarSection(rawValue: env["HOOPWISE_DEMO_PAGE"]!) ?? .today
        }
        return Self.startupSelection()
    }()
    #else
    @State private var selection: SidebarSection? = RootView.startupSelection()
    #endif

    /// Settings: open at launch on Today, or reopen the last used page.
    private static func startupSelection() -> SidebarSection {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "settings.startupPage") == "last",
              let raw = defaults.string(forKey: "settings.lastPage"),
              let section = SidebarSection(rawValue: raw) else { return .today }
        return section
    }
    /// The court editor's model lives with the WINDOW. NSUndoManager holds its
    /// targets unowned(unsafe); a per-visit model left dangling actions in the
    /// window's undo stack, and Cmd-Z after navigation dereferenced freed
    /// memory. Window lifetime plus purge-on-teardown removes the class.
    @StateObject private var editorModel = PlayEditorModel(diagram: PlayEditorModel.newDiagram())
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// App-wide Esc-dismisses-sheets rule; lives as long as the window.
    @State private var presentationKeys = PresentationKeyDispatcher()
    /// The Whistle — one engine for the page, the bubble, and curation.
    @StateObject private var assistantEngine = AssistantEngine()

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
        .environmentObject(assistantEngine)
        .onReceive(NotificationCenter.default.publisher(for: .macSidebarSelection)) { note in
            if let raw = note.object as? String, let s = SidebarSection(rawValue: raw) {
                selection = s
            }
        }
        .onChange(of: selection) { _, newValue in
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: "settings.lastPage")
            }
        }
        .onAppear {
            presentationKeys.install()
            assistantEngine.configure(dataManager: dataManager)
            WhistleBubbleController.shared.attach(engine: assistantEngine)
            Task { await assistantEngine.runCuration() }
            #if DEBUG
            // Agent settings: "key=value,key=value" applied to UserDefaults
            // ("key=" removes), so Settings behaviour is testable from
            // outside the sandbox. AppStorage views react immediately.
            if let pairs = ProcessInfo.processInfo.environment["HOOPWISE_DEMO_DEFAULTS"] {
                for pair in pairs.split(separator: ",") {
                    let kv = pair.split(separator: "=", maxSplits: 1,
                                        omittingEmptySubsequences: false)
                    guard kv.count == 2 else { continue }
                    let key = String(kv[0])
                    let value = String(kv[1])
                    if value.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
                    else { UserDefaults.standard.set(value, forKey: key) }
                }
            }
            #endif
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
            // Agent assistant: scripted send + confirm at fixed delays.
            if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_ASSISTANT"] == "script" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    assistantEngine.send("Schedule a demo session for 蔡一铭")
                }
                if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_ASSISTANT_CONFIRM"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        assistantEngine.resolvePending(confirmed: true)
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
        case .assistant: AssistantView()
        case .athletes: AthletesDirectoryView()
        case .sessions: SessionsDirectoryView()
        case .programs: ProgramsView()
        case .drills:   DrillsView()
        case .playbook: PlaybookMacView()
        case .courtEditor: PlayEditorView(model: editorModel)
        case .sales:    SalesMacView()
        case .league:   LeagueMacView()
        case .hub:      HubMacView()
        }
    }
}
