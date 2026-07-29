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
        }
    }

    private func initialize() async {
        guard !isInitialized else { return }
        await dataManager.loadAllData()
        await SessionStatusMonitor.shared.startMonitoring(dataManager: dataManager)
        isInitialized = true
    }
}

extension Notification.Name {
    static let macNewSession = Notification.Name("MacNewSession")
    static let macNewAthlete = Notification.Name("MacNewAthlete")
    static let macSidebarSelection = Notification.Name("MacSidebarSelection")
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
