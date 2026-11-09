import SwiftUI

// HoopWise Journal's design tokens and components, as the Plays screens use
// them (Luther, November 2026: the Journal's Plays tab, taken as is). The
// J prefix keeps them apart from Hoopwise's own Theme; the values are the
// Journal's, unchanged.

enum JSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let screen: CGFloat = 16
}

enum JRadius {
    static let card: CGFloat = 16
    static let tile: CGFloat = 12
}

enum JTouchTarget {
    static let standard: CGFloat = 44
}

enum JPalette {
    static let background = Color(.systemBackground)
    static let ink = Color(.label)
    static let card = Color(.secondarySystemBackground)
    static let fill = Color(.tertiarySystemFill)
    // Courts and play diagrams: thin warm-grey lines, offense in blue, the
    // defender to read in amber.
    static let courtLine = Color(uiColor: .jAdaptive(light: 0xC3C2B7, dark: 0x4A4945))
    static let play = Color(uiColor: .jAdaptive(light: 0x2A78D6, dark: 0x3987E5))
    static let read = Color(uiColor: .jAdaptive(light: 0xB27200, dark: 0xFAB219))
    /// Shots, and dribbles that finish at the rim.
    static let shot = Color(uiColor: .jAdaptive(light: 0xD8342C, dark: 0xFF5A4F))
    /// Training cones (drill drawings): safety orange.
    static let cone = Color(uiColor: .jAdaptive(light: 0xF06A00, dark: 0xFF8A2A))
}

enum JMotion {
    static let expand = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension UIColor {
    convenience init(jHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func jAdaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(jHex: dark) : UIColor(jHex: light) }
    }
}

/// The Journal's category colours (only `court` and `neutral` are used here).
enum JCategory: Sendable {
    case court
    case neutral

    var uiColor: UIColor {
        switch self {
        case .court: .jAdaptive(light: 0xE07A2E, dark: 0xFF9548)
        case .neutral: .label
        }
    }

    var iconUIColor: UIColor {
        switch self {
        case .court: .jAdaptive(light: 0xB4541A, dark: 0xFFAE6E)
        case .neutral: .label
        }
    }

    var tileUIColor: UIColor {
        switch self {
        case .neutral: .tertiarySystemFill
        default:
            UIColor { traits in
                self.uiColor.resolvedColor(with: traits)
                    .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.22 : 0.15)
            }
        }
    }

    var color: Color { Color(uiColor: uiColor) }
    var iconColor: Color { Color(uiColor: iconUIColor) }
    var tile: Color { Color(uiColor: tileUIColor) }
}

/// The primary card: glass, radius 16, standard padding, no shadow.
struct JCard<Content: View>: View {
    var verticalPadding: CGFloat = JSpacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JSpacing.m)
            .padding(.vertical, verticalPadding)
            .glassEffect(.regular, in: .rect(cornerRadius: JRadius.card))
    }
}

/// Section label. Uppercase and tracked in English; in Chinese, no
/// uppercase transform and no extra tracking.
struct JEyebrowLabel: View {
    let title: JPString
    var systemImage: String?
    var category: JCategory = .neutral

    var body: some View {
        let latin = !JournalPlayLanguage.isChinese
        HStack(spacing: JSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(category == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(category.iconColor))
            }
            JText(title)
                .textCase(latin ? .uppercase : nil)
                .tracking(latin ? 0.6 : 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A small rounded tile with a category-coloured symbol.
struct JIconTile: View {
    let symbol: String
    var category: JCategory = .neutral
    var size: CGFloat = 28

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = min(size * scale, size * 1.5)
        Image(systemName: symbol)
            .font(.system(size: side * 0.52, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(category.iconColor)
            .frame(width: side, height: side)
            .background(category.tile, in: .rect(cornerRadius: side * 0.28))
            .accessibilityHidden(true)
    }
}

/// One line that stands for a whole section: tile, title, a short value and
/// a chevron.
struct JSummaryRow: View {
    let symbol: String
    var category: JCategory = .neutral
    let title: JPString
    var value: Text?
    var showsChevron = true
    var chevron = "chevron.right"

    var body: some View {
        HStack(spacing: JSpacing.s) {
            JIconTile(symbol: symbol, category: category)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JSpacing.xs) {
                    titleText
                    Spacer(minLength: JSpacing.xs)
                    valueText(.trailing)
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    valueText(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsChevron {
                Image(systemName: chevron)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: JTouchTarget.standard)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        JText(title)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func valueText(_ alignment: TextAlignment) -> some View {
        if let value {
            value
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment)
                .lineLimit(alignment == .leading ? nil : 2)
        }
    }
}

/// "Play deleted · Undo" for a few seconds after a delete. One at a time; a
/// new one replaces the old. One shared centre for the Plays screens (the
/// Journal kept it in the app's environment).
@MainActor @Observable
final class JUndoCenter {
    static let shared = JUndoCenter()

    struct Item: Identifiable {
        let id = UUID()
        let message: JPString
        let undo: () -> Void
    }

    private(set) var item: Item?

    func show(_ message: JPString, undo: @escaping () -> Void) {
        item = Item(message: message, undo: undo)
    }

    func dismiss(_ id: UUID) {
        if item?.id == id { item = nil }
    }

    func performUndo() {
        guard let item else { return }
        self.item = nil
        item.undo()
    }
}

struct JUndoToastView: View {
    private var center: JUndoCenter { .shared }

    var body: some View {
        if let item = center.item {
            HStack(spacing: JSpacing.s) {
                JText(item.message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: JSpacing.xs)
                Button {
                    withAnimation(JMotion.expand) { center.performUndo() }
                } label: {
                    JText("Undo")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(JPalette.background)
                        .padding(.horizontal, JSpacing.m)
                        .frame(minHeight: JTouchTarget.standard)
                }
                .buttonStyle(.glassProminent)
                .tint(JPalette.ink)
            }
            .padding(.leading, JSpacing.m)
            .padding(.trailing, JSpacing.xs)
            .padding(.vertical, JSpacing.xxs)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, JSpacing.screen)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: item.id) {
                try? await Task.sleep(for: .seconds(8))
                withAnimation(JMotion.expand) { center.dismiss(item.id) }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// The undo toast over a Plays screen.
    func journalUndoToast() -> some View {
        overlay(alignment: .bottom) {
            JUndoToastView()
                .animation(JMotion.expand, value: JUndoCenter.shared.item?.id)
        }
    }
}

#if DEBUG
/// DEBUG launch options for screenshots, the Journal's `-open` family as
/// environment variables: HOOPWISE_PLAYS_OPEN=play|study|playback|legend|
/// editor|details|newpart|newplay, HOOPWISE_PLAYS_PLAY=<starter key>,
/// HOOPWISE_PLAYS_PART=<n>, HOOPWISE_PLAYS_STEP=<n> (from 0).
struct JournalPlaysLaunch {
    static let current = JournalPlaysLaunch()
    private let env = ProcessInfo.processInfo.environment

    var open: String? { env["HOOPWISE_PLAYS_OPEN"] }
    var play: String? { env["HOOPWISE_PLAYS_PLAY"] }
    var part: Int? { env["HOOPWISE_PLAYS_PART"].flatMap(Int.init) }
    var step: Int? { env["HOOPWISE_PLAYS_STEP"].flatMap(Int.init) }
    func opens(_ name: String) -> Bool { open == name }
}
#endif
