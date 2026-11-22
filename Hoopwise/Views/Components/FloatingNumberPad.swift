import SwiftUI

// THE FLOATING NUMBER PAD (23 Nov 2026, Luther, markup on a phone-style keypad
// floating over a sign-in field: "I prefer this floating number pad to strictly
// enter numerical values through the app. Especially the trackable drills.").
// One keypad — 1–9, then [. or nothing] 0 ⌫ — on a frosted card, used:
//   · inline in the tracked drills' entry (NumberWheel now draws it), and
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
    var keyHeight: CGFloat = 52
    /// Each key's identifier is "<identifier>.key.<digit>" ("dot", "delete").
    var identifier = "numberPad"

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
                    Button { onKey("→") } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: keyHeight * 0.38, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: keyHeight, maxHeight: keyHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NumberKeyStyle(plain: true))
                    .accessibilityLabel("Next")
                    .accessibilityIdentifier("\(identifier).key.next")
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
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .sensoryFeedback(.selection, trigger: taps)
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

// MARK: - Two numbers, one pad

/// Two numbers typed on ONE pad (the shot chart: made, attempted). Tap a box
/// to type into it; → moves from the first to the second. Each box's first key
/// replaces its number, as on the single pad.
struct PairedNumberPad: View {
    struct Field {
        var title: String
        var range: ClosedRange<Int>
        var value: Binding<Int>
        var tint: Color
        var identifier: String
    }
    let first: Field
    let second: Field
    /// Keys: "<identifier>.key.<digit>", "<identifier>.key.next".
    var identifier = "pairPad"

    @State private var active = 0
    @State private var entries = [NumberPadEntry(text: ""), NumberPadEntry(text: "")]
    @State private var written: [Int?] = [nil, nil]

    private var fields: [Field] { [first, second] }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                box(0)
                box(1)
            }
            FloatingNumberPad(onKey: type, nextKey: active == 0, keyHeight: 48, identifier: identifier)
                .frame(maxWidth: 340)
        }
        .onAppear { reset(0); reset(1) }
        .onChange(of: first.value.wrappedValue) { _, v in if v != written[0] { reset(0) } }
        .onChange(of: second.value.wrappedValue) { _, v in if v != written[1] { reset(1) } }
    }

    private func box(_ i: Int) -> some View {
        let f = fields[i]
        let on = active == i
        return Button { active = i; entries[i].fresh = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("\(f.value.wrappedValue)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? f.tint : .clear, lineWidth: 2.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(f.identifier).value")
        .accessibilityValue("\(f.value.wrappedValue)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func reset(_ i: Int) {
        entries[i] = NumberPadEntry(text: "", maximum: Double(fields[i].range.upperBound))
        entries[i].reset(to: Double(fields[i].value.wrappedValue))
        written[i] = nil
        active = 0   // a new zone or athlete starts on the first box
    }

    private func type(_ key: Character) {
        if key == "→" { active = 1; entries[1].fresh = true; return }
        let i = active
        if key == "⌫" { entries[i].delete() } else { entries[i].press(key) }
        let r = fields[i].range
        let v = entries[i].text.isEmpty ? r.lowerBound : max(r.lowerBound, min(r.upperBound, Int(entries[i].value)))
        written[i] = v
        withAnimation(.snappy(duration: 0.15)) { fields[i].value.wrappedValue = v }
    }
}
