import SwiftUI
import CloudKit

struct MacSettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var syncMonitor = CloudSyncMonitor.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            profileTab.tabItem { Label("Profile", systemImage: "person.crop.circle") }
            syncTab.tabItem { Label("Sync", systemImage: "icloud") }
            dataTab.tabItem { Label("Data", systemImage: "internaldrive") }
        }
        .frame(width: 520, height: 380)
    }

    private var generalTab: some View {
        Form {
            Text("Hoopwise").font(.title3.weight(.semibold))
            Text("Coaching workspace for Mac").foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var profileTab: some View {
        Form {
            LabeledContent("Coach", value: dataManager.coach.name.isEmpty ? "—" : dataManager.coach.name)
        }
        .formStyle(.grouped)
        .padding()
    }

    // Deliberately has no "Sync Now" or "Auto Sync" control. SwiftData drives CloudKit
    // itself, so neither would do anything, and CLAUDE.md rule 6 forbids replicating the
    // iOS placebos. What this shows instead is the state that was previously invisible.
    private var syncTab: some View {
        Form {
            if let failure = SwiftDataManager.startupFailure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Store")
                }
            }

            Section {
                LabeledContent("iCloud Account") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accountStatusColor)
                            .frame(width: 8, height: 8)
                        Text(syncMonitor.accountStatusLabel)
                    }
                }

                if let advice = syncMonitor.accountStatusAdvice {
                    Text(advice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if syncMonitor.isSyncing { ProgressView().controlSize(.small) }
                        Text(syncMonitor.activity.label)
                    }
                }

                LabeledContent("Last Synced", value: syncMonitor.lastSyncLabel)
            }

            Section {
                if let error = syncMonitor.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("No sync errors", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Environment", value: syncMonitor.environmentLabel)
                LabeledContent("Container", value: CloudSyncMonitor.containerIdentifier)
                    .textSelection(.enabled)
            } footer: {
                Text("Development and Production are separate databases. A debug build never sees data written by a TestFlight or App Store build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check iCloud Account") {
                    Task { await syncMonitor.refreshAccountStatus() }
                }
                .disabled(syncMonitor.isCheckingAccount)
            } footer: {
                Text("SwiftData syncs with CloudKit automatically; there is nothing to trigger by hand. This re-checks the account this build can reach.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await syncMonitor.refreshAccountStatus() }
    }

    private var accountStatusColor: Color {
        switch syncMonitor.accountStatus {
        case .available:  return .green
        case .noAccount:  return .orange
        case .restricted: return .red
        default:          return .gray
        }
    }

    private var dataTab: some View {
        Form {
            Button("Refresh All Data") {
                Task { await dataManager.refreshAllCaches() }
            }
            LabeledContent("Athletes", value: "\(dataManager.students.count)")
            LabeledContent("Sessions", value: "\(dataManager.sessionEvents.count)")
            LabeledContent("Programs", value: "\(dataManager.programs.count)")
        }
        .formStyle(.grouped)
        .padding()
    }
}
