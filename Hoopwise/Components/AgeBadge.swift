import SwiftUI

// MARK: - Age Badge
/// Compact badge that visualizes an age group (e.g., "U12") in a tinted pill.
/// Apple-style: single tone, high-contrast monogram, no gradient or shadow.
/// Reused on programs, sessions, students, and category rows so the visual
/// language for "age group" is consistent everywhere.
struct AgeBadge: View {
    enum Size {
        case xsmall   // inline next to a label, ~22pt height
        case small    // list-row leading, ~28pt height
        case medium   // primary identity icon for a row, ~44pt
        case large    // detail header, ~64pt

        var height: CGFloat {
            switch self {
            case .xsmall: return 22
            case .small:  return 28
            case .medium: return 44
            case .large:  return 64
            }
        }

        var font: Font {
            switch self {
            case .xsmall: return .caption2.weight(.semibold)
            case .small:  return .caption.weight(.semibold)
            case .medium: return .body.weight(.semibold)
            case .large:  return .title2.weight(.bold)
            }
        }

        var corner: CGFloat {
            switch self {
            case .xsmall, .small: return 6
            case .medium:         return 12
            case .large:          return 16
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .xsmall: return 6
            case .small:  return 8
            case .medium: return 10
            case .large:  return 14
            }
        }
    }

    let shortName: String        // e.g. "U12", "18+"
    var tint: Color = .accentColor
    var size: Size = .small
    var filled: Bool = false     // filled vs. tonal

    var body: some View {
        Text(shortName.uppercased())
            .font(size.font)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, size.hPadding)
            .frame(minWidth: size.height, minHeight: size.height)
            .foregroundStyle(filled ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(filled ? tint : tint.opacity(0.15))
            )
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            AgeBadge(shortName: "U6",  tint: Color(hex: "#FFD93D"))
            AgeBadge(shortName: "U8",  tint: AppTheme.avatarPink)
            AgeBadge(shortName: "U10", tint: AppTheme.avatarOrange)
            AgeBadge(shortName: "U12", tint: AppTheme.avatarYellow)
            AgeBadge(shortName: "U14", tint: AppTheme.avatarGreen)
            AgeBadge(shortName: "U16", tint: AppTheme.avatarBlue)
        }
        HStack(spacing: 12) {
            AgeBadge(shortName: "U12", tint: .accentColor, size: .medium)
            AgeBadge(shortName: "U14", tint: .accentColor, size: .medium, filled: true)
            AgeBadge(shortName: "U16", tint: .blue,        size: .large)
        }
    }
    .padding()
}
