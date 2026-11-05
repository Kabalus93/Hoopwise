import SwiftData
import SwiftUI

/// Draw one step: drag players and defenders, draw cuts, dribbles, passes
/// and screens from a player, add defenders and the one to read, give the
/// ball, erase. Undo and redo; nothing is saved until Done.
struct JournalPlayStepEditor: View {
    let step: JournalPlayStep
    let court: JournalCourtKind
    let number: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var diagram: JournalPlayDiagram
    @State private var caption: String
    @State private var text: String
    @State private var tool: Tool = .move
    @State private var undoStack: [JournalPlayDiagram] = []
    @State private var redoStack: [JournalPlayDiagram] = []
    @State private var drag: Drag?
    @State private var confirmingDiscard = false

    enum Tool: String, CaseIterable, Identifiable {
        case move, cut, dribble, pass, screen, defender, ball, erase
        var id: String { rawValue }

        var label: JPString {
            switch self {
            case .move: "Move"
            case .cut: "Cut"
            case .dribble: "legend.dribble"
            case .pass: "Pass"
            case .screen: "Screen"
            case .defender: "Defender"
            case .ball: "Ball"
            case .erase: "Erase"
            }
        }

        var hint: JPString {
            switch self {
            case .move: "Drag a player, a defender or the end of a line."
            case .cut: "Drag from a player to where they run."
            case .dribble: "Drag from the ball handler to where they dribble."
            case .pass: "Drag from the passer to a teammate."
            case .screen: "Drag from a player to where they set the screen."
            case .defender: "Tap the court to add a defender; tap one to mark the one to read."
            case .ball: "Tap the player who has the ball when the step starts."
            case .erase: "Tap a line, a defender or a note to erase it."
            }
        }

        var lineKind: JournalPlayDiagram.ActionKind? {
            switch self {
            case .cut: .cut
            case .dribble: .dribble
            case .pass: .pass
            case .screen: .screen
            default: nil
            }
        }
    }

    /// What the finger is doing.
    private enum Drag {
        case player(Int)
        case defender(Int)
        case actionEnd(Int)
        case line(player: Int, points: [JournalCourtPoint])
        case tap
    }

    init(step: JournalPlayStep, court: JournalCourtKind, number: Int) {
        self.step = step
        self.court = court
        self.number = number
        _diagram = State(initialValue: step.diagram)
        _caption = State(initialValue: step.caption)
        _text = State(initialValue: step.text)
    }

    private var changed: Bool {
        diagram != step.diagram || caption != step.caption || text != step.text
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: JSpacing.s) {
                TextField(text: $caption) { JText("Caption, like “Set” or “The read”") }
                    .font(.headline)
                    .submitLabel(.done)
                    .padding(.horizontal, JSpacing.m)
                    .frame(minHeight: JTouchTarget.standard)
                    .background(JPalette.card, in: .rect(cornerRadius: JRadius.tile))
                canvas
                    .frame(maxHeight: .infinity, alignment: .top)
                tools
                JText(tool.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField(text: $text, axis: .vertical) { JText("What happens, and what to read") }
                    .lineLimit(2...5)
                    .padding(JSpacing.s)
                    .frame(minHeight: JTouchTarget.standard)
                    .background(JPalette.card, in: .rect(cornerRadius: JRadius.tile))
            }
            .padding(.horizontal, JSpacing.screen)
            .padding(.bottom, JSpacing.s)
            .background(JPalette.background)
            .navigationTitle(JText("Step \(number)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { changed ? confirmingDiscard = true : dismiss() } label: { JText("Cancel") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: undo) {
                        Label { JText("Undo") } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                    .disabled(undoStack.isEmpty)
                    Button(action: redo) {
                        Label { JText("Redo") } icon: { Image(systemName: "arrow.uturn.forward") }
                    }
                    .disabled(redoStack.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { JText("Done") }
                }
            }
            .confirmationDialog(JText("Discard your changes to this step?"), isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button(role: .destructive) { dismiss() } label: { JText("Discard changes") }
            }
        }
        .interactiveDismissDisabled(changed)
    }

    // MARK: - Canvas

