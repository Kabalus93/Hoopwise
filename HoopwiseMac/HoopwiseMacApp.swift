import SwiftUI
import SwiftData

@main
struct HoopwiseMacApp: App {
    @StateObject private var dataManager = SwiftDataManager.shared
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isInitialized {
                    RootView()
                        .environmentObject(dataManager)
                        .modelContainer(dataManager.modelContainer)
                } else {
                    MacSplashView()
                }
            }
            .frame(minWidth: 1100, minHeight: 700)
            .modifier(AppearanceSettingsModifier())
            .task { await initialize() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { NotificationCenter.default.post(name: .macNewSession, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Athlete") { NotificationCenter.default.post(name: .macNewAthlete, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // Court editor commands, so every shortcut is discoverable rather
            // than only living in a tooltip.
            CommandMenu("Play") {
                // ⌘N is New Session app-wide, so the editor's own "new" needs
                // its own binding rather than a tooltip claiming one it never
                // had.
                Button("New Play…") {
                    NotificationCenter.default.post(name: .macEditorNewPlay, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Save to Playbook") {
                    NotificationCenter.default.post(name: .macEditorSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .macEditorTogglePlay, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Mirror Play") {
                    NotificationCenter.default.post(name: .macEditorMirror, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                Divider()
                Button("Toggle Movement Paths") {
                    NotificationCenter.default.post(name: .macEditorTogglePaths, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Export Frame (PNG)…") {
                    NotificationCenter.default.post(name: .macEditorExportFrame, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Export Play Sheet (PDF)…") {
                    NotificationCenter.default.post(name: .macEditorExportSheet, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Toggle Sticky Ball") {
                    NotificationCenter.default.post(name: .macEditorToggleSticky, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Text("Tools: A select · O offense · D defense · B ball · S sticky · P paths")
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await SwiftDataManager.shared.refreshAllCaches() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            MacSettingsView()
                .environmentObject(dataManager)
                .modifier(AppearanceSettingsModifier())
        }
    }

    private func initialize() async {
        guard !isInitialized else { return }
        await dataManager.loadAllData()
        await SessionStatusMonitor.shared.startMonitoring(dataManager: dataManager)
        isInitialized = true
        #if DEBUG
        HandoverWriteDebug.runIfRequested(dataManager: dataManager)
        #endif
    }
}

extension Notification.Name {
    static let macNewSession = Notification.Name("MacNewSession")
    static let macNewAthlete = Notification.Name("MacNewAthlete")
    static let macSidebarSelection = Notification.Name("MacSidebarSelection")
    static let macEditorTogglePlay = Notification.Name("MacEditorTogglePlay")
    static let macEditorMirror = Notification.Name("MacEditorMirror")
    static let macEditorTogglePaths = Notification.Name("MacEditorTogglePaths")
    static let macEditorToggleSticky = Notification.Name("MacEditorToggleSticky")
    static let macEditorSave = Notification.Name("MacEditorSave")
    static let macOpenPlayInEditor = Notification.Name("MacOpenPlayInEditor")
    static let macOpenSession = Notification.Name("MacOpenSession")
    static let macOpenAthlete = Notification.Name("MacOpenAthlete")
    static let macDismissPresentedSurface = Notification.Name("MacDismissPresentedSurface")
    static let macEditorNewPlay = Notification.Name("MacEditorNewPlay")
    static let macEditorExportFrame = Notification.Name("MacEditorExportFrame")
    static let macEditorExportSheet = Notification.Name("MacEditorExportSheet")
}

struct MacSplashView: View {
    var body: some View {
        ZStack {
            Color(red: 30/255, green: 58/255, blue: 138/255).ignoresSafeArea()
            VStack(spacing: 18) {
                Image("HoopwiseLogoWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                ProgressView().controlSize(.small).tint(.white)
            }
        }
    }
}
