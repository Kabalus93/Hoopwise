import SwiftUI

/// A horizontal number wheel — a ruler of numbers that snaps to the one in
/// the middle, a haptic tick per number (21 Nov 2026, Luther: "a scrolling
/// wheel would be elegant and practical"). Tap a number to jump to it.
/// VoiceOver: swipe up / down to adjust.
struct NumberWheel: View {
    let range: ClosedRange<Int>
    @Binding var value: Int
    var tint: Color = .orange
    var itemWidth: CGFloat = 52
    /// Prefix for each number's identifier (UI tests): "<id>.<n>".
    var identifier: String = "wheel"

    @State private var position: Int?

    var body: some View {
        GeometryReader { geo in
            let margin = max(0, (geo.size.width - itemWidth) / 2)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { n in
                        Button {
                            withAnimation(.snappy) { position = n }
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: itemWidth, height: 64)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.62)
                                .opacity(phase.isIdentity ? 1 : 0.35)
                        }
                        .accessibilityIdentifier("\(identifier).\(n)")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
            .overlay {
                // The reading window.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint, lineWidth: 2.5)
                    .frame(width: itemWidth + 6, height: 60)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                    .offset(y: -2)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 68)
        .onAppear { position = value }
        .onChange(of: value) { _, v in if position != v { withAnimation(.snappy) { position = v } } }
        .onChange(of: position) { _, p in if let p, p != value { value = p } }
        .sensoryFeedback(.selection, trigger: position)
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
}
