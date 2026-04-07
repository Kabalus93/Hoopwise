import SwiftUI

#if os(macOS)
/// macOS shell — sidebar navigation wrapping the same views used on iOS.
/// All feature logic lives in the shared iOS views; this file is only layout.
struct MacContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab: MacTab = .home
    @State private var showingSettings = false

    enum MacTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case sessions = "Sessions"
        case students = "Students"
        case hub = "Hub"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home:     return "house.fill"
            case .sessions: return "calendar"
            case .students: return "person.2.fill"
            case .hub:      return "square.grid.2x2.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 260)
        } detail: {
            detailContent
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            MacSettingsView()
                .environmentObject(dataManager)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand header
            HStack(spacing: 10) {
                Image("HoopwiseLogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Hoopwise")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Basketball Training Manager")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            // Navigation items
            VStack(spacing: 4) {
                ForEach(MacTab.allCases) { tab in
                    sidebarButton(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Bottom: profile + sync + settings
            Divider().padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button(action: { showingSettings = true }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppTheme.accentColor.opacity(0.3))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Text(profileInitials)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.accentColor)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(profileName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text("Coach")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Sync
                Button(action: { Task { await dataManager.fullSync() } }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(SupabaseManager.shared.isConnected ? .green : .secondary)
                        .rotationEffect(.degrees(dataManager.isSyncing ? 360 : 0))
                        .animation(
                            dataManager.isSyncing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: dataManager.isSyncing
                        )
                }
                .buttonStyle(.plain)
                .help("Sync with cloud")

                // Settings
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarButton(_ tab: MacTab) -> some View {
        let isSelected = selectedTab == tab
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? AppTheme.accentColor : .secondary)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()

                if let badge = badgeCount(for: tab) {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.accentColor.opacity(0.8), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for tab: MacTab) -> Int? {
        switch tab {
        case .home:
            let count = expiringContractCount + dataManager.overdueReminders.count
            return count > 0 ? count : nil
        case .sessions:
            let upcoming = dataManager.upcomingSessions.count
            return upcoming > 0 ? upcoming : nil
        default:
            return nil
        }
    }

    private var expiringContractCount: Int {
        let twoWeeks = Date().addingTimeInterval(14 * 24 * 3600)
        return dataManager.contracts.filter { contract in
            contract.status == .active &&
            !contract.isPayAsYouGo &&
            ((contract.expiryDate ?? .distantFuture) <= twoWeeks || (contract.remainingSessions ?? 100) <= 3)
        }.count
    }

    private var profileName: String {
        let name = dataManager.coach.name
        return name.isEmpty ? "Set up profile" : name
    }

    private var profileInitials: String {
        let initials = dataManager.coach.initials
        return initials.isEmpty ? "?" : initials
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .home:
            FlightyActionableDashboard()
        case .sessions:
            FlightySessionRootView()
        case .students:
            NavigationStack {
                StudentIntelligenceListView()
            }
        case .hub:
            FlightyHubView()
        }
    }
}
#endif
