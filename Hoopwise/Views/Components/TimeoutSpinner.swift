import SwiftUI

/// A `ProgressView` that falls back to an error state if it spins past `timeout` seconds.
/// Use anywhere the underlying work could plausibly hang (CloudKit fetch, photo pipeline, network).
struct TimeoutSpinner: View {
    var label: String? = nil
    var timeout: TimeInterval = 8
    var onRetry: (() -> Void)? = nil

    @State private var timedOut = false

    var body: some View {
        Group {
            if timedOut {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "加载失败" : "Couldn't load")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let onRetry {
                        Button(LocalizationManager.shared.currentLanguage == .chinese ? "重试" : "Try Again") {
                            timedOut = false
                            onRetry()
                            scheduleTimeout()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    if let label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .task {
            scheduleTimeout()
        }
    }

    private func scheduleTimeout() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                timedOut = true
            }
        }
    }
}
