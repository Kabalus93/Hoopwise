import SwiftUI

/// A part played step by step: the caption and "Step 1 of 3", the diagram
/// (swipe between steps), ‹ ▶ › under it, and the step's text in a card
/// below. Shared by the play page (the concept, playable in place — Luther,
/// November 2026: the hero's ▶ used to open a second screen where ▶ then
/// played) and the step screen of every part.
///
/// A drill's drawing plays the same way (`init(steps:court:…)`, November
/// 2026): its steps are values rather than a part's records.
///
/// The host owns which step is shown (`index`) so its toolbar can draw,
/// add, move or delete that step; playback stops whenever the host moves
/// the index itself or `paused` turns on (an editor or dialog open).
struct JournalPlayStepPlayer<Leading: View>: View {
    /// One step as the player shows it.
    struct Step {
        var diagram: JournalPlayDiagram
        var caption: String
        var text: String
    }

    let steps: [Step]
    let court: JournalCourtKind
    @Binding var index: Int
    var paused = false
    /// Start playing as soon as the player appears.
    var autoplay = false
    /// DEBUG: a frozen moment of the playback, for screenshots.
    var frozenT: Double?
    /// The height of the window the player sits in: the court is kept small
    /// enough that it, its caption and ‹ ▶ › fit without scrolling (Luther,
    /// November 2026: in a wide Mac window the half court ran off the bottom).
    var viewportHeight: CGFloat?
    /// Shown before the caption (the play page puts "Concept" there).
    @ViewBuilder var leading: () -> Leading

