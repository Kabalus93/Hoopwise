import SwiftUI

// THE FLOATING NUMBER PAD (23 Nov 2026, Luther, markup on a phone-style keypad
// floating over a sign-in field: "I prefer this floating number pad to strictly
// enter numerical values through the app. Especially the trackable drills.").
// One keypad — 1–9, then [✓ / → / .] 0 ⌫ — used:
//   · as the tracked drills' log popup (`cellNumberPad`): the keys alone,
//     popping out of the tapped table cell or shot-chart zone, and
//   · as a popover from any number field (`NumberPadField`), in place of the
//     system keyboard (on the iPad `.numberPad` brings up the full keyboard).

/// What the keys have typed, as text. The first key after the pad opens (or
/// after the value was set from outside) REPLACES what was there; later keys
/// append. A value past `maximum` starts again from the key just pressed.
nonisolated struct NumberPadEntry: Equatable {
    var text: String
    var fresh = true
    var maximum: Double?
    var decimals: Int = 0

    init(text: String, maximum: Double? = nil, decimals: Int = 0) {
        self.text = text
        self.maximum = maximum
        self.decimals = decimals
    }

    var value: Double { Double(text) ?? 0 }

    mutating func press(_ key: Character) {
        if key == "." {
            guard decimals > 0 else { return }
            if fresh { text = "0."; fresh = false; return }
            if !text.contains(".") { text = (text.isEmpty ? "0" : text) + "." }
            return
        }
        guard key.isNumber else { return }
        var next = fresh ? String(key) : text + String(key)
        fresh = false
        if let dot = next.firstIndex(of: "."), next.distance(from: dot, to: next.endIndex) - 1 > decimals { return }
        // No leading zeros ("05" → "5").
        if next.count > 1, next.hasPrefix("0"), !next.hasPrefix("0.") { next.removeFirst() }
        if let maximum, (Double(next) ?? 0) > maximum {
            guard (Double(String(key)) ?? 0) <= maximum else { return }
            next = String(key)
        }
        text = next
    }

    mutating func delete() {
        fresh = false
        if !text.isEmpty { text.removeLast() }
    }

    /// The value was set from outside: show it, and let the next key replace it.
    mutating func reset(to value: Double) {
        text = decimals > 0 ? NumberPadEntry.format(value, decimals: decimals) : String(Int(value.rounded()))
        fresh = true
    }

    static func format(_ value: Double, decimals: Int) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.\(decimals)f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

/// The keys.
struct FloatingNumberPad: View {
    /// A digit, "." or "⌫".
    var onKey: (Character) -> Void
    var allowsDecimal = false
    /// The bottom-left key when there is no decimal point: "→" (next field).
    var nextKey = false
    /// A ✓ key ("✓"): log and go on (the tracked-drill popup).
    var confirmKey = false
    var keyHeight: CGFloat = 52
    /// Each key's identifier is "<identifier>.key.<digit>" ("dot", "delete").
    var identifier = "numberPad"
    /// The frosted card around the keys; off inside a popover, which has its own.
    var chrome = true

    private let rows: [[Character]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) { ForEach(row, id: \.self) { key($0) } }
            }
            HStack(spacing: 8) {
                if allowsDecimal {
                    key(".")
                } else if nextKey {
                    actionKey("→", symbol: "arrow.right", name: "next", label: "Next", prominent: false)
                } else if confirmKey {
                    actionKey("✓", symbol: "checkmark", name: "confirm", label: "Log", prominent: true)
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: keyHeight)
                }
                key("0")
                Button { onKey("⌫") } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: keyHeight * 0.4, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: keyHeight, maxHeight: keyHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NumberKeyStyle(plain: true))
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("\(identifier).key.delete")
            }
            // With a decimal point the action gets a row of its own.
            if allowsDecimal && (nextKey || confirmKey) {
                if nextKey {
                    actionKey("→", symbol: "arrow.right", name: "next", label: "Next", prominent: false)
                } else {
                    actionKey("✓", symbol: "checkmark", name: "confirm", label: "Log", prominent: true)
                }
            }
        }
        .padding(chrome ? 10 : 0)
        .background {
            if chrome { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial) }
        }
        .shadow(color: .black.opacity(chrome ? 0.12 : 0), radius: 14, y: 6)
        .sensoryFeedback(.selection, trigger: taps)
    }

    private func actionKey(_ k: Character, symbol: String, name: String, label: String, prominent: Bool) -> some View {
        Button { onKey(k) } label: {
            Image(systemName: symbol)
                .font(.system(size: keyHeight * 0.4, weight: .bold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: keyHeight, maxHeight: keyHeight)
                .background {
                    if prominent { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(NumberKeyStyle(plain: true))
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(identifier).key.\(name)")
    }

    @State private var taps = 0

    private func key(_ k: Character) -> some View {
        Button {
            taps += 1
            onKey(k)
        } label: {
            Text(String(k))
                .font(.system(size: keyHeight * 0.48, weight: .regular, design: .default))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: keyHeight, maxHeight: keyHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(NumberKeyStyle(plain: false))
        .accessibilityIdentifier("\(identifier).key.\(k == "." ? "dot" : String(k))")
    }
}

/// A white key that darkens while pressed, like the system keypad.
private struct NumberKeyStyle: ButtonStyle {
    var plain: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(plain ? (configuration.isPressed ? Color(.systemFill) : .clear)
                                : (configuration.isPressed ? Color(.systemGray4) : Color(.secondarySystemGroupedBackground)))
                    .shadow(color: .black.opacity(plain ? 0 : 0.08), radius: 0.5, y: 1)
            )
    }
}

// MARK: - A number field that opens the pad

/// A form row's number, typed on the floating pad in a popover (no system
/// keyboard). Tap the number to open it; tap outside or ✓ to close.
struct NumberPadField: View {
    var prompt: String = "0"
    @Binding var value: Double
    var decimals: Int = 2
    var maximum: Double? = nil
    var identifier = "numberPadField"

    @State private var open = false
    @State private var entry = NumberPadEntry(text: "")

    var body: some View {
        Button {
            entry = NumberPadEntry(text: "", maximum: maximum, decimals: decimals)
            entry.reset(to: value)
            open = true
        } label: {
            Text(value == 0 && !open ? prompt : NumberPadEntry.format(value, decimals: decimals))
                .monospacedDigit()
                .foregroundStyle(value == 0 && !open ? .secondary : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(open ? Color.accentColor.opacity(0.15) : .clear))
                .frame(minWidth: 60, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(spacing: 10) {
                Text(entry.text.isEmpty ? "0" : entry.text)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                FloatingNumberPad(onKey: { k in
                    if k == "⌫" { entry.delete() } else { entry.press(k) }
                    value = entry.value
                }, allowsDecimal: decimals > 0, keyHeight: 48, identifier: identifier)
            }
            .padding(12)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The same for whole numbers kept as text (a jersey number).
struct NumberPadTextField: View {
    var prompt: String = "#"
    @Binding var text: String
    var identifier = "numberPadText"

    var body: some View {
        NumberPadField(prompt: prompt, value: Binding(
            get: { Double(text) ?? 0 },
            set: { text = $0 == 0 ? "" : String(Int($0)) }
        ), decimals: 0, maximum: 999, identifier: identifier)
    }
}

// MARK: - The tracked-drill popup: keys alone, out of the cell

/// What a tracked drill's table cell opens (23 Nov 2026, Luther: "the log pad
/// should be as clean as in the screenshot, just a number pad … the spots
/// already appear on the drill screen, and the athletes too"). The keys pop
/// out of the tapped cell; what is typed shows IN the cell; ✓ logs it and the
/// next cell opens; a tap outside keeps what was typed and closes.
struct CellNumberPad: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var draft: NumberPadEntry
    var identifier: String
    var onConfirm: () -> Void
    /// The popup has gone (the next cell may open now — opening it while
    /// this one is still closing is refused by iOS).
    var onClosed: () -> Void = {}

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented) {
            FloatingNumberPad(onKey: { k in
                switch k {
                case "✓": onConfirm()
                case "⌫": draft.delete()
                default: draft.press(k)
                }
            }, allowsDecimal: draft.decimals > 0, confirmKey: true, keyHeight: 56,
               identifier: identifier, chrome: false)
                .padding(12)
                .frame(width: 280)
                .presentationCompactAdaptation(.popover)
                .onDisappear(perform: onClosed)
        }
    }
}

extension View {
    func cellNumberPad(isPresented: Binding<Bool>, draft: Binding<NumberPadEntry>, identifier: String,
                       onConfirm: @escaping () -> Void, onClosed: @escaping () -> Void = {}) -> some View {
        modifier(CellNumberPad(isPresented: isPresented, draft: draft, identifier: identifier,
                               onConfirm: onConfirm, onClosed: onClosed))
    }
}

/// One cell of a tracked drill's table: which athlete, which spot.
struct PadCell: Hashable {
    var student: UUID
    var spot: Int
}

extension NumberPadEntry {
    /// A cell's draft: what is in it (replaced by the first key), at most `maximum`.
    static func cell(_ value: Double?, maximum: Double, decimals: Int = 0) -> NumberPadEntry {
        var e = NumberPadEntry(text: "", maximum: maximum, decimals: decimals)
        if let value { e.reset(to: value) }
        return e
    }

    /// Something was typed (not just opened and confirmed).
    var typed: Bool { !fresh }
}
