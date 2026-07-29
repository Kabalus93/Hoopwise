import SwiftUI
import CloudKit

// MARK: - Sync Status View
struct SyncStatusView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastCloudKitSyncDate") as? Date
    @State private var isRefreshing = false

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    statusCard
                    detailsCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(.regularMaterial)
            .navigationTitle(isChinese ? "iCloud 同步" : "iCloud Sync")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .task { await refreshAccountStatus() }
            .refreshable { await refreshAccountStatus() }
        }
    }

    // MARK: - Status Card
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            if let subtitle = statusSubtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(isChinese ? "上次同步" : "Last synced")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastSyncedLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Details Card
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isChinese ? "关于 iCloud 同步" : "About iCloud Sync")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(isChinese
                 ? "您的训练数据通过 iCloud 在所有登录同一 Apple ID 的设备之间安全同步。"
                 : "Your coaching data syncs securely across all devices signed in to the same Apple ID through iCloud.")
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Mapping
    private var statusTitle: String {
        switch accountStatus {
        case .available:              return "iCloud · Synced"
        case .noAccount:              return "iCloud · No Account"
        case .restricted:             return "iCloud · Restricted"
        case .couldNotDetermine:      return "iCloud · Unavailable"
        case .temporarilyUnavailable: return "iCloud · Reconnecting…"
        @unknown default:             return "iCloud · Unavailable"
        }
    }

    private var statusColor: Color {
        switch accountStatus {
        case .available:              return .green
        case .noAccount:              return .orange
        case .restricted:             return .red
        case .couldNotDetermine,
             .temporarilyUnavailable: return .gray
        @unknown default:             return .gray
        }
    }

    private var statusSubtitle: String? {
        switch accountStatus {
        case .noAccount:
            return isChinese ? "请在「设置」中登录 iCloud" : "Sign in to iCloud in Settings"
        case .restricted:
            return isChinese ? "iCloud 在此设备上受限制" : "iCloud is restricted on this device"
        case .temporarilyUnavailable:
            return isChinese ? "正在重新连接 iCloud…" : "Reconnecting to iCloud…"
        default:
            return nil
        }
    }

    private var lastSyncedLabel: String {
        guard let date = lastSyncDate else { return "—" }
        return date.formatted(.relative(presentation: .numeric))
    }

    // MARK: - Refresh
    private func refreshAccountStatus() async {
        await MainActor.run { isRefreshing = true }
        do {
            let status = try await CKContainer.default().accountStatus()
            await MainActor.run {
                self.accountStatus = status
                self.lastSyncDate = UserDefaults.standard.object(forKey: "lastCloudKitSyncDate") as? Date
                self.isRefreshing = false
            }
        } catch {
            debugLog("SyncStatusView: failed to read iCloud account status: \(error)")
            await MainActor.run {
                self.accountStatus = .couldNotDetermine
                self.isRefreshing = false
            }
        }
    }
}
