import SwiftUI
import Foundation

// MARK: - Navigation Notification Names
extension Notification.Name {
    /// Open the live-session screen from anywhere in the app. The persistent
    /// pill and the dashboard's live card both post this.
    static let openLiveSession = Notification.Name("openLiveSession")
}

struct MainTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var sessionMonitor = SessionStatusMonitor.shared
    @ObservedObject private var liveEngine = LiveSessionEngine.shared
    @SceneStorage("selectedTab") private var selectedTab: Int = 0
    @State private var showingLiveSheet = false
    @State private var showingRollCallFromBanner = false
    @State private var widgetDeepLink: WidgetDeepLink?

    /// Widget tap-through target. One item drives one sheet so a session tap
    /// arriving while an athlete sheet is up just swaps the content.
    enum WidgetDeepLink: Identifiable {
        case session(SessionEvent)
        case athlete(Student)

        var id: UUID {
            switch self {
            case .session(let session): return session.id
            case .athlete(let student): return student.id
            }
        }
    }

    private var isChinese: Bool { localizationManager.currentLanguage == .chinese }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                Tab(isChinese ? "首页" : "Home", systemImage: "house.fill", value: 0) {
                    FlightyActionableDashboard()
                }

                Tab(isChinese ? "课程" : "Sessions", systemImage: "calendar", value: 1) {
                    FlightySessionRootView()
                }

                Tab(isChinese ? "学员" : "Athletes", systemImage: "person.2.fill", value: 2) {
                    NavigationStack {
                        StudentIntelligenceListView()
                    }
                }

                Tab(isChinese ? "中心" : "Hub", systemImage: "square.grid.2x2.fill", value: 3) {
                    FlightyHubView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)

            // Persistent live-session pill. Appears across every tab while a
            // run is active, so dismissing the live screen never hides the
            // fact that a session is still running. Hidden while the live
            // sheet is up to avoid double-rendering the same indicator.
            if liveEngine.isActive, !showingLiveSheet, let live = liveEngine.session {
                LiveSessionPill(
                    session: live,
                    programColor: Color(hex: liveEngine.programColorHex),
                    remaining: liveEngine.sessionRemainingSeconds,
                    isPaused: liveEngine.isPaused
                ) {
                    showingLiveSheet = true
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: liveEngine.isActive)
        .tint(Color.accentColor)
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .fullScreenCover(isPresented: $showingLiveSheet) {
            LiveSessionView { showingLiveSheet = false }
        }
        .onChange(of: liveEngine.rollCallPromptPending) { _, pending in
            // If the live screen is dismissed but the engine fires the
            // 5-min reminder, surface a global sheet so it isn't missed.
            if pending && !showingLiveSheet { showingRollCallFromBanner = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLiveSession)) { _ in
            if liveEngine.isActive { showingLiveSheet = true }
        }
        // Widget deep links (the one sanctioned freeze exception). onReceive
        // handles warm taps; onAppear drains a route queued during cold start,
        // when the URL arrived before this view existed.
        .onAppear { consumePendingWidgetRoute() }
        .onReceive(NotificationCenter.default.publisher(for: .hoopwiseOpenSessionRequest)) { note in
            PendingWidgetRoute.pending = nil
            if let id = note.object as? UUID { openWidgetSession(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hoopwiseOpenAthleteRequest)) { note in
            PendingWidgetRoute.pending = nil
            if let id = note.object as? UUID { openWidgetAthlete(id) }
        }
        .sheet(item: $widgetDeepLink) { link in
            switch link {
            case .session(let session):
                NavigationStack {
                    FlightySessionPageView(session: session, accessMode: .execution)
                }
            case .athlete(let student):
                NavigationStack {
                    StudentDetailView(student: student)
                }
            }
        }
        .sheet(isPresented: $showingRollCallFromBanner, onDismiss: {
            liveEngine.dismissRollCallPrompt()
        }) {
            RollCallPhotoSheet(programColor: Color(hex: liveEngine.programColorHex)) { image in
                #if os(iOS)
                if let s = liveEngine.session,
                   let path = PhotoCaptureManager.shared.saveAttendancePhoto(image, for: s.id) {
                    var updated = s
                    updated.attendancePhotoPath = path
                    liveEngine.session = updated
                    dataManager.updateSessionEvent(updated)
                }
                #endif
                liveEngine.dismissRollCallPrompt()
            }
        }
    }

    // MARK: - Widget deep-link routing

    private func consumePendingWidgetRoute() {
        guard let route = PendingWidgetRoute.pending else { return }
        PendingWidgetRoute.pending = nil
        WidgetSnapshotWriter.traceDeepLink("cold-start pending route consumed")
        switch route {
        case .session(let id): openWidgetSession(id)
        case .athlete(let id): openWidgetAthlete(id)
        }
    }

    private func openWidgetSession(_ id: UUID) {
        let session = dataManager.sessionEvents.first(where: { $0.id == id })
        WidgetSnapshotWriter.traceDeepLink("session \(id) found=\(session != nil)")
        guard let session else { return }
        widgetDeepLink = .session(session)
    }

    private func openWidgetAthlete(_ id: UUID) {
        let student = dataManager.students.first(where: { $0.id == id })
        WidgetSnapshotWriter.traceDeepLink("athlete \(id) found=\(student != nil)")
        guard let student else { return }
        widgetDeepLink = .athlete(student)
    }
}

// MARK: - Live Session Pill
/// Compact persistent indicator that a session is live. Tap to resume the
/// live screen. Sits at the top edge above all tabs.
struct LiveSessionPill: View {
    let session: SessionEvent
    let programColor: Color
    let remaining: Int
    let isPaused: Bool
    let onTap: () -> Void

    private var remainingLabel: String {
        let r = max(remaining, 0)
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isPaused ? Color.secondary : Color.red)
                    .frame(width: 8, height: 8)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isPaused)

                Text(isPaused ? "PAUSED" : "LIVE")
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(isPaused ? Color.secondary : Color.red)

                Text(session.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(remainingLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(programColor)

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(programColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    MainTabView()
        .environmentObject(DataManager.shared)
}
