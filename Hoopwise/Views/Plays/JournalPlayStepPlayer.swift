import SwiftUI
import PencilKit

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
    /// The Coach board plays IN PLACE (17 Nov 2026, Luther: "should not open
    /// a new popup window for replay but play right there"): `bare` draws the
    /// court alone — no card, caption, ‹ ▶ › or step text; the board's own
    /// bar drives it through `scribbling`, `playToken` (each change toggles
    /// play / stop) and hears back through `onPlayingChange`.
    var bare = false
    var scribbling: Bool? = nil
    var playToken = 0
    var onPlayingChange: ((Bool) -> Void)? = nil
    /// Shown before the caption (the play page puts "Concept" there).
    @ViewBuilder var leading: () -> Leading

    @State private var playing = false
    @State private var stepStart = Date.now
    @State private var playback: Task<Void, Never>?
    /// The index playback last moved to, to tell its own moves from the host's.
    @State private var playedIndex: Int?
    @State private var frozen: Double?
    /// Pencil ink per step, while the page is open (PlayInkLayer).
    @State private var ink: [Int: PKDrawing] = [:]
    /// Scribble mode: what is drawn from a player is read as a cut, pass,
    /// screen or dribble and played (JournalPlayScribble).
    @State private var scribbleOn = false
    /// What scribble made of each step.
    @State private var scribbles: [Int: ScribbleRun] = [:]
    /// The ink canvas's size, to turn its points into court metres.
    @State private var inkSize: CGSize = .zero
    /// Reads the ink once the Pencil has rested two seconds.
    @State private var scribbleRead: Task<Void, Never>?
    /// Moves the players for what was just read, or replays it all.
    @State private var scribbleMotion: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: Step? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        SwiftUI.Group {
            if bare {
                pager
            } else {
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
            }
        }
        .onChange(of: playToken) { _, _ in if playing { stop() } else { play() } }
        .onChange(of: playing) { _, now in onPlayingChange?(now) }
        .onChange(of: scribbling) { _, on in if let on, on != scribbleOn { setScribble(on) } }
        .onAppear {
            frozen = frozenT
            if let scribbling, scribbling != scribbleOn { setScribble(scribbling) }
            if autoplay, frozen == nil, steps.count > 0 { play() }
            #if DEBUG
            scribbleDemo()
            #endif
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
                    .overlay {
                        PlayInkLayer(drawing: inkBinding(i))
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { inkSize = $0 }
                    }
                    .padding(JSpacing.xs)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(JournalPlayCourt.aspectRatio(court), contentMode: .fit)
        .frame(maxWidth: maxCourtWidth)
        .frame(maxWidth: .infinity)
        .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
        .overlay(alignment: .topTrailing) { clearInkButton }
        .overlay(alignment: .topLeading) { scribbleButton }
        .overlay(alignment: .bottom) { scribbleHint }
        .accessibilityElement(children: .contain)
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

    private func inkBinding(_ i: Int) -> Binding<PKDrawing> {
        Binding(get: { ink[i] ?? PKDrawing() }, set: { drawing in
            ink[i] = drawing
            if scribbleOn, i == index { scheduleScribbleRead() }
        })
    }

    private var hasInkOrScribble: Bool {
        !(ink[index]?.strokes.isEmpty ?? true) || !(scribbles[index]?.batches.isEmpty ?? true)
    }

    /// Shown once the Pencil has marked up this step; in scribble mode it
    /// also puts the players back where the step starts.
    @ViewBuilder
    private var clearInkButton: some View {
        if hasInkOrScribble {
            Button {
                withAnimation(JMotion.expand) { resetInk() }
            } label: {
                Label { scribbleOn ? JText("Reset ink") : JText("Clear ink") } icon: { Image(systemName: "eraser") }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, JSpacing.s)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glass)
            .padding(JSpacing.s)
            .accessibilityIdentifier("plays.player.clearInk")
        }
    }

    /// Scribble needs a Pencil: an iPad, not the Mac.
    private var offersScribble: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    @ViewBuilder
    private var scribbleButton: some View {
        if offersScribble && !bare {
            Button {
                withAnimation(JMotion.expand) { setScribble(!scribbleOn) }
            } label: {
                Label { JText("Scribble") } icon: { Image(systemName: "scribble.variable") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scribbleOn ? JPalette.background : JPalette.ink)
                    .padding(.horizontal, JSpacing.s)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(scribbleOn ? JPalette.play : Color.clear)
            .padding(JSpacing.s)
            .accessibilityIdentifier("plays.player.scribble")
            .accessibilityAddTraits(scribbleOn ? .isSelected : [])
        }
    }

    /// How to scribble, until something has been read on this step.
    @ViewBuilder
    private var scribbleHint: some View {
        if scribbleOn, scribbles[index]?.batches.isEmpty ?? true {
            JText("Draw from a player: arrow = cut, dashes = pass, bar = screen, zigzag = dribble")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, JSpacing.s)
                .padding(.vertical, 6)
                .filmGlass(.regular, in: .capsule)
                .padding(JSpacing.s)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func diagram(_ step: Step, isCurrent: Bool) -> some View {
        if isCurrent, scribbleOn {
            scribbleDiagram(step)
        } else if isCurrent, let frozen {
            JournalPlayDiagramView(diagram: step.diagram, court: court, frame: JournalPlayMath.frame(step.diagram, at: frozen, court: court))
        } else if isCurrent, playing, !reduceMotion {
            let diagram = step.diagram
            let duration = Self.duration(diagram)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(stepStart) / duration
                JournalPlayDiagramView(diagram: diagram, court: court, frame: JournalPlayMath.frame(diagram, at: t, court: court))
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
        if scribbleOn {
            replayScribble()
            return
        }
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
        if scribbleOn, scribbleMotion != nil {
            scribbleMotion?.cancel()
            scribbleMotion = nil
            if var run = scribbles[index], !run.batches.isEmpty {
                run.shown = run.batches.count - 1
                run.phase = .done
                scribbles[index] = run
            }
        }
    }
}

// MARK: - Scribble

#if DEBUG
extension JournalPlayStepPlayer {
    /// HOOPWISE_PLAYS_SCRIBBLE=1 opens in scribble mode; =demo also draws, as
    /// Pencil strokes, a cut with an arrowhead from one player and dashes from
    /// the ball handler to another, then lets them be read (2 s later); =ink
    /// draws them and stops before reading (a screenshot of the ink).
    func scribbleDemo() {
        guard let mode = ProcessInfo.processInfo.environment["HOOPWISE_PLAYS_SCRIBBLE"] else { return }
        scribbleOn = true
        guard mode == "demo" || mode == "ink" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard steps.indices.contains(index), inkSize.width > 0 else { return }
            let base = formation(steps[index])
            guard let holder = base.ball ?? base.offense.first?.number,
                  let from = base.player(holder)?.at,
                  let receiver = base.offense.first(where: { $0.number != holder }),
                  let cutter = base.offense.last(where: { $0.number != holder && $0.number != receiver.number }),
                  let rim = court.baskets.first else { return }
            let scale = JournalPlayCourt.scale(court, width: inkSize.width)
            func view(_ p: JournalCourtPoint) -> CGPoint { JournalPlayCourt.point(p, scale: scale, court: court) }
            var strokes: [[JournalCourtPoint]] = []
            // The cut: toward the rim, stopping 1.5 m short, with a V.
            let goal = JournalCourtPoint(rim.x + (cutter.at.x - rim.x) * 0.25, rim.y + 1.5)
            strokes.append(Self.demoLine(cutter.at, goal))
            let u = Self.demoUnit(cutter.at, goal)
            for turn in [0.5, -0.5] {
                let back = JournalCourtPoint(goal.x - 0.5 * (u.x * cos(turn) - u.y * sin(turn)),
                                             goal.y - 0.5 * (u.x * sin(turn) + u.y * cos(turn)))
                strokes.append(Self.demoLine(goal, back))
            }
            // The pass: dashes from the handler to the receiver.
            let length = from.distance(to: receiver.at)
            let v = Self.demoUnit(from, receiver.at)
            var s = 0.4
            while s + 0.5 < length - 0.4 {
                strokes.append(Self.demoLine(JournalCourtPoint(from.x + v.x * s, from.y + v.y * s),
                                             JournalCourtPoint(from.x + v.x * (s + 0.5), from.y + v.y * (s + 0.5))))
                s += 0.95
            }
            let ink = PKInkingTool(.pen, color: .systemRed, width: 5).ink
            let made = strokes.enumerated().map { k, line in
                PKStroke(ink: ink, path: PKStrokePath(
                    controlPoints: line.enumerated().map { j, p in
                        PKStrokePoint(location: view(p), timeOffset: Double(j) * 0.01, size: CGSize(width: 5, height: 5),
                                      opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    },
                    creationDate: Date(timeIntervalSinceNow: Double(k) * 0.01)))
            }
            self.ink[index] = PKDrawing(strokes: made)
            if mode == "demo" { scheduleScribbleRead() }
        }
    }

    static func demoLine(_ a: JournalCourtPoint, _ b: JournalCourtPoint) -> [JournalCourtPoint] {
        (0...12).map { k in
            let t = Double(k) / 12
            return JournalCourtPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
        }
    }

    static func demoUnit(_ a: JournalCourtPoint, _ b: JournalCourtPoint) -> JournalCourtPoint {
        let d = a.distance(to: b)
        return JournalCourtPoint((b.x - a.x) / d, (b.y - a.y) / d)
    }
}
#endif

extension JournalPlayStepPlayer {
    /// What scribble made of one step: each reading of the ink is a BATCH
    /// that starts where the one before left everyone.
    struct ScribbleRun {
        enum Phase: Equatable { case still, moving(Date), done }
        var batches: [JournalPlayDiagram] = []
        /// The batch on the court.
        var shown = 0
        var phase: Phase = .still
        /// Strokes already read (their creation dates), kept or used.
        var seen: Set<Date> = []
    }

    /// The step's players and ball where it starts, nothing drawn.
    func formation(_ step: Step) -> JournalPlayDiagram {
        var diagram = step.diagram
        diagram.actions = []
        diagram.notes = []
        return diagram
    }

    @ViewBuilder
    func scribbleDiagram(_ step: Step) -> some View {
        let run = scribbles[index] ?? ScribbleRun()
        if run.batches.indices.contains(run.shown) {
            let batch = run.batches[run.shown]
            switch run.phase {
            case .still:
                JournalPlayDiagramView(diagram: batch, court: court)
            case .moving(let since):
                let duration = Self.duration(batch)
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(since) / duration
                    JournalPlayDiagramView(diagram: batch, court: court, frame: JournalPlayMath.frame(batch, at: t, court: court))
                }
            case .done:
                JournalPlayDiagramView(diagram: batch, court: court, frame: JournalPlayMath.frame(batch, at: 1, court: court))
            }
        } else {
            JournalPlayDiagramView(diagram: formation(step), court: court)
        }
    }

    func setScribble(_ on: Bool) {
        stop()
        scribbleRead?.cancel()
        scribbleMotion?.cancel()
        scribbleMotion = nil
        if !on { scribbles = [:] }
        scribbleOn = on
    }

    func resetInk() {
        scribbleRead?.cancel()
        scribbleMotion?.cancel()
        scribbleMotion = nil
        ink[index] = nil
        scribbles[index] = nil
    }

    /// Two seconds after the Pencil last touched the court, read the ink
    /// (Luther: "move after I lift the pencil and don't write again for 2
    /// seconds").
    func scheduleScribbleRead() {
        scribbleRead?.cancel()
        let step = index
        scribbleRead = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, step == index, scribbleOn else { return }
            readScribble()
        }
    }

    /// The new strokes become actions: the ones read leave the ink (the
    /// clean line shows what was understood), the rest stay red. Then the
    /// players move.
    func readScribble() {
        guard steps.indices.contains(index), inkSize.width > 0, var drawing = ink[index] else { return }
        var run = scribbles[index] ?? ScribbleRun()
        let fresh = drawing.strokes.enumerated().filter { !run.seen.contains($0.element.path.creationDate) }
        guard !fresh.isEmpty else { return }
        let scale = JournalPlayCourt.scale(court, width: inkSize.width)
        let points: [[JournalCourtPoint]] = fresh.map { item in
            item.element.path.interpolatedPoints(by: .distance(3)).map { point in
                let p = point.location.applying(item.element.transform)
                return JournalPlayCourt.courtPoint(p, scale: scale, court: court)
            }
        }
        let base = run.batches.last.map { JournalPlayMath.startOfNextStep(after: $0, court: court) }
            ?? formation(steps[index])
        let result = JournalPlayScribble.read(points, on: base, court: court)
        for item in fresh { run.seen.insert(item.element.path.creationDate) }
        guard !result.diagram.actions.isEmpty else {
            scribbles[index] = run
            return
        }
        let usedStrokes = Set(result.used.map { fresh[$0].offset })
        drawing.strokes = drawing.strokes.enumerated().filter { !usedStrokes.contains($0.offset) }.map(\.element)
        ink[index] = drawing
        run.batches.append(result.diagram)
        run.shown = run.batches.count - 1
        run.phase = .still
        scribbles[index] = run
        moveScribble(batch: run.shown, pause: 0.6)
    }

    /// The clean lines for a moment, then the players move along them.
    func moveScribble(batch: Int, pause: Double) {
        scribbleMotion?.cancel()
        let step = index
        scribbleMotion = Task { @MainActor in
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled, step == index, var run = scribbles[step], run.batches.indices.contains(batch) else { return }
            run.shown = batch
            run.phase = .moving(.now)
            scribbles[step] = run
            try? await Task.sleep(for: .seconds(Self.duration(run.batches[batch])))
            guard !Task.isCancelled, step == index, var after = scribbles[step] else { return }
            after.phase = .done
            scribbles[step] = after
            scribbleMotion = nil
        }
    }

    /// ▶ in scribble mode: everything scribbled on this step, from the start.
    func replayScribble() {
        guard let run = scribbles[index], !run.batches.isEmpty else { return }
        scribbleMotion?.cancel()
        let step = index
        playing = true
        scribbleMotion = Task { @MainActor in
            for batch in run.batches.indices {
                guard !Task.isCancelled, step == index, var now = scribbles[step] else { break }
                now.shown = batch
                now.phase = .moving(.now)
                scribbles[step] = now
                try? await Task.sleep(for: .seconds(Self.duration(run.batches[batch]) + 0.3))
            }
            if !Task.isCancelled, var end = scribbles[step] {
                end.shown = end.batches.count - 1
                end.phase = .done
                scribbles[step] = end
            }
            playing = false
            scribbleMotion = nil
        }
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
