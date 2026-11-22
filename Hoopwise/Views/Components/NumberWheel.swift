import SwiftUI

/// Where a tracked drill's number is entered. It was a horizontal wheel
/// (21 Nov 2026); since 23 Nov 2026 it is the FLOATING NUMBER PAD (Luther:
/// "I prefer this floating number pad … especially the trackable drills") —
/// the number large in a window, the keypad under it. Same name and call so
/// every entry pad switched at once.
///
/// The first key after the value is set (a new athlete, a new spot, a quick
/// chip) replaces it; later keys append; a number past the range's top starts
/// again from the key just pressed. ⌫ with nothing left goes back to the
/// range's bottom.
struct NumberWheel: View {
    let range: ClosedRange<Int>
    @Binding var value: Int
    var tint: Color = .orange
    var itemWidth: CGFloat = 52
    /// Prefix for the keys' identifiers (UI tests): "<id>.key.<digit>", and
    /// "<id>.value" on the number.
    var identifier: String = "wheel"
    /// Off when the page shows the number itself (the custom tracking pad).
    var showsValue = true

    @State private var entry = NumberPadEntry(text: "")
    /// The value this pad last wrote, to tell an outside change from its own.
    @State private var written: Int?

    var body: some View {
        VStack(spacing: 10) {
            if showsValue {
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("\(identifier).value")
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(entry.fresh ? tint.opacity(0.35) : tint, lineWidth: 2.5)
                )
            }
            FloatingNumberPad(onKey: type, keyHeight: 48, identifier: identifier)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .onAppear { reset() }
        .onChange(of: value) { _, v in if v != written { reset() } }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func reset() {
        entry = NumberPadEntry(text: "", maximum: Double(range.upperBound))
        entry.reset(to: Double(value))
        written = nil
    }

    private func type(_ key: Character) {
        if key == "⌫" { entry.delete() } else { entry.press(key) }
        let v = entry.text.isEmpty ? range.lowerBound : max(range.lowerBound, min(range.upperBound, Int(entry.value)))
        written = v
        withAnimation(.snappy(duration: 0.15)) { value = v }
    }
}
