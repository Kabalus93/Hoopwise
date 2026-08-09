import SwiftUI
import SwiftData

extension Notification.Name {
    /// Fired by SAMApp's `.onOpenURL` when the user taps a `.hoopwise`
    /// file outside the app. OrganizationView observes this and opens
    /// the import preview sheet.
    static let hoopwiseBundleOpenRequest = Notification.Name("hoopwiseBundleOpenRequest")
    /// Widget deep links (hoopwise://session/<id>, hoopwise://athlete/<id>).
    /// MainTabView observes these (the one sanctioned freeze exception).
    static let hoopwiseOpenSessionRequest = Notification.Name("hoopwiseOpenSessionRequest")
    static let hoopwiseOpenAthleteRequest = Notification.Name("hoopwiseOpenAthleteRequest")
}

/// A widget deep link that arrived before MainTabView's observers existed —
/// on a cold start the URL lands while the splash is still up, so posting
/// the notification alone would drop it into a void. SAMApp stores the route
/// here as well; MainTabView consumes it once navigation is ready.
enum PendingWidgetRoute {
    case session(UUID)
    case athlete(UUID)

    static var pending: PendingWidgetRoute?
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
                        PendingWidgetRoute.pending = id.map { .session($0) }
                        NotificationCenter.default.post(
                            name: .hoopwiseOpenSessionRequest, object: id)
                    case "athlete":
                        PendingWidgetRoute.pending = id.map { .athlete($0) }
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

        #if DEBUG
        exportStatementIfRequested()
        AttentionDebugReport.runIfRequested(dataManager: dataManager)
        #endif
    }

    #if DEBUG
    /// Headless statement export for device verification — same channel as
    /// the widget traces. HOOPWISE_EXPORT_STATEMENT="<studentName>:<contractNo>"
    /// (set via `devicectl device process launch -e`) writes the PDF to the
    /// App Group's Library/Caches, pullable without root. Debug only, no UI.
    @MainActor
    private func exportStatementIfRequested() {
        guard let spec = ProcessInfo.processInfo
            .environment["HOOPWISE_EXPORT_STATEMENT"] else { return }
        let parts = spec.split(separator: ":")
        guard let namePart = parts.first else { return }
        let name = String(namePart)
        let contractNo = parts.count > 1 ? Int(parts[1]) : nil
        guard let student = dataManager.students.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.chineseName == name
        }) else { return }
        let contracts = dataManager.contracts.filter { $0.studentId == student.id }
        guard let contract = contractNo
            .flatMap({ number in contracts.first { $0.contractNumber == number } })
            ?? contracts.first else { return }
        guard let input = AttendanceStatementDocument.makeInput(
                studentId: student.id, contract: contract, dataManager: dataManager),
              let dir = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches", isDirectory: true)
        else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try? AttendanceStatementDocument.render(
            input, to: dir.appendingPathComponent("statement-debug.pdf"))
    }
    #endif
}
