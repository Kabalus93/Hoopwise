import SwiftUI

// MARK: - Sync Error Banner
// Displays sync status and errors at the top of the screen.
// Observes SyncState to show pending count, errors, and failed operations.

struct SyncErrorBanner: View {
    @ObservedObject var syncState: SyncState
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Transient error banner
            if let error = syncState.lastError {
                HStack(spacing: 8) {
                    Image(systemName: errorIcon(for: error))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(error.localizedDescription ?? "Sync error")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer()

                    if error.isRetryable {
                        Button(action: onRetry) {
                            Text("Retry")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: { syncState.clearError() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bannerColor(for: error))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Pending indicator (subtle)
            if syncState.isSyncing || syncState.pendingCount > 0 {
                HStack(spacing: 6) {
                    if syncState.isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                            #if os(iOS)
                            .tint(.secondary)
                            #endif
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }

                    Text(syncState.isSyncing
                         ? "Syncing…"
                         : "\(syncState.pendingCount) pending")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let date = syncState.lastSyncDate {
                        Text("Last sync: \(date, style: .relative) ago")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                #if os(iOS)
                .background(Color(.systemBackground).opacity(0.95))
                #else
                .background(Color(.windowBackgroundColor).opacity(0.95))
                #endif
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: syncState.lastError != nil)
        .animation(.easeInOut(duration: 0.25), value: syncState.pendingCount)
    }

    // MARK: - Helpers

    private func errorIcon(for error: SyncError) -> String {
        switch error {
        case .unauthorized:       return "lock.fill"
        case .networkUnavailable: return "wifi.slash"
        case .conflict:           return "arrow.triangle.2.circlepath"
        default:                  return "exclamationmark.triangle.fill"
        }
    }

    private func bannerColor(for error: SyncError) -> Color {
        switch error {
        case .unauthorized:       return .red
        case .networkUnavailable: return .orange
        case .conflict:           return .yellow.opacity(0.9)
        default:                  return .red.opacity(0.85)
        }
    }
}

// MARK: - Failed Operations List
// Shows persistently failed operations that need user attention.

struct FailedOperationsSheet: View {
    @ObservedObject var syncState: SyncState
    var onRetryAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if syncState.failedOperations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("No failed operations")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(syncState.failedOperations) { op in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: operationIcon(op.operation))
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                    Text("\(op.operation.rawValue.capitalized) on \(op.table)")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Text(op.errorMessage)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                Text(op.timestamp, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    syncState.removeFailedOperation(op.id)
                                } label: {
                                    Label("Dismiss", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Failed Syncs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13))
                }
                if !syncState.failedOperations.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Retry All") { onRetryAll() }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }

    private func operationIcon(_ kind: MutationKind) -> String {
        switch kind {
        case .insert: return "plus.circle"
        case .update: return "pencil.circle"
        case .delete: return "trash.circle"
        }
    }
}
