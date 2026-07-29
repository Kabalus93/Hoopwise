import SwiftUI

/// Compact pill that distinguishes private vs group at a glance. Sized to
/// sit comfortably next to age badges and status chips on session/student
/// cards. Three sizes cover most contexts.
struct FormatBadge: View {
    let format: SessionFormat
    var size: Size = .compact
    var showLabel: Bool = true

    enum Size {
        case mini    // icon-only dot used in tight rows (calendar grid)
        case compact // icon + short label, the default for cards/list rows
        case full    // icon + label, padded — used in detail headers
    }

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: format.icon)
                .font(.system(size: iconSize, weight: .semibold))
            if showLabel && size != .mini {
                Text(format.shortLabel)
                    .font(.system(size: textSize, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(format.tint)
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(
            Capsule().fill(format.tint.opacity(0.14))
        )
        .accessibilityLabel(format.shortLabel)
    }

    private var spacing: CGFloat {
        switch size {
        case .mini: return 0
        case .compact: return 4
        case .full: return 6
        }
    }
    private var iconSize: CGFloat {
        switch size {
        case .mini: return 9
        case .compact: return 10
        case .full: return 13
        }
    }
    private var textSize: CGFloat {
        switch size {
        case .mini: return 0
        case .compact: return 10
        case .full: return 13
        }
    }
    private var hPadding: CGFloat {
        switch size {
        case .mini: return 4
        case .compact: return 7
        case .full: return 10
        }
    }
    private var vPadding: CGFloat {
        switch size {
        case .mini: return 4
        case .compact: return 3
        case .full: return 5
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 8) {
            FormatBadge(format: .privateClient, size: .mini)
            FormatBadge(format: .group, size: .mini)
        }
        HStack(spacing: 8) {
            FormatBadge(format: .privateClient)
            FormatBadge(format: .group)
        }
        HStack(spacing: 8) {
            FormatBadge(format: .privateClient, size: .full)
            FormatBadge(format: .group, size: .full)
        }
    }
    .padding()
}
