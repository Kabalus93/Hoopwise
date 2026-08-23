import SwiftUI

/// THE ONLY TIME RULER v2 HAS.
///
/// The keyframe editor's timeline was a coordinate system you authored in:
/// lanes, keyframes, a work area, snapping. Nothing here is authorable —
/// timing is derived from distance and pace, and there is no number in this
/// model a coach can type. So the bar does exactly two things: it says where
/// you are in the play, and it lets you get somewhere else.
///
/// The ticks are FRAME BOUNDARIES. They are the play's structure, the thing the
/// coach recognises ("that's the entry, that's the flare"), and they make
/// scrubbing land on a moment rather than a millisecond.
struct FrameScrubBar: View {
    @ObservedObject var model: FrameEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .help(model.isRunning ? "Pause (Space)" : "Play (Space)")

            track

            Text(clock)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Done") { model.exitPlayback() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Back to authoring (Esc) — lands on the frame you are watching")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var clock: String {
        String(format: "%.1f / %.1fs", model.playhead, model.playbackDuration)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let duration = max(model.playbackDuration, 0.0001)
            let progress = min(max(model.playhead / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: barHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * progress, height: barHeight)
                // Frame boundaries, subtle: structure you can see without it
                // competing with where you are.
                ForEach(Array(model.frameBoundaries.enumerated()), id: \.offset) { _, start in
                    Rectangle()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 1, height: barHeight + 5)
                        .offset(x: width * CGFloat(start / duration))
                }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, width * progress - 5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .frame(height: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Scrubbing PAUSES. A clock still running under the
                        // finger fights it, and every frame the coach lands on
                        // slides away before they have read it.
                        model.pausePlayback()
                        let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                        model.playhead = duration * Double(fraction)
                    }
            )
        }
        .frame(height: 20)
    }
}
