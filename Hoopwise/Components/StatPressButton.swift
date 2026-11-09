import SwiftUI

// MARK: - One touch, one action
//
// Live-game stat buttons: TAP adds the stat, HOLD removes one. They used to be
// a `Button` with a `simultaneousGesture(LongPressGesture)`: the hold removed
// the stat at 0.5s and lifting the finger then fired the Button's own tap, so
// the stat came straight back (October 2026, field report). The gate below is
// the rule — a touch that removed can never also add — and the view feeds it
// from exclusive tap / long-press recognisers.

/// Decides what a touch on a stat button does. Pure, so it can be tested.
struct StatPressGate {
    /// How long a touch must be held to remove instead of add.
    static let holdDuration: TimeInterval = 0.5
    /// A tap this soon after a removal is the same touch being lifted.
    static let releaseWindow: TimeInterval = 0.6

    private(set) var lastRemoval: Date?

    /// The hold elapsed: remove one.
    mutating func hold(at now: Date) -> Bool {
        lastRemoval = now
        return true
    }

    /// The finger lifted as a tap: add — unless this touch already removed.
    func tap(at now: Date) -> Bool {
        guard let lastRemoval else { return true }
        return now.timeIntervalSince(lastRemoval) > Self.releaseWindow
    }
}

/// A live-game stat button: tap = add, hold = remove one. Never both.
struct StatPressButton: View {
    let label: String
    let color: Color
    let add: () -> Void
    let remove: () -> Void
    /// Grow to the height the parent offers (the live panel's tall rows)
    /// instead of the 34pt strip button.
    var fillsHeight = false
    var font: Font = .caption.bold()
    /// SF Symbol shown above the label, so the action reads at a glance.
    var icon: String? = nil

    @State private var gate = StatPressGate()
    @State private var addTick = 0
    @State private var removeTick = 0

    private func label(_ font: Font) -> some View {
        Text(label)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    var body: some View {
        // Icon and label keep clear of the edges at any size (Luther,
        // November 2026: STL and BLK's hands touched their borders): both
        // are sized from the button's own height, inside an inset.
        GeometryReader { proxy in
            let inner = proxy.size.height - 10
            SwiftUI.Group {
                if let icon, inner >= 40 {
                    // Tall: the symbol over the word.
                    VStack(spacing: max(2, inner * 0.06)) {
                        Image(systemName: icon)
                            .font(.system(size: min(fillsHeight ? 20 : 14, inner * 0.34), weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        label(font)
                    }
                } else if let icon, inner >= 18 {
                    // Short: the symbol beside the word.
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: min(14, inner * 0.55), weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        label(font)
                    }
                } else {
                    label(font)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: fillsHeight ? .infinity : 34)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture {
                guard gate.tap(at: Date()) else { return }
                addTick += 1
                add()
            }
            .onLongPressGesture(minimumDuration: StatPressGate.holdDuration) {
                guard gate.hold(at: Date()) else { return }
                removeTick += 1
                remove()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: addTick)
            .sensoryFeedback(.warning, trigger: removeTick)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if gate.tap(at: Date()) { add() } }
            .accessibilityAction(named: "Remove one") { remove() }
    }
}