    @State private var playing = false
    @State private var stepStart = Date.now
    @State private var playback: Task<Void, Never>?
    /// The index playback last moved to, to tell its own moves from the host's.
    @State private var playedIndex: Int?
    @State private var frozen: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: Step? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: JSpacing.m) {
            JCard(verticalPadding: JSpacing.s) {
                VStack(alignment: .leading, spacing: JSpacing.s) {
                    header
                    pager
                    controls
                }
            }
            stepText
        }
        .onAppear {
            frozen = frozenT
            if autoplay, frozen == nil, steps.count > 0 { play() }
        }
        .onDisappear(perform: stop)
        .onChange(of: paused) { _, isPaused in if isPaused { stop() } }
        .onChange(of: index) { _, newIndex in
            if playing, newIndex != playedIndex { stop() }
        }
    }

    // MARK: - Diagram

    /// Room for the card's caption row, ‹ ▶ › and paddings, and the floating
    /// tab bar over the bottom of the window.
    private static var chrome: CGFloat { 250 }

    /// The widest the court may be so its height fits the window.
    private var maxCourtWidth: CGFloat {
        guard let viewportHeight else { return .infinity }
        let height = max(240, viewportHeight - Self.chrome)
        return height * JournalPlayCourt.aspectRatio(court)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: JSpacing.xs) {
            leading()
            Text(verbatim: current?.caption ?? "")
                .font(.headline)
            Spacer(minLength: JSpacing.xs)
            JText("Step \(index + 1) of \(steps.count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                diagram(step, isCurrent: i == index)
                    .padding(JSpacing.xs)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(JournalPlayCourt.aspectRatio(court), contentMode: .fit)
        .frame(maxWidth: maxCourtWidth)
        .frame(maxWidth: .infinity)
        .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: current?.caption ?? ""))
        .accessibilityValue(JText("Step \(index + 1) of \(steps.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: index + 1)
            case .decrement: go(to: index - 1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func diagram(_ step: Step, isCurrent: Bool) -> some View {
        if isCurrent, let frozen {
            JournalPlayDiagramView(diagram: step.diagram, court: court, frame: JournalPlayMath.frame(step.diagram, at: frozen))
        } else if isCurrent, playing, !reduceMotion {
            let diagram = step.diagram
            let duration = Self.duration(diagram)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(stepStart) / duration
                JournalPlayDiagramView(diagram: diagram, court: court, frame: JournalPlayMath.frame(diagram, at: t))
            }
        } else {
            JournalPlayDiagramView(diagram: step.diagram, court: court)
        }
    }

    private var controls: some View {
        HStack(spacing: JSpacing.s) {
            stepButton("chevron.left", label: "Previous step", enabled: index > 0) { go(to: index - 1) }
            Spacer(minLength: 0)
            Button {
                playing ? stop() : play()
            } label: {
                Label {
                    playing ? JText("Pause") : JText("Play")
                } icon: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(JPalette.background)
                .padding(.horizontal, JSpacing.l)
                .frame(minHeight: JTouchTarget.standard)
            }
            .buttonStyle(.glassProminent)
            .tint(JPalette.ink)
            .accessibilityIdentifier("plays.player.play")
            Spacer(minLength: 0)
            stepButton("chevron.right", label: "Next step", enabled: index < steps.count - 1) { go(to: index + 1) }
        }
    }

    private func stepButton(_ symbol: String, label: JPString, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { JText(label) } icon: { Image(systemName: symbol) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: JTouchTarget.standard, height: JTouchTarget.standard)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var stepText: some View {
        if let text = current?.text, !text.isEmpty {
            JCard {
                Text(verbatim: text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
            }
        }
    }

    // MARK: - Playback

    /// Seconds a step plays: 1.2 s a beat (`JournalPlayMath.playBeats`).
    private static func duration(_ diagram: JournalPlayDiagram) -> Double {
        max(1.2, 1.2 * JournalPlayMath.playBeats(diagram))
    }

    private func go(to newIndex: Int) {
        stop()
        guard steps.indices.contains(newIndex) else { return }
        withAnimation(JMotion.expand) { index = newIndex }
    }

    /// From this step to the last; from the start when already on the last.
    private func play() {
        frozen = nil
        if index >= steps.count - 1 { setIndex(0) }
        playing = true
        playedIndex = index
        playback = Task { @MainActor in
            while !Task.isCancelled, steps.indices.contains(index) {
                stepStart = .now
                let hold = reduceMotion ? 2.4 : Self.duration(steps[index].diagram) + 0.8
                try? await Task.sleep(for: .seconds(hold))
                guard !Task.isCancelled else { return }
                guard index < steps.count - 1 else { break }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { setIndex(index + 1) }
            }
            playing = false
        }
    }

    private func setIndex(_ newIndex: Int) {
        playedIndex = newIndex
        index = newIndex
    }

    private func stop() {
        playback?.cancel()
        playback = nil
        playing = false
    }
}

extension JournalPlayStepPlayer {
    /// A play's part, its steps read from the store.
    init(part: JournalPlayPart, index: Binding<Int>, paused: Bool = false, autoplay: Bool = false,
         frozenT: Double? = nil, viewportHeight: CGFloat? = nil, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(steps: part.sortedSteps.map { Step(diagram: $0.diagram, caption: $0.caption, text: $0.text) },
                  court: part.play?.court ?? .half, index: index, paused: paused, autoplay: autoplay,
                  frozenT: frozenT, viewportHeight: viewportHeight, leading: leading)
    }
}

extension JournalPlayStepPlayer where Leading == EmptyView {
    init(part: JournalPlayPart, index: Binding<Int>, paused: Bool = false, autoplay: Bool = false,
         frozenT: Double? = nil, viewportHeight: CGFloat? = nil) {
        self.init(part: part, index: index, paused: paused, autoplay: autoplay, frozenT: frozenT,
                  viewportHeight: viewportHeight) { EmptyView() }
    }

    /// A drill's drawing.
    init(drawing: DrillDrawing, index: Binding<Int>, viewportHeight: CGFloat? = nil) {
        self.init(steps: drawing.steps.map { Step(diagram: $0.diagram, caption: $0.caption, text: $0.text) },
                  court: drawing.court, index: index, viewportHeight: viewportHeight) { EmptyView() }
    }
}
