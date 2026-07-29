import SwiftUI
import SwiftData

extension Notification.Name {
    /// Fired by SAMApp's `.onOpenURL` when the user taps a `.hoopwise`
    /// file outside the app. OrganizationView observes this and opens
    /// the import preview sheet.
    static let hoopwiseBundleOpenRequest = Notification.Name("hoopwiseBundleOpenRequest")
}

@main
struct SAMApp: App {
    @StateObject private var dataManager = SwiftDataManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isInitialized = false
    @State private var hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    splashView
                } else if !hasOnboarded {
                    OnboardingView {
                        hasOnboarded = true
                    }
                    .environmentObject(dataManager)
                    .modelContainer(dataManager.modelContainer)
                } else {
                    mainAppContent
                }
            }
            .task { await initializeApp() }
            .onOpenURL { url in
                // External `.hoopwise` files (AirDrop, Mail, Files, Messages, etc.)
                // arrive here. We post a notification that OrganizationView
                // observes and opens the import preview sheet.
                NotificationCenter.default.post(
                    name: .hoopwiseBundleOpenRequest,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                guard isInitialized else { return }
                Task { await dataManager.refreshAllCaches() }
            default:
                break
            }
        }
    }

    private var splashView: some View {
        ZStack {
            Color(red: 30/255, green: 58/255, blue: 138/255).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("HoopwiseLogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                ProgressView().tint(.white)
            }
        }
    }

    @ViewBuilder
    private var mainAppContent: some View {
        MainTabView()
            .environmentObject(dataManager)
            .modelContainer(dataManager.modelContainer)
    }

    private func initializeApp() async {
        guard !isInitialized else { return }

        await dataManager.loadAllData()

        await SessionStatusMonitor.shared.startMonitoring(dataManager: dataManager)

        isInitialized = true
    }
}
