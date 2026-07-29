import SwiftUI

// MARK: - Filter Chip
// Small pill-shaped toggle used in filter rows across the app.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = AppTheme.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color : AppTheme.surfaceColor)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini Team Logo
// Compact circular team badge used in schedule pickers and lists.
struct MiniTeamLogo: View {
    let team: Team?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(team?.primaryColor ?? .gray)
            Text(String((team?.shortName ?? "?").prefix(1)))
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

typealias TeamLogo = MiniTeamLogo

// MARK: - Visual Effect Blur
// Cross-platform UIKit/AppKit blur for use behind glass surfaces.
#if os(iOS)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
#else
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
