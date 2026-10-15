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

    /// Non-nil only in a DEBUG build launched with HOOPWISE_SHOT — the
    /// creation-sheet screenshot harness. Release builds compile to `nil`.
    private var debugSheetShot: String? {
        #if DEBUG
        return SheetGalleryDebug.requestedShot
        #else
        return nil
        #endif
    }

    /// SheetGalleryDebug only exists in DEBUG; Release never reaches this
    /// (debugSheetShot is nil there) but must still compile it.
    @ViewBuilder
    private func debugSheetRoot(shot: String) -> some View {
        #if DEBUG
        SheetGalleryDebug.root(shot: shot, dataManager: dataManager)
        #else
        EmptyView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    splashView
                } else if let shot = debugSheetShot {
                    debugSheetRoot(shot: shot)
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

        #if DEBUG
        // Unit tests are hosted in this app. Booting the data load, the
        // status monitor and the debug hooks alongside them destabilised the
        // test process; the tests drive their own manager.
        if SwiftDataManager.isRunningUnitTests {
            isInitialized = true
            return
        }
        #endif

        await dataManager.loadAllData()

        await SessionStatusMonitor.shared.startMonitoring(dataManager: dataManager)

        isInitialized = true

        #if DEBUG
        #if os(iOS)
        ScreenshotStore.prune(dataManager: dataManager)
        #endif
        if SheetGalleryDebug.requestedShot != nil {
            SheetGalleryDebug.seedIfEmpty(dataManager: dataManager)
        }
        exportStatementIfRequested()
        exportGuideIfRequested()
        ClassListDebug.previewIfRequested(dataManager: dataManager)
        AttentionDebugReport.runIfRequested(dataManager: dataManager)
        runOrphanCensusIfRequested()
        SessionInspectorDebug.runIfRequested(dataManager: dataManager)
        SessionInspectorDebug.seriesReportIfRequested(dataManager: dataManager)
        SessionInspectorDebug.seedFridayProgramIfRequested(dataManager: dataManager)
        SessionInspectorDebug.programProfileIfRequested(dataManager: dataManager)
        SessionInspectorDebug.adoptFridaySeriesIfRequested(dataManager: dataManager)
        SessionInspectorDebug.createMicroGroupsIfRequested(dataManager: dataManager)
        SessionInspectorDebug.applyAllMergesIfRequested(dataManager: dataManager)
        SessionInspectorDebug.rewindowDryRunIfRequested(dataManager: dataManager)
        SessionInspectorDebug.extendPlanDryRunIfRequested(dataManager: dataManager)
        SessionInspectorDebug.applyPlanReshapeIfRequested(dataManager: dataManager)
        SessionInspectorDebug.applyDedupeIfRequested(dataManager: dataManager)
        SessionInspectorDebug.venueCensusIfRequested(dataManager: dataManager)
        SessionInspectorDebug.foldStraySessionIfRequested(dataManager: dataManager)
        SessionInspectorDebug.phaseLanguageReportIfRequested(dataManager: dataManager)
        SessionInspectorDebug.dedupeRuleComparisonIfRequested(dataManager: dataManager)
        SessionInspectorDebug.expiryFlipReportIfRequested(dataManager: dataManager)
        SessionInspectorDebug.handoverReportIfRequested(dataManager: dataManager)
        #endif
    }

    #if DEBUG
    /// HOOPWISE_ORPHAN_CENSUS=1 → writes the referential-integrity census for
    /// the live store to the App Group's Library/Caches, pullable via
    /// devicectl. Read-only: the census never repairs anything.
    @MainActor
    private func runOrphanCensusIfRequested() {
        guard ProcessInfo.processInfo.environment["HOOPWISE_ORPHAN_CENSUS"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/orphan-census.txt") else { return }
        let census = SessionIntegrity.census(sessions: dataManager.sessionEvents,
                                             programs: dataManager.programs,
                                             phases: dataManager.microCycles)

        // The dedupe DRY RUN rides along: same read-only guarantee, and the
        // two reports are only meaningful together.
        let redeemed = SessionDedupe.redeemedSessionIds(in: dataManager.contracts)
        let plan = SessionDedupe.plan(
            groups: SessionIntegrity.duplicateSessionGroups(in: dataManager.sessionEvents),
            redeemedSessionIds: redeemed)

        // Phase 2.1 adoption plan rides along — same read-only guarantee.
        let adoption = SessionAdoption.plan(sessions: dataManager.sessionEvents,
                                            programs: dataManager.programs,
                                            contracts: dataManager.contracts,
                                            students: dataManager.students)

        let phasePlan = PhaseAssignment.plan(sessions: dataManager.sessionEvents,
                                             phases: dataManager.microCycles)

        let text = SessionIntegrity.report(census)
            + "\n\n" + SessionDedupe.report(plan)
            + "\n\n" + SessionAdoption.report(adoption)
            + "\n\n" + PhaseAssignment.report(phasePlan)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
    #endif

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

    /// Headless Parent Guide export, same channel as the statement.
    /// HOOPWISE_EXPORT_GUIDE="<programName>" (or "*" for the first program)
    /// renders the PDF and the long image in English and Chinese through the
    /// same makeInput/render calls the Parent Guide screen uses, into the App
    /// Group's Library/Caches as guide-debug-{en,zh}.{pdf,jpg}. Append
    /// ":stress" to fill every coach-written field with long text — passed
    /// straight to makeInput, never saved — to exercise pagination.
    @MainActor
    private func exportGuideIfRequested() {
        guard let spec = ProcessInfo.processInfo
            .environment["HOOPWISE_EXPORT_GUIDE"] else { return }
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
        let name = parts.first.map(String.init) ?? "*"
        let stress = parts.dropFirst().contains("stress")
        guard let program = name == "*" ? dataManager.programs.first
                : dataManager.programs.first(where: { $0.name == name }),
              let dir = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches", isDirectory: true)
        else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var notes = ProgramGuideStore.notes(for: program.id)
        if stress {
            let zh = "孩子们会在每节课里反复练习运球、传球和投篮的基本动作，教练会根据每个孩子的情况调整难度，让每个人都能在挑战中进步，并且学会在团队里沟通、互相鼓励。"
            let en = "Every session repeats the fundamentals — dribbling, passing and shooting — and the coach adjusts the difficulty for each child so everyone is stretched without being lost, and learns to talk and encourage teammates on court."
            let long = (0..<4).map { _ in zh + " " + en }.joined(separator: "\n\n")
            notes.purpose = long
            notes.sessionNote = zh + en
            notes.reviewNote = long
            notes.coachNote = long
            notes.homeActivity = zh + "\n" + en
        }
        for chinese in [false, true] {
            let input = ProgramGuideDocument.makeInput(
                program: program, dataManager: dataManager, notes: notes,
                academyName: ProgramGuideStore.academyName, isChinese: chinese)
            let tag = chinese ? "zh" : "en"
            _ = try? ProgramGuideDocument.renderPDF(
                input, to: dir.appendingPathComponent("guide-debug-\(tag).pdf"))
            if let image = try? ProgramGuideDocument.renderLongImage(input) {
                let target = dir.appendingPathComponent("guide-debug-\(tag).jpg")
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: image, to: target)
            }
        }
    }
    #endif
}