    private var canvas: some View {
        JournalPlayDiagramView(diagram: shown, court: court)
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(.rect)
                        .gesture(gesture(size: proxy.size))
                }
            }
            .padding(JSpacing.xs)
            .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
            .overlay(RoundedRectangle(cornerRadius: JRadius.tile).strokeBorder(JPalette.courtLine, lineWidth: 0.5))
            .accessibilityElement()
            .accessibilityLabel(JText("Drawing of step \(number)"))
            .accessibilityHint(JText(tool.hint))
    }

    /// The drawing with the line being drawn.
    private var shown: JournalPlayDiagram {
        guard case .line(let player, let points)? = drag, points.count >= 2, let kind = tool.lineKind else {
            return diagram
        }
        var out = diagram
        let path = kind == .pass ? [points[0], points[points.count - 1]] : points
        out.actions.append(.init(kind: kind, player: player, path: path))
        return out
    }

    private func gesture(size: CGSize) -> some Gesture {
        let s = JournalPlayCourt.scale(court, width: size.width)
        func metres(_ p: CGPoint) -> JournalCourtPoint {
            JournalCourtPoint(p.x / s - JournalPlayCourt.margin, p.y / s - JournalPlayCourt.margin)
        }
        // A finger's reach: a player's circle, at least 22 pt.
        let radius = max(JournalPlayCourt.playerRadius * max(1, 17 / s) * 1.3, 22 / s)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil { drag = begin(at: metres(value.startLocation), radius: radius) }
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 4 else { return }
                update(to: metres(value.location))
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                finish(at: metres(value.location), isTap: distance <= 8, radius: radius)
                drag = nil
            }
    }

    private func begin(at point: JournalCourtPoint, radius: Double) -> Drag {
        if tool == .move {
            switch JournalPlayMath.hit(point, in: diagram, radius: radius) {
            case .player(let n): pushUndo(); return .player(n)
            case .defender(let i): pushUndo(); return .defender(i)
            case .actionEnd(let i): pushUndo(); return .actionEnd(i)
            default: return .tap
            }
        }
        if tool.lineKind != nil, let start = JournalPlayMath.lineStart(at: point, in: diagram, radius: radius) {
            return .line(player: start.player, points: [start.from])
        }
        return .tap
    }

    private func update(to point: JournalCourtPoint) {
        switch drag {
        case .player(let n): diagram = JournalPlayMath.moving(player: n, to: point, in: diagram)
        case .defender(let i): if diagram.defense.indices.contains(i) { diagram.defense[i].at = point }
        case .actionEnd(let i): diagram = JournalPlayMath.moving(endOf: i, to: point, in: diagram)
        case .line(let player, var points):
            if let last = points.last, last.distance(to: point) > 0.15 {
                points.append(point)
                drag = .line(player: player, points: points)
            }
        case .tap, nil: break
        }
    }

    private func finish(at point: JournalCourtPoint, isTap: Bool, radius: Double) {
        switch drag {
        case .line(let player, let points):
            if let kind = tool.lineKind,
               let added = JournalPlayMath.adding(kind, by: player, along: points + [point], to: diagram, radius: radius) {
                pushUndo()
                diagram = added
            }
        case .player, .defender, .actionEnd:
            // A touch that didn't move changes nothing.
            if isTap, let previous = undoStack.popLast() { diagram = previous }
        case .tap, nil:
            guard isTap else { return }
            tap(at: point, radius: radius)
        }
    }

    private func tap(at point: JournalCourtPoint, radius: Double) {
        let hit = JournalPlayMath.hit(point, in: diagram, radius: radius)
        switch tool {
        case .defender:
            pushUndo()
            if case .defender(let i)? = hit {
                diagram.defense[i].isRead.toggle()
            } else {
                diagram.defense.append(.init(at: point))
            }
        case .ball:
            guard case .player(let n)? = hit else { return }
            pushUndo()
            diagram.ball = diagram.ball == n ? nil : n
        case .erase:
            guard let hit else { return }
            if case .player = hit { return }
            pushUndo()
            diagram = JournalPlayMath.erasing(hit, in: diagram)
        default:
            break
        }
    }

    // MARK: - Tools

    /// Two rows of four, all in reach: 44 pt high, icon and name.
    private var tools: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: JSpacing.xxs), count: 4)
        return LazyVGrid(columns: columns, spacing: JSpacing.xxs) {
            ForEach(Tool.allCases) { item in
                Button {
                    tool = item
                } label: {
                    HStack(spacing: 2) {
                        icon(item)
                            .frame(width: 24, height: 20)
                        JText(item.label)
                            .font(.caption.weight(tool == item ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, JSpacing.xxs)
                    .frame(maxWidth: .infinity, minHeight: JTouchTarget.standard)
                    .background(tool == item ? JPalette.fill : .clear, in: .rect(cornerRadius: JRadius.tile - 2))
                    .overlay {
                        if tool == item {
                            RoundedRectangle(cornerRadius: JRadius.tile - 2).strokeBorder(JPalette.ink, lineWidth: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
        }
    }

    private static let iconLine = [JournalCourtPoint(-0.8, 1), JournalCourtPoint(2.8, 1)]

    @ViewBuilder
    private func icon(_ tool: Tool) -> some View {
        let line = Self.iconLine
        switch tool {
        case .move: Image(systemName: "hand.point.up.left").font(.body)
        case .cut: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .cut, player: 0, path: line)]))
        case .dribble: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .dribble, player: 0, path: line)]))
        case .pass: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .pass, player: 0, path: line)]))
        case .screen: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .screen, player: 0, path: [JournalCourtPoint(-0.8, 1), JournalCourtPoint(2.4, 1)])]))
        case .defender: JournalPlayMark(diagram: JournalPlayDiagram(defense: [.init(at: JournalCourtPoint(1, 1))]))
        case .ball: Image(systemName: "basketball").font(.body).foregroundStyle(JCategory.court.iconColor)
        case .erase: Image(systemName: "eraser").font(.body)
        }
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(diagram)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(diagram)
        diagram = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(diagram)
        diagram = next
    }

    private func save() {
        step.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        step.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        step.diagram = diagram
        try? context.save()
        dismiss()
    }
}
