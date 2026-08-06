import SwiftUI
import SwiftData

extension Notification.Name {
    /// Fired by SAMApp's `.onOpenURL` when the user taps a `.hoopwise`
    /// file outside the app. OrganizationView observes this and opens
    /// the import preview sheet.
    static let hoopwiseBundleOpenRequest = Notification.Name("hoopwiseBundleOpenRequest")
    /// Widget deep links (hoopwise://session/<id>, hoopwise://athlete/<id>).
    /// Published for navigation; wiring them to actual screens is an iOS
    /// view change and therefore waits on the UI freeze.
    static let hoopwiseOpenSessionRequest = Notification.Name("hoopwiseOpenSessionRequest")
    static let hoopwiseOpenAthleteRequest = Notification.Name("hoopwiseOpenAthleteRequest")
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
                // Widget deep links use the hoopwise:// scheme.
                if url.scheme == "hoopwise" {
                    let id = UUID(uuidString: url.lastPathComponent)
                    switch url.host {
                    case "session":
                        NotificationCenter.default.post(
                            name: .hoopwiseOpenSessionRequest, object: id)
                    case "athlete":
                        NotificationCenter.default.post(
                            name: .hoopwiseOpenAthleteRequest, object: id)
                    default:
                        break
                    }
                    return
                }
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
