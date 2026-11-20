import SwiftData
import SwiftUI
import PencilKit
import OSLog

/// Draw a part's steps: drag players and defenders, draw cuts, dribbles,
/// passes, shots and screens from a player, add defenders and the one to
/// read, give the ball, erase. Undo and redo per step. The step menu in the
/// title (and the workspace's Steps list) moves between the part's steps
/// and adds one — each step keeps its own draft (Luther, November 2026: edit
/// more than one step without pressing Done). Nothing is saved until Done;
/// Cancel discards every step's changes and any step added here.
///
/// Two layouts. Compact width (iPhone) is the Journal's: caption, court,
/// tool grid, notes. Regular width (iPad, and the Mac where most plays are
/// drawn — Luther, November 2026: "like Pixelmator Pro") is a workspace: a
/// vertical tool rail, the court as large as the window allows, and an
/// inspector for the step, the tool and the SELECTION (Move selects a
/// player, defender or line to edit), with keyboard shortcuts.
///
/// The same editor draws a DRILL's visual (`init(drawing:onSave:)`, Luther,
/// November 2026): steps as values handed back on Done, plus a Player tool
/// (any number of players; Erase removes one) and a Cone tool.
struct JournalPlayStepEditor: View {
    let court: JournalCourtKind
    /// The play part whose steps are drawn; nil for a drill's drawing.
    private let part: JournalPlayPart?
    /// A drill's drawing (November 2026, Luther: drill visuals use this
    /// editor): handed back on Done instead of written to a part. A drill
    /// also gets as many players as it wants (Player tool, erase removes
    /// one) and cones; a play keeps its five.
    private let onSaveDrill: ((DrillDrawing) -> Void)?
    private var isDrill: Bool { onSaveDrill != nil }
    /// The Coach board keeps every change as it happens (Luther, 17 Nov 2026:
    /// "I'd like to find it as is when I come back"), so leaving the editor
    /// any way — Cancel included, or the app going away — loses nothing.
    private let onDrawingChange: ((DrillDrawing) -> Void)?
    /// The Coach board's own controls (17 Nov 2026, Luther: "land directly in
    /// the editor in full screen with only the tool bar on the side and steps
    /// at the bottom left tucked into a button"). Present only on the board.
    /// Also a DRILL'S DRAWING (19 Nov 2026, Luther: "adding a drawing to a
    /// drill should use the general play editor like the one accessed in the
    /// hub"): the same layout with its own title, no Clear / Save menu, and
    /// Cancel + Done as before (`DrillDrawingEditor`).
    struct BoardActions {
        var title: JPString = "Coach board"
        var isBlank: Bool
        /// The court to change to, and the drawing as it stands now.
        var setCourt: (JournalCourtKind, DrillDrawing) -> Void
        var clear: (() -> Void)? = nil
        var saveAsPlay: (() -> Void)? = nil
        var saveAsDrill: (() -> Void)? = nil
        /// Edits made before the editor was rebuilt (a court change), so
        /// Cancel still asks before throwing them away.
        var edited: Bool = false
    }
    private let board: BoardActions?
    @State private var boardStepsOpen = false
    /// The board's Defense dock, open above its capsule (20 Nov 2026).
    @State private var defenseOpen = false
    /// The board's court plays in place: the step player replaces the
    /// editable court while it plays or while Scribble is on.
    @State private var boardPlayer = false
    @State private var boardAutoplay = false
    @State private var boardPlaying = false
    @State private var boardScribble = false
    @State private var boardPlayToken = 0

    /// Every step, in order, as values: the one on screen is `current`, and
    /// `diagram`, `caption`, `text` and the undo stacks are its working copy;
    /// the others keep their drafts here. Nothing touches the store until
    /// Done, so Cancel only has to drop them.
    @State private var pages: [Page]
    @State private var current: UUID
    /// Saved steps deleted in this editor: deleted on Done, back on Cancel.
    @State private var deleted: [Page] = []
    @State private var confirmingDeleteStep = false

    private struct Content: Equatable {
        var diagram: JournalPlayDiagram
        var caption: String
        var text: String
    }

    private struct Draft {
        var diagram: JournalPlayDiagram
        var caption: String
        var text: String
        var undo: [JournalPlayDiagram] = []
        var redo: [JournalPlayDiagram] = []

        var content: Content { Content(diagram: diagram, caption: caption, text: text) }
    }

    private struct Page: Identifiable {
        let id = UUID()
        /// The play step it edits; nil for a step added here, and in a drill.
        var model: JournalPlayStep?
        /// What it held when the editor opened; nil for a step added here.
        var saved: Content?
        var draft: Draft
    }

    private var currentIndex: Int { pages.firstIndex { $0.id == current } ?? 0 }
    private var number: Int { currentIndex + 1 }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var diagram: JournalPlayDiagram
    @State private var caption: String
    @State private var text: String
    @State private var tool: Tool = .move
    /// APPLE PENCIL (15 Nov 2026): once a Pencil touches the court, the
    /// Pencil draws with the tool and a finger moves / selects whatever the
    /// tool (`plays.pencilDraws`, on by default). `gestureTool` is the tool
    /// the touch in progress uses.
    @State private var pencilSeen = false
    @State private var gestureTool: Tool?
    @State private var previousTool: Tool = .move
    /// Where the Pencil (or the Mac pointer) hovers, in metres.
    @State private var hoverPoint: JournalCourtPoint?
    /// The tool palette a squeeze (or double-tap, per the system setting)
    /// opens at the Pencil tip, in the court's points.
    @State private var paletteAt: CGPoint?
    @AppStorage("plays.pencilDraws") private var pencilDraws = true
    /// ANNOTATIONS (19 Nov 2026, Luther): free ink over the court, drawn
    /// with the Annotate switch on; kept with the steps only when the coach
    /// chooses (device setting, off by default), else dropped on Done.
    @State private var annotating = false
    @AppStorage("plays.keepAnnotations") private var keepAnnotations = false
    @AppStorage("plays.annotate.pen") private var annotationPenRaw = AnnotationPen.pen.rawValue
    @AppStorage("plays.annotate.penColor") private var penColorRaw = AnnotationColor.red.rawValue
    @AppStorage("plays.annotate.highlighterColor") private var highlighterColorRaw = AnnotationColor.yellow.rawValue

    private var annotationPen: AnnotationPen { AnnotationPen(rawValue: annotationPenRaw) ?? .pen }
    private var annotationColor: AnnotationColor {
        let raw = annotationPen == .pen ? penColorRaw : highlighterColorRaw
        return AnnotationColor(rawValue: raw).flatMap { annotationPen.colors.contains($0) ? $0 : nil } ?? annotationPen.defaultColor
    }
    @State private var undoStack: [JournalPlayDiagram] = []
    @State private var redoStack: [JournalPlayDiagram] = []
    @State private var drag: Drag?
    /// Where the touch in progress began (points), for tap-versus-drag.
    @State private var dragStart: CGPoint?
    @State private var confirmingDiscard = false
    @State private var selection: Selection?
    /// The rail tool under the pointer: its name shows beside it.
    @State private var hoveredTool: Tool?
    /// The workspace's size: taller than wide (an iPad mini held upright, a
    /// narrow Mac window) puts the inspector UNDER the court, so the court
    /// keeps the whole width (Luther, November 2026).
    @State private var workspaceSize: CGSize = .zero
    /// The layout in force. It does not change while a text field is being
    /// typed in: the on-screen keyboard makes an upright window wider than
    /// tall, and switching then would take the field (and focus) away.
    @State private var inspectorBelow = false
    @FocusState private var focus: Field?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Field { case caption, notes }

    /// What the Move tool picked (regular width).
    enum Selection: Equatable {
        case player(Int)
        case defender(Int)
        case cone(Int)
        case action(Int)

        var hit: JournalPlayMath.PlayHit {
            switch self {
            case .player(let n): .player(n)
            case .defender(let i): .defender(i)
            case .cone(let i): .cone(i)
            case .action(let i): .action(i)
            }
        }
    }

    private var isWorkspace: Bool { sizeClass == .regular }
    /// The tool the current touch draws with (Move for a finger in Pencil
    /// mode), else the selected one.
    private var activeTool: Tool { gestureTool ?? tool }
    /// Single-key shortcuts only in the workspace, and never while typing.
    private var keysActive: Bool { isWorkspace && focus == nil }
    /// Straight or curved for new lines; remembered on this device.
    @AppStorage("plays.lineShape") private var lineShapeRaw = JournalPlayDiagram.PathShape.straight.rawValue

    private var lineShape: JournalPlayDiagram.PathShape {
        JournalPlayDiagram.PathShape(rawValue: lineShapeRaw) ?? .straight
    }

    enum Tool: String, CaseIterable, Identifiable {
        case move, cut, dribble, pass, handoff, shot, screen, player, defender, ball, cone, erase
        var id: String { rawValue }

        /// Player and Cone are a drill's: a play always has its five.
        static func available(drill: Bool) -> [Tool] {
            drill ? allCases : allCases.filter { $0 != .player && $0 != .cone }
        }

        var label: JPString {
            switch self {
            case .move: "Move"
            case .cut: "Cut"
            case .dribble: "legend.dribble"
            case .pass: "Pass"
            case .handoff: "Hand-off"
            case .shot: "Shot"
            case .screen: "Screen"
            case .player: "Player"
            case .defender: "Defender"
            case .ball: "Ball"
            case .cone: "Cone"
            case .erase: "Erase"
            }
        }

        /// The hint in a drill, where players can be added and removed.
        func hint(drill: Bool) -> JPString {
            guard drill else { return hint }
            switch self {
            case .erase: return "Tap a player, a line, a defender, a cone or a note to erase it."
            default: return hint
            }
        }

        var hint: JPString {
            switch self {
            case .move: "Drag a player, a defender, the end of a line or a bend. Tap a line to make it straight or curved."
            case .cut: "Drag from a player to where they run."
            case .dribble: "Drag from the ball handler to where they dribble."
            case .pass: "Drag from the passer to a teammate."
            case .handoff: "Drag from the ball handler to a teammate: from a distance he dribbles over and hands it off; next to him, a plain hand-off."
            case .shot: "Drag from the shooter toward the basket; the line ends in the rim."
            case .screen: "Drag from a player to where they set the screen."
            case .player: "Tap the court to add a player."
            case .defender: "Tap the court to add a defender; tap one to mark the one to read."
            case .ball: "Tap a player to give or take a ball. Several players can each have one."
            case .cone: "Tap the court to add a cone."
            case .erase: "Tap a line, a defender or a note to erase it."
            }
        }

        var lineKind: JournalPlayDiagram.ActionKind? {
            switch self {
            case .cut: .cut
            case .dribble: .dribble
            case .pass: .pass
            case .handoff: .handoff
            case .shot: .shot
            case .screen: .screen
            default: nil
            }
        }

        /// Lines that can run straight or curved (a pass is always straight).
        var shapesLine: Bool { self == .cut || self == .dribble || self == .screen || self == .handoff }

        /// The workspace's single-key shortcut (graphics-app convention:
        /// V for the pointer).
        var key: Character {
            switch self {
            case .move: "v"
            case .cut: "c"
            case .dribble: "d"
            case .pass: "p"
            case .handoff: "f"
            case .shot: "h"
            case .screen: "s"
            case .player: "o"
            case .defender: "x"
            case .ball: "b"
            case .cone: "k"
            case .erase: "e"
            }
        }

        /// The rail's groups: select | lines | marks | erase.
        static func railGroups(drill: Bool) -> [[Tool]] {
            [[.move], [.cut, .dribble, .pass, .handoff, .shot, .screen],
             drill ? [.player, .defender, .ball, .cone] : [.defender, .ball], [.erase]]
        }
    }

    /// What the finger is doing.
    private enum Drag {
        case player(Int)
        case defender(Int)
        case cone(Int)
        case actionEnd(Int)
        case bend(action: Int, point: Int)
        case line(player: Int, points: [JournalCourtPoint])
        case tap
    }

    /// Opens on `step`; its part's other steps are a menu away.
    init(step: JournalPlayStep, court: JournalCourtKind) {
        self.court = court
        part = step.part
        onSaveDrill = nil
        onDrawingChange = nil
        board = nil
        let models = step.part?.sortedSteps ?? [step]
        let pages = models.map { model in
            Page(model: model, saved: Content(diagram: model.diagram, caption: model.caption, text: model.text),
                 draft: Draft(diagram: model.diagram, caption: model.caption, text: model.text))
        }
        let first = pages.first { $0.model === step } ?? pages[0]
        _pages = State(initialValue: pages)
        _current = State(initialValue: first.id)
        _diagram = State(initialValue: first.draft.diagram)
        _caption = State(initialValue: first.draft.caption)
        _text = State(initialValue: first.draft.text)
    }

    /// A drill's drawing, opened on its first step; Done hands it back.
    init(drawing: DrillDrawing, onChange: ((DrillDrawing) -> Void)? = nil, board: BoardActions? = nil,
         onSave: @escaping (DrillDrawing) -> Void) {
        court = drawing.court
        part = nil
        onSaveDrill = onSave
        onDrawingChange = onChange
        self.board = board
        let steps = drawing.steps.isEmpty ? DrillDrawing.new(court: drawing.court).steps : drawing.steps
        let pages = steps.map { step in
            Page(saved: Content(diagram: step.diagram, caption: step.caption, text: step.text),
                 draft: Draft(diagram: step.diagram, caption: step.caption, text: step.text))
        }
        _pages = State(initialValue: pages)
        _current = State(initialValue: pages[0].id)
        _diagram = State(initialValue: pages[0].draft.diagram)
        _caption = State(initialValue: pages[0].draft.caption)
        _text = State(initialValue: pages[0].draft.text)
    }

    private var changed: Bool {
        if board?.edited == true { return true }
        if !deleted.isEmpty || pages.contains(where: { $0.saved == nil }) { return true }
        return pages.contains { page in
            let content = page.id == current ? Content(diagram: diagram, caption: caption, text: text) : page.draft.content
            return content != page.saved
        }
    }

    // MARK: - Steps

    /// The working copy goes back into its page.
    private func stash() {
        let i = currentIndex
        guard pages.indices.contains(i) else { return }
        pages[i].draft = Draft(diagram: diagram, caption: caption, text: text, undo: undoStack, redo: redoStack)
    }

    /// Another step on screen, with its draft.
    private func show(_ id: UUID) {
        guard id != current, let page = pages.first(where: { $0.id == id }) else { return }
        stash()
        current = id
        diagram = page.draft.diagram
        caption = page.draft.caption
        text = page.draft.text
        undoStack = page.draft.undo
        redoStack = page.draft.redo
        selection = nil
        drag = nil
        focus = nil
    }

    private func go(by offset: Int) {
        let i = currentIndex
        guard pages.indices.contains(i + offset) else { return }
        show(pages[i + offset].id)
    }

    /// A step after this one, starting where this one's DRAFT ends.
    private func addStep() {
        let new = Page(draft: Draft(diagram: JournalPlayMath.startOfNextStep(after: diagram, court: court), caption: "", text: ""))
        pages.insert(new, at: currentIndex + 1)
        show(new.id)
    }

    /// The step on screen goes; its neighbour (the next, else the one before)
    /// comes up. A saved step waits for Done, so Cancel brings it back. The
    /// last step stays.
    private func deleteStep() {
        let i = currentIndex
        guard pages.count > 1, pages.indices.contains(i) else { return }
        let gone = pages[i]
        show(pages.indices.contains(i + 1) ? pages[i + 1].id : pages[i - 1].id)
        pages.removeAll { $0.id == gone.id }
        if gone.saved != nil { deleted.append(gone) }
    }

    /// The step on screen trades places with its neighbour (-1 earlier, +1
    /// later). Done writes the new order.
    private func moveStep(by offset: Int) {
        let i = currentIndex
        guard pages.indices.contains(i), pages.indices.contains(i + offset) else { return }
        stash()
        pages.swapAt(i, i + offset)
    }

    /// The diagram a step shows in the Steps list: the working copy for the
    /// one on screen, else its draft.
    private func shownDiagram(_ page: Page) -> JournalPlayDiagram {
        page.id == current ? diagram : page.draft.diagram
    }

    private func caption(of page: Page) -> String {
        page.id == current ? caption : page.draft.caption
    }

    /// The title: "Step 2 of 3" opening a menu of the part's steps.
    private var stepMenu: some View {
        Menu {
            stepMenuItems
        } label: {
            HStack(spacing: 4) {
                JText("Step \(number) of \(pages.count)")
                    .font(.headline)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityIdentifier("plays.editor.steps")
    }

    /// Every step, then add / move / delete.
    @ViewBuilder
    private var stepMenuItems: some View {
            ForEach(Array(pages.enumerated()), id: \.element.id) { i, other in
                Button { show(other.id) } label: {
                    let name = caption(of: other)
                    if other.id == current {
                        Label { Text(verbatim: name.isEmpty ? jp("Step \(i + 1)") : "\(i + 1). \(name)") } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: name.isEmpty ? jp("Step \(i + 1)") : "\(i + 1). \(name)")
                    }
                }
            }
            Divider()
            Button(action: addStep) {
                Label { JText("Add a step after this one") } icon: { Image(systemName: "plus") }
            }
            if pages.count > 1 {
                Button { moveStep(by: -1) } label: {
                    Label { JText("Move step earlier") } icon: { Image(systemName: "arrow.up") }
                }
                .disabled(number <= 1)
                Button { moveStep(by: 1) } label: {
                    Label { JText("Move step later") } icon: { Image(systemName: "arrow.down") }
                }
                .disabled(number >= pages.count)
                Button(role: .destructive) { confirmingDeleteStep = true } label: {
                    Label { JText("Delete step") } icon: { Image(systemName: "trash") }
                }
            }
    }

    /// The phone's steps bar, under the caption: ‹ Step 2 of 3 › and ⋯ (the
    /// toolbar has no room for the title menu there — Luther, November 2026:
    /// on the iPhone steps could not be added, moved or deleted).
    private var compactStepsBar: some View {
        HStack(spacing: JSpacing.s) {
            Button { go(by: -1) } label: {
                Label { JText("Previous step") } icon: { Image(systemName: "chevron.left") }
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .disabled(number <= 1)
            Menu { stepMenuItems } label: {
                HStack(spacing: 4) {
                    JText("Step \(number) of \(pages.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 36)
            }
            .accessibilityIdentifier("plays.editor.steps")
            Button { go(by: 1) } label: {
                Label { JText("Next step") } icon: { Image(systemName: "chevron.right") }
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .disabled(number >= pages.count)
            Spacer(minLength: 0)
            Button(action: addStep) {
                Label { JText("Add a step") } icon: { Image(systemName: "plus") }
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("plays.editor.addStep")
        }
    }

    /// One step in the Steps list: its small drawing and caption.
    private func stepTile(_ i: Int, _ other: Page, vertical: Bool) -> some View {
        Button { show(other.id) } label: {
            SwiftUI.Group {
                if vertical {
                    VStack(alignment: .leading, spacing: 3) {
                        JournalPlayThumbnail(diagram: shownDiagram(other), court: court, width: 92, height: 66)
                        stepLabel(i, other)
                    }
                    .frame(width: 92, alignment: .leading)
                } else {
                    HStack(spacing: JSpacing.s) {
                        JournalPlayThumbnail(diagram: shownDiagram(other), court: court, width: 56, height: 44)
                        stepLabel(i, other)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(4)
            .background(other.id == current ? JPalette.fill : .clear, in: .rect(cornerRadius: 8))
            .overlay {
                if other.id == current { RoundedRectangle(cornerRadius: 8).strokeBorder(JPalette.ink, lineWidth: 1) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plays.editor.step.\(i + 1)")
    }

    private func stepLabel(_ i: Int, _ other: Page) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            JText("Step \(i + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: caption(of: other))
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    /// The side inspector's Steps: the same header as the filmstrip, the
    /// steps as rows, then "+ Add a step" as the list's last row.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: JSpacing.xs) {
            stepsHeader
            ForEach(Array(pages.enumerated()), id: \.element.id) { i, other in
                stepTile(i, other, vertical: false)
            }
            Button(action: addStep) {
                Label { JText("Add a step") } icon: { Image(systemName: "plus") }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("plays.editor.addStep")
        }
        .background { stepKeys }
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if isWorkspace { workspace } else { compactLayout }
            }
            .background(JPalette.background)
            #if DEBUG
            // HOOPWISE_PLAYS_DEFENSE=man|zone23|zone32 opens on the Defender
            // tool with that defense (screenshots, checks).
            .onAppear {
                if let raw = ProcessInfo.processInfo.environment["HOOPWISE_PLAYS_DEFENSE"],
                   let mode = JournalPlayDiagram.DefenseMode(rawValue: raw) {
                    tool = .defender
                    setDefense(mode)
                    // _BALL=<n>: 2 s later that player alone holds the ball.
                    if let n = ProcessInfo.processInfo.environment["HOOPWISE_PLAYS_DEFENSE_BALL"].flatMap(Int.init) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagram.balls = [n] }
                    }
                }
            }
            #endif
            #if DEBUG
            // HOOPWISE_BOARD_ANNOTATE=1: the board opens annotating.
            .onAppear {
                if board != nil, ProcessInfo.processInfo.environment["HOOPWISE_BOARD_ANNOTATE"] == "1" { annotating = true }
            }
            #endif
            // The Pencil's "previous tool" (double-tap) goes back to this.
            .onChange(of: tool) { old, _ in
                previousTool = old
                paletteAt = nil
                annotating = false
                // On the board, picking a tool goes back to drawing.
                if board != nil, boardPlayer {
                    boardScribble = false
                    boardPlayer = false
                }
            }
            // Auto defense: defenders follow every change to the offense.
            .onChange(of: diagram) { _, new in
                let placed = JournalPlayMath.placingDefense(new, court: court)
                #if DEBUG
                if new.defenseMode != nil {
                    Logger(subsystem: "hoopwise.mac", category: "defense").log(
                        "placed \(new.defenseMode?.rawValue ?? "-", privacy: .public) ball \(new.balls, privacy: .public) \(placed.defense.map { "(\(Int($0.at.x * 10)),\(Int($0.at.y * 10)))" }.joined(), privacy: .public)")
                }
                #endif
                if placed != new { diagram = placed }
            }
            .onChange(of: diagram) { _, _ in reportDrawing() }
            .onChange(of: caption) { _, _ in reportDrawing() }
            .onChange(of: text) { _, _ in reportDrawing() }
            .onChange(of: pages.map(\.id)) { _, _ in reportDrawing() }
            // The phone's steps bar says which step; the title would repeat it.
            .navigationTitle(isWorkspace ? JText("Step \(number)") : Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isWorkspace && board == nil {
                    ToolbarItem(placement: .principal) { stepMenu }
                }
                if let board {
                    ToolbarItem(placement: .principal) {
                        JText(board.title).font(.headline)
                    }
                    ToolbarItemGroup(placement: .topBarLeading) { boardControls(board) }
                }
                // The Coach board keeps every change as it is made, so there
                // is nothing to cancel there: Done alone closes it.
                if onDrawingChange == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        // Esc deselects first, then cancels (`shortcutKeys`).
                        Button { changed ? confirmingDiscard = true : dismiss() } label: { JText("Cancel") }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: undo) {
                        Label { JText("Undo") } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                    .disabled(undoStack.isEmpty)
                    .keyboardShortcut(keysActive ? KeyboardShortcut("z", modifiers: .command) : nil)
                    .help(jp("Undo") + " (⌘Z)")
                    Button(action: redo) {
                        Label { JText("Redo") } icon: { Image(systemName: "arrow.uturn.forward") }
                    }
                    .disabled(redoStack.isEmpty)
                    .keyboardShortcut(keysActive ? KeyboardShortcut("z", modifiers: [.command, .shift]) : nil)
                    .help(jp("Redo") + " (⇧⌘Z)")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { JText("Done") }
                        .keyboardShortcut(isWorkspace ? KeyboardShortcut(.return, modifiers: .command) : nil)
                        .help(jp("Done") + " (⌘↩)")
                }
            }
            .confirmationDialog(JText("Delete this step?"), isPresented: $confirmingDeleteStep, titleVisibility: .visible) {
                Button(role: .destructive, action: deleteStep) { JText("Delete step") }
            } message: {
                JText("Its drawing and notes go with it. Cancel brings it back until you press Done.")
            }
            .confirmationDialog(JText("Discard your changes to these steps?"), isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button(role: .destructive, action: discard) { JText("Discard changes") }
            }
        }
        .interactiveDismissDisabled(changed && onDrawingChange == nil)
    }

    /// The Journal's phone layout, unchanged: caption, court, tools, notes.
    private var compactLayout: some View {
            VStack(spacing: JSpacing.s) {
                TextField(text: $caption) { JText("Caption, like “Set” or “The read”") }
                    .font(.headline)
                    .submitLabel(.done)
                    .padding(.horizontal, JSpacing.m)
                    .frame(minHeight: JTouchTarget.standard)
                    .background(JPalette.card, in: .rect(cornerRadius: JRadius.tile))
                compactStepsBar
                canvas
                    .frame(maxHeight: .infinity, alignment: .top)
                tools
                HStack(alignment: .top, spacing: JSpacing.s) {
                    JText(tool.hint(drill: isDrill))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if tool.shapesLine {
                        Picker(selection: $lineShapeRaw) {
                            JText("Straight").tag(JournalPlayDiagram.PathShape.straight.rawValue)
                            JText("Curved").tag(JournalPlayDiagram.PathShape.curved.rawValue)
                        } label: {
                            JText("Line")
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityIdentifier("plays.editor.lineShape")
                    }
                }
                if tool == .defender { defenseControls }
                TextField(text: $text, axis: .vertical) { JText("What happens, and what to read") }
                    .lineLimit(2...5)
                    .padding(JSpacing.s)
                    .frame(minHeight: JTouchTarget.standard)
                    .background(JPalette.card, in: .rect(cornerRadius: JRadius.tile))
            }
            .padding(.horizontal, JSpacing.screen)
            .padding(.bottom, JSpacing.s)
    }

    // MARK: - Workspace (regular width)

    /// Tool rail | court | inspector.
    private var workspace: some View {
        HStack(spacing: 0) {
            toolRail
            Divider()
            if board != nil {
                SwiftUI.Group {
                    if boardPlayer { boardStage } else { canvas }
                }
                    .padding(JSpacing.m)
                    .padding(.bottom, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Steps · Defense · the play bar (20 Nov 2026, Luther:
                    // the defense gets its own place, between the two).
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: JSpacing.s) {
                            boardStepsButton
                            Spacer(minLength: 0)
                            defenseDock
                            Spacer(minLength: 0)
                            boardTransport
                        }
                        .padding(JSpacing.m)
                    }
                    // Pen or highlighter and its colour, while annotating.
                    .overlay(alignment: .top) {
                        if annotating { annotationPalette.padding(.top, JSpacing.xs) }
                    }
            } else if inspectorBelow {
                VStack(spacing: 0) {
                    canvas
                        .padding(JSpacing.m)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    bottomInspector
                        .frame(height: min(300, workspaceSize.height * 0.36))
                }
            } else {
                canvas
                    .padding(JSpacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector
                    .frame(width: 290)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            workspaceSize = size
            if focus == nil { inspectorBelow = size.width < size.height }
        }
        .onChange(of: focus) { _, field in
            if field == nil { inspectorBelow = workspaceSize.width < workspaceSize.height }
        }
        .background { shortcutKeys }
    }

    /// The inspector laid out under the court: Steps as a row of small
    /// drawings with their controls, then this step's words beside the tool
    /// and the selection.
    private var bottomInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JSpacing.m) {
                stepsPanel
                HStack(alignment: .top, spacing: JSpacing.m) {
                    inspectorSection("This step") { stepFields(notesLines: 2...4) }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: JSpacing.m) {
                        defenseSection
                        toolSection
                        if let selection { selectionSection(selection) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(JSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JPalette.card)
    }

    // MARK: - Steps panel (17 Nov 2026, Luther: "the steps bottom tab is not
    // so well designed") — one header line ("STEPS  2 of 3", then move and
    // delete as one small capsule) over a filmstrip: each step a drawing with
    // its number on it and its caption under, the one on screen ringed in the
    // accent, and "+" as the strip's last frame. Tapping a frame shows it;
    // ⌘[ ⌘] still step through (hidden buttons).

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: JSpacing.s) {
            stepsHeader
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: JSpacing.s) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { i, other in
                            filmFrame(i, other).id(other.id)
                        }
                        addFrame
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
                .onChange(of: current) { _, id in withAnimation { reader.scrollTo(id, anchor: .center) } }
            }
        }
        .background { stepKeys }
    }

    private var stepsHeader: some View {
        HStack(spacing: JSpacing.s) {
            JEyebrowLabel(title: "Steps")
            JText("\(number) of \(pages.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if pages.count > 1 {
                HStack(spacing: 0) {
                    Menu {
                        Button { moveStep(by: -1) } label: {
                            Label { JText("Move step earlier") } icon: { Image(systemName: "arrow.left") }
                        }
                        .disabled(number <= 1)
                        Button { moveStep(by: 1) } label: {
                            Label { JText("Move step later") } icon: { Image(systemName: "arrow.right") }
                        }
                        .disabled(number >= pages.count)
                    } label: {
                        Label { JText("Move step") } icon: { Image(systemName: "arrow.left.arrow.right") }
                            .frame(width: 40, height: 32)
                    }
                    .help(jp("Move step"))
                    Divider().frame(height: 18)
                    Button(role: .destructive) { confirmingDeleteStep = true } label: {
                        Label { JText("Delete step") } icon: { Image(systemName: "trash") }
                            .frame(width: 40, height: 32)
                    }
                    .help(jp("Delete step"))
                    .accessibilityIdentifier("plays.editor.deleteStep")
                }
                .labelStyle(.iconOnly)
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(JPalette.ink)
                .background(JPalette.fill, in: Capsule())
            }
        }
    }

    /// One frame of the filmstrip.
    private func filmFrame(_ i: Int, _ other: Page) -> some View {
        let on = other.id == current
        let name = caption(of: other)
        return Button { show(other.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                JournalPlayThumbnail(diagram: shownDiagram(other), court: court, width: 104, height: 74)
                    .overlay(alignment: .topLeading) {
                        Text(verbatim: "\(i + 1)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(on ? .white : JPalette.ink)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(on ? Color.accentColor : JPalette.fill, in: Circle())
                            .padding(4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(on ? Color.accentColor : JPalette.ink.opacity(0.12), lineWidth: on ? 2 : 1)
                    }
                Text(verbatim: name.isEmpty ? jp("Step \(i + 1)") : name)
                    .font(.caption.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? JPalette.ink : .secondary)
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plays.editor.step.\(i + 1)")
    }

    /// The strip's last frame: a new step after the one on screen.
    private var addFrame: some View {
        Button(action: addStep) {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                JText("Add a step").font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 104, height: 74)
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plays.editor.addStep")
    }

    /// ⌘[ and ⌘] with no buttons on screen (the frames are the buttons).
    private var stepKeys: some View {
        ZStack {
            Button("") { go(by: -1) }
                .keyboardShortcut(keysActive ? KeyboardShortcut("[", modifiers: .command) : nil)
            Button("") { go(by: 1) }
                .keyboardShortcut(keysActive ? KeyboardShortcut("]", modifiers: .command) : nil)
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - The Coach board

    /// Bottom left of the court: which step, opening the steps and this
    /// step's words, defense, the tool's options and the selection.
    private var boardStepsButton: some View {
        Button { boardStepsOpen.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                JText("Step \(number) of \(pages.count)").monospacedDigit()
                Image(systemName: "chevron.up").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityIdentifier("plays.editor.steps")
        .popover(isPresented: $boardStepsOpen, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: JSpacing.l) {
                    stepsPanel
                    inspectorSection("This step") { stepFields(notesLines: 2...5) }
                    toolSection
                    if let selection { selectionSection(selection) }
                }
                .padding(JSpacing.m)
            }
            .frame(width: 460)
            .frame(minHeight: 420, maxHeight: 640)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// The board's court while it plays or scribbles: the play page's step
    /// player, court only, on the board's steps as they stand.
    private var boardStage: some View {
        JournalPlayStepPlayer(
            steps: drawingNow.steps.map { .init(diagram: $0.diagram, caption: $0.caption, text: $0.text) },
            court: court,
            index: Binding(get: { currentIndex }, set: { i in
                if pages.indices.contains(i) { show(pages[i].id) }
            }),
            autoplay: boardAutoplay,
            bare: true,
            scribbling: boardScribble,
            playToken: boardPlayToken,
            onPlayingChange: { now in
                boardPlaying = now
                // Back to drawing once the playback ends (Scribble stays).
                if !now, !boardScribble { boardPlayer = false }
            }
        ) { EmptyView() }
    }

    /// Bottom right: Scribble (iPad), ‹ ▶ › — playing right on the court.
    private var boardTransport: some View {
        HStack(spacing: 2) {
            if offersScribble {
                Button {
                    boardScribble.toggle()
                    boardAutoplay = false
                    boardPlayer = boardScribble || boardPlaying
                } label: {
                    Label { JText("Scribble") } icon: { Image(systemName: "scribble.variable") }
                        .labelStyle(.iconOnly)
                        .frame(width: 48, height: 44)
                        .foregroundStyle(boardScribble ? Color.accentColor : JPalette.ink)
                }
                .accessibilityIdentifier("board.scribble")
                .accessibilityAddTraits(boardScribble ? .isSelected : [])
                Divider().frame(height: 22)
            }
            Button { boardStep(by: -1) } label: {
                Label { JText("Previous step") } icon: { Image(systemName: "backward.end.fill") }
                    .labelStyle(.iconOnly).frame(width: 48, height: 44)
            }
            .disabled(number <= 1)
            .accessibilityIdentifier("board.previous")
            Button(action: boardPlayPause) {
                Label { boardPlaying ? JText("Pause") : JText("Play") } icon: {
                    Image(systemName: boardPlaying ? "pause.fill" : "play.fill")
                }
                .labelStyle(.iconOnly).font(.title3).frame(width: 56, height: 44)
            }
            .accessibilityIdentifier("board.play")
            Button { boardStep(by: 1) } label: {
                Label { JText("Next step") } icon: { Image(systemName: "forward.end.fill") }
                    .labelStyle(.iconOnly).frame(width: 48, height: 44)
            }
            .disabled(number >= pages.count)
            .accessibilityIdentifier("board.next")
            Divider().frame(height: 22)
            // A new step after this one, at once; its words go in the steps
            // panel at the bottom left if the coach wants them.
            Button(action: boardAddStep) {
                Label { JText("Add a step") } icon: { Image(systemName: "plus") }
                    .labelStyle(.iconOnly).font(.body.weight(.semibold)).frame(width: 48, height: 44)
            }
            .accessibilityIdentifier("board.addStep")
        }
        .buttonStyle(.plain)
        .foregroundStyle(JPalette.ink)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var offersScribble: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    private func boardPlayPause() {
        stash()
        selection = nil
        if boardPlayer {
            boardPlayToken += 1
        } else {
            boardAutoplay = true
            boardPlayer = true
        }
    }

    private func boardAddStep() {
        if boardPlayer && !boardScribble { boardPlayer = false }
        addStep()
    }

    /// ‹ ›: the step before or after, on the court at once (playing stops).
    private func boardStep(by offset: Int) {
        if boardPlayer && !boardScribble { boardPlayer = false }
        go(by: offset)
    }

    /// Court, Clear and Save — the board's top bar.
    @ViewBuilder
    private func boardControls(_ board: BoardActions) -> some View {
        Menu {
            ForEach(JournalCourtKind.allCases) { kind in
                Button { stash(); board.setCourt(kind, drawingNow) } label: {
                    if kind == court {
                        Label { JText(kind.label) } icon: { Image(systemName: "checkmark") }
                    } else {
                        JText(kind.label)
                    }
                }
            }
        } label: {
            Label { JText(court.label) } icon: { Image(systemName: "sportscourt") }
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("board.court")
        Button(action: toggleLanes) {
            Label { JText("Lanes") } icon: { Image(systemName: "rectangle.split.3x1") }
        }
        .tint(diagram.lanes ? Color.accentColor : nil)
        .accessibilityIdentifier("board.lanes")
        .accessibilityAddTraits(diagram.lanes ? .isSelected : [])
        Menu {
            Toggle(isOn: Binding(get: { annotating }, set: { on in
                annotating = on
                if on { boardScribble = false; boardPlayer = false }
            })) {
                Label { JText("Annotate") } icon: { Image(systemName: "pencil.tip") }
            }
            .accessibilityIdentifier("board.annotate")
            Toggle(isOn: $keepAnnotations) {
                Label { JText("Keep annotations") } icon: { Image(systemName: "tray.and.arrow.down") }
            }
            .accessibilityIdentifier("board.keepAnnotations")
            Button(role: .destructive) {
                guard diagram.ink != nil else { return }
                pushUndo()
                diagram.ink = nil
            } label: {
                Label { JText("Clear this step's annotations") } icon: { Image(systemName: "eraser.line.dashed") }
            }
            .disabled(diagram.ink == nil)
        } label: {
            Label { JText("Annotate") } icon: { Image(systemName: annotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") }
        }
        .tint(annotating ? Color.accentColor : nil)
        .accessibilityIdentifier("board.annotations")
        if let clear = board.clear {
            Button(role: .destructive, action: clear) {
                Label { JText("Clear") } icon: { Image(systemName: "eraser") }
            }
            .disabled(board.isBlank)
            .accessibilityIdentifier("board.clear")
        }
        if let saveAsPlay = board.saveAsPlay, let saveAsDrill = board.saveAsDrill {
            Menu {
                Button(action: saveAsPlay) {
                    Label { JText("Save as Play") } icon: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
                }
                .accessibilityIdentifier("board.saveAsPlay")
                Button(action: saveAsDrill) {
                    Label { JText("Save as Drill") } icon: { Image(systemName: "figure.basketball") }
                }
                .accessibilityIdentifier("board.saveAsDrill")
            } label: {
                Label { JText("Save") } icon: { Image(systemName: "square.and.arrow.down") }
            }
            .accessibilityIdentifier("board.save")
        }
    }

    /// Lanes on or off for every step (19 Nov 2026, Luther).
    private func toggleLanes() {
        let on = !diagram.lanes
        pushUndo()
        stash()
        for i in pages.indices where i != currentIndex { pages[i].draft.diagram.lanes = on }
        diagram.lanes = on
    }

    /// Free ink over the court while Annotate is on: finger, Pencil or
    /// pointer; each stroke is one undo step.
    private func annotationCanvas(size: CGSize) -> some View {
        let s = JournalPlayCourt.scale(court, width: size.width)
        return PlayInkLayer(drawing: Binding(
            get: { PlayInkImages.drawing(diagram.ink, scale: s) },
            set: { drawn in
                let data = PlayInkImages.data(drawn, scale: s)
                guard data != diagram.ink else { return }
                pushUndo()
                diagram.ink = data
            }), anyInput: true, ink: annotationPen.tool(annotationColor))
            .accessibilityIdentifier("board.inkCanvas")
    }

    /// Pen or highlighter, and its colour (19 Nov 2026, Luther), floating at
    /// the top of the court while Annotate is on.
    private var annotationPalette: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationPen.allCases) { pen in
                Button { annotationPenRaw = pen.rawValue } label: {
                    Image(systemName: pen == .pen ? "pencil.tip" : "highlighter")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 36)
                        .foregroundStyle(annotationPen == pen ? Color.white : JPalette.ink)
                        .background(annotationPen == pen ? Color.accentColor : .clear,
                                    in: .rect(cornerRadius: 10, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pen == .pen ? JText("Pen") : JText("Highlighter"))
                .accessibilityIdentifier("board.annotate.\(pen.rawValue)")
                .accessibilityAddTraits(annotationPen == pen ? .isSelected : [])
            }
            Rectangle().fill(JPalette.ink.opacity(0.15)).frame(width: 0.5, height: 24).padding(.horizontal, 4)
            ForEach(annotationPen.colors) { color in
                Button {
                    if annotationPen == .pen { penColorRaw = color.rawValue } else { highlighterColorRaw = color.rawValue }
                } label: {
                    Circle()
                        .fill(Color(color.ui))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(JPalette.ink.opacity(0.25), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(annotationColor == color ? Color.accentColor : .clear, lineWidth: 2.5))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(JText(color.label))
                .accessibilityIdentifier("board.annotate.color.\(color.rawValue)")
                .accessibilityAddTraits(annotationColor == color ? .isSelected : [])
            }
            Rectangle().fill(JPalette.ink.opacity(0.15)).frame(width: 0.5, height: 24).padding(.horizontal, 4)
            Button { annotating = false } label: {
                JText("Done").font(.subheadline.weight(.semibold)).padding(.horizontal, 8).frame(height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("board.annotate.done")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    /// One column of tools, grouped like a graphics app's: select, the four
    /// lines, the marks, erase. Each says its name and key on hover.
    /// One column of tools, grouped like a graphics app's: select, the
    /// lines, the marks, erase (18 Nov 2026, Luther: "the same quality as a
    /// modern design software"). 40 pt tiles on an 8 pt rhythm; the tool in
    /// use is an accent tile with a white glyph, a hovered one a faint fill;
    /// hairline group dividers; the rail's edge a hairline too.
    private var toolRail: some View {
        VStack(spacing: 4) {
            ForEach(Array(Tool.railGroups(drill: isDrill).enumerated()), id: \.offset) { i, group in
                if i > 0 {
                    Rectangle()
                        .fill(JPalette.ink.opacity(0.12))
                        .frame(width: 24, height: 0.5)
                        .padding(.vertical, 6)
                }
                ForEach(group) { item in railButton(item) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .background(JPalette.card)
        .overlay(alignment: .trailing) {
            Rectangle().fill(JPalette.ink.opacity(0.10)).frame(width: 0.5)
        }
        // The hover labels reach over the court.
        .zIndex(1)
    }

    private func railButton(_ item: Tool) -> some View {
        let on = tool == item
        let hovered = hoveredTool == item
        return Button {
            select(tool: item)
        } label: {
            icon(item, colored: !on)
                .foregroundStyle(on ? Color.white : JPalette.ink.opacity(hovered ? 1 : 0.82))
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? Color.accentColor : JPalette.ink.opacity(hovered ? 0.08 : 0))
                }
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }
                }
                .shadow(color: on ? Color.accentColor.opacity(0.35) : .clear, radius: 4, y: 1)
                .contentShape(.rect)
                .animation(.easeOut(duration: 0.12), value: on)
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keysActive ? KeyboardShortcut(KeyEquivalent(item.key), modifiers: []) : nil)
        // The tool's name and key, at once, beside the rail (a system
        // tooltip waits and sits under the pointer).
        .onHover { inside in
            if inside { hoveredTool = item } else if hoveredTool == item { hoveredTool = nil }
        }
        .overlay(alignment: .leading) {
            if hovered {
                HStack(spacing: 8) {
                    JText(item.label)
                        .font(.callout.weight(.medium))
                    Text(verbatim: String(item.key).uppercased())
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(JPalette.ink.opacity(0.08), in: .rect(cornerRadius: 4, style: .continuous))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(JPalette.ink.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .fixedSize()
                .offset(x: 50)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .accessibilityLabel(JText(item.label))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("plays.editor.tool.\(item.rawValue)")
    }

    private func select(tool item: Tool) {
        tool = item
        if item != .move { selection = nil }
    }

    /// The step, the tool, and what is selected.
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JSpacing.l) {
                stepsSection
                inspectorSection("This step") { stepFields(notesLines: 3...10) }
                defenseSection
                toolSection
                if pencilSeen { pencilSection }
                if let selection {
                    selectionSection(selection)
                }
            }
            .padding(JSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JPalette.card)
    }

    @ViewBuilder
    private func stepFields(notesLines: ClosedRange<Int>) -> some View {
        TextField(text: $caption) { JText("Caption, like “Set” or “The read”") }
            .font(.headline)
            .focused($focus, equals: .caption)
            .textFieldStyle(.roundedBorder)
        TextField(text: $text, axis: .vertical) { JText("What happens, and what to read") }
            .lineLimit(notesLines)
            .focused($focus, equals: .notes)
            .textFieldStyle(.roundedBorder)
    }

    private var toolSection: some View {
        inspectorSection(tool.label) {
            JText(tool == .move
                  ? (isDrill ? "Click to select a player, a defender, a cone or a line; drag to move it, or the end or a bend of a line."
                     : "Click to select a player, a defender or a line; drag to move it, or the end or a bend of a line.")
                  : tool.hint(drill: isDrill))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if tool.shapesLine {
                shapePicker($lineShapeRaw)
            }
        }
    }

    /// Shown once a Pencil has touched the court (15 Nov 2026).
    private var pencilSection: some View {
        inspectorSection("Apple Pencil") {
            Toggle(isOn: $pencilDraws) { JText("Pencil draws, finger moves") }
                .accessibilityIdentifier("plays.editor.pencilDraws")
            JText(pencilDraws
                  ? "The Pencil draws with the tool; a finger moves and selects, whatever the tool. Double-tap or squeeze the Pencil for the eraser, the last tool or the tools. Tap with two fingers to undo, three to redo."
                  : "The Pencil and a finger both use the tool. Double-tap or squeeze the Pencil for the eraser, the last tool or the tools. Tap with two fingers to undo, three to redo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The workspace always shows the defense (Luther, 12 Nov 2026: a play
    /// left "By hand" looked broken — the choice hid under the Defender tool).
    private var defenseSection: some View {
        inspectorSection("Defense") { defenseControls }
    }

    /// The mode, what it does, and — for man-to-man — how it plays.
    @ViewBuilder
    private var defenseControls: some View {
        VStack(alignment: .leading, spacing: JSpacing.s) {
            defensePicker
            JText(defenseExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if diagram.defenseMode == .man {
                schemeRow("On the ball", id: "onBall", selection: Binding(
                    get: { scheme.onBall }, set: { new in setScheme { $0.onBall = new } })) {
                    JText("Contain").tag(DefenseScheme.OnBall.contain)
                    JText("No middle").tag(DefenseScheme.OnBall.noMiddle)
                }
                schemeRow("One pass away", id: "offBall", selection: Binding(
                    get: { scheme.offBall }, set: { new in setScheme { $0.offBall = new } })) {
                    JText("Gap").tag(DefenseScheme.OffBall.gap)
                    JText("Deny").tag(DefenseScheme.OffBall.deny)
                }
                schemeRow("Ball screens", id: "screens", selection: Binding(
                    get: { scheme.screens }, set: { new in setScheme { $0.screens = new } })) {
                    JText("Switch").tag(DefenseScheme.Screens.switchAll)
                    JText("Drop").tag(DefenseScheme.Screens.drop)
                    JText("Hedge").tag(DefenseScheme.Screens.hedge)
                    JText("Trap").tag(DefenseScheme.Screens.trap)
                    JText("Chase").tag(DefenseScheme.Screens.chase)
                }
                Toggle(isOn: Binding(get: { scheme.helpRotate }, set: { new in setScheme { $0.helpRotate = new } })) {
                    JText("Help and rotate on drives")
                }
                .font(.subheadline)
                .accessibilityIdentifier("plays.editor.defense.help")
                JText(screensExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func schemeRow<V: Hashable, Content: View>(_ title: JPString, id: String, selection: Binding<V>,
                                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            JText(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(selection: selection, content: content) { JText(title) }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plays.editor.defense.\(id)")
        }
    }

    private var scheme: DefenseScheme { diagram.defenseScheme ?? .standard }

    private var defenseExplanation: JPString {
        switch diagram.defenseMode {
        case nil: "By hand: defenders stay where you put them."
        case .man: "Man-to-man: on the ball an arm's length off; one pass away in the gap or denying; two passes away on the split line. Drag a defender to nudge him."
        case .zone23: "2-3 zone: the defenders slide with the ball as the chart says — top, wing, corner, high post, low post. Drag one to nudge him."
        case .zone32: "3-2 zone: the defenders slide with the ball as the chart says — top, wing, corner, high post, low post. Drag one to nudge him."
        }
    }

    private var screensExplanation: JPString {
        switch scheme.screens {
        case .switchAll: "Switch: on every screen the two defenders swap men."
        case .drop: "Drop: the screener's man sinks between ball and rim; the handler's man goes over and trails."
        case .hedge: "Hedge: the screener's man steps out into the handler's path, then recovers; the low man tags the roller."
        case .trap: "Trap: both defenders on the ball; the low man tags the roller, the next man splits."
        case .chase: "Chase: no switch — over the top, a soft show by the screener's man."
        }
    }

    /// The Defense dock (20 Nov 2026, Luther: "instead of tucking it in steps
    /// give it its own expandable place to live"): a capsule in the bottom
    /// bar saying the defense; it opens upward into the controls.
    private var defenseDock: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { defenseOpen.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                Text(verbatim: defenseShortName)
                Image(systemName: defenseOpen ? "chevron.down" : "chevron.up").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityIdentifier("plays.editor.defenseDock")
        .overlay(alignment: .bottom) {
            if defenseOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: JSpacing.s) {
                        JEyebrowLabel(title: "Defense")
                        defenseControls
                    }
                    .padding(JSpacing.m)
                }
                .frame(width: 420)
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .offset(y: -56)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityIdentifier("plays.editor.defensePanel")
            }
        }
    }

    private var defenseShortName: String {
        switch diagram.defenseMode {
        case nil: jp("By hand")
        case .man:
            switch scheme.screens {
            case .switchAll: jp("Man") + " · " + jp("Switch")
            case .drop: jp("Man") + " · " + jp("Drop")
            case .hedge: jp("Man") + " · " + jp("Hedge")
            case .trap: jp("Man") + " · " + jp("Trap")
            case .chase: jp("Man") + " · " + jp("Chase")
            }
        case .zone23: "2-3"
        case .zone32: "3-2"
        }
    }

    /// A change to the man scheme, on every step of the part.
    private func setScheme(_ change: (inout DefenseScheme) -> Void) {
        var new = scheme
        change(&new)
        guard new != scheme else { return }
        pushUndo()
        stash()
        let applied = JournalPlayMath.applyingScheme(new, to: pages.map(\.draft.diagram), court: court)
        for (i, d) in applied.enumerated() where i != currentIndex {
            if pages[i].draft.diagram != d {
                pages[i].draft.undo.append(pages[i].draft.diagram)
                pages[i].draft.diagram = d
            }
        }
        if applied.indices.contains(currentIndex) { diagram = applied[currentIndex] }
    }

    /// Auto defense for the whole part (12 November 2026, Luther): drawn by
    /// hand, man-to-man (matched by nearest, switch on every screen), or a
    /// 2-3 / 3-2 zone. Changing it re-matches from the first step on.
    private var defensePicker: some View {
        Picker(selection: Binding(get: { diagram.defenseMode?.rawValue ?? "off" },
                                  set: { setDefense(JournalPlayDiagram.DefenseMode(rawValue: $0)) })) {
            JText("By hand").tag("off")
            JText("Man").tag(JournalPlayDiagram.DefenseMode.man.rawValue)
            Text(verbatim: "2-3").tag(JournalPlayDiagram.DefenseMode.zone23.rawValue)
            Text(verbatim: "3-2").tag(JournalPlayDiagram.DefenseMode.zone32.rawValue)
        } label: { JText("Defense") }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("plays.editor.defense")
    }

    private func setDefense(_ mode: JournalPlayDiagram.DefenseMode?) {
        #if DEBUG
        Logger(subsystem: "hoopwise.mac", category: "defense").log("set \(mode?.rawValue ?? "off", privacy: .public) was \(diagram.defenseMode?.rawValue ?? "off", privacy: .public)")
        #endif
        guard mode != diagram.defenseMode else { return }
        pushUndo()
        stash()
        let applied = JournalPlayMath.applyingDefense(mode, to: pages.map(\.draft.diagram), court: court)
        for (i, d) in applied.enumerated() where i != currentIndex {
            if pages[i].draft.diagram != d {
                pages[i].draft.undo.append(pages[i].draft.diagram)
                pages[i].draft.diagram = d
            }
        }
        if applied.indices.contains(currentIndex) { diagram = applied[currentIndex] }
        selection = nil
    }

    private func inspectorSection<Content: View>(_ title: JPString, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JSpacing.xs) {
            JEyebrowLabel(title: title)
            content()
        }
    }

    private func shapePicker(_ binding: Binding<String>) -> some View {
        Picker(selection: binding) {
            JText("Straight").tag(JournalPlayDiagram.PathShape.straight.rawValue)
            JText("Curved").tag(JournalPlayDiagram.PathShape.curved.rawValue)
        } label: {
            JText("Line")
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("plays.editor.lineShape")
    }

    @ViewBuilder
    private func selectionSection(_ selection: Selection) -> some View {
        switch selection {
        case .player(let n):
            inspectorSection("Player \(n)") {
                Toggle(isOn: Binding(get: { diagram.hasBall(n) }, set: { on in
                    pushUndo()
                    if on { diagram.balls.append(n) } else { diagram.balls.removeAll { $0 == n } }
                })) { JText("Has a ball") }
                if diagram.actions.contains(where: { $0.player == n }) {
                    Button(role: .destructive) {
                        pushUndo()
                        diagram.actions.removeAll { $0.player == n }
                    } label: { JText("Erase their lines") }
                }
                if isDrill { deleteSelectionButton }
            }
        case .cone(let i):
            if diagram.cones.indices.contains(i) {
                inspectorSection("Cone") { deleteSelectionButton }
            }
        case .defender(let i):
            if diagram.defense.indices.contains(i) {
                inspectorSection("Defender") {
                    Toggle(isOn: Binding(get: { diagram.defense.indices.contains(i) && diagram.defense[i].isRead },
                                         set: { on in
                        guard diagram.defense.indices.contains(i) else { return }
                        pushUndo()
                        diagram.defense[i].isRead = on
                    })) { JText("The one to read") }
                    deleteSelectionButton
                }
            }
        case .action(let i):
            if diagram.actions.indices.contains(i) {
                let action = diagram.actions[i]
                let byDefender = JournalPlayDiagram.defenderIndex(action.player) != nil
                inspectorSection(byDefender ? "A defender's cut"
                                 : action.kind == .pass ? "Pass from \(action.player) to \(action.receiver ?? 0)"
                                 : action.kind == .handoff ? "Hand-off from \(action.player) to \(action.receiver ?? 0)"
                                 : action.kind == .shot ? "Shot by \(action.player)" : "Line by \(action.player)") {
                    // A defender only cuts: no dribble or screen for him.
                    if action.kind.movesPlayer && !byDefender {
                        Picker(selection: Binding(get: { diagram.actions.indices.contains(i) ? diagram.actions[i].kind : .cut },
                                                  set: { kind in
                            guard diagram.actions.indices.contains(i), diagram.actions[i].kind != kind else { return }
                            pushUndo()
                            diagram.actions[i].kind = kind
                        })) {
                            JText(Tool.cut.label).tag(JournalPlayDiagram.ActionKind.cut)
                            JText(Tool.dribble.label).tag(JournalPlayDiagram.ActionKind.dribble)
                            JText(Tool.screen.label).tag(JournalPlayDiagram.ActionKind.screen)
                        } label: { JText("Kind") }
                        .pickerStyle(.segmented)
                        shapePicker(Binding(get: {
                            guard diagram.actions.indices.contains(i) else { return "straight" }
                            return (diagram.actions[i].isStraight ? JournalPlayDiagram.PathShape.straight : .curved).rawValue
                        }, set: { raw in
                            guard diagram.actions.indices.contains(i) else { return }
                            let wantsStraight = raw == JournalPlayDiagram.PathShape.straight.rawValue
                            guard diagram.actions[i].isStraight != wantsStraight else { return }
                            pushUndo()
                            diagram = JournalPlayMath.toggledShape(of: i, in: diagram)
                        }))
                        if !action.isStraight {
                            JText("Drag the dots on the line to shape it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    deleteSelectionButton
                }
            }
        }
    }

    private var deleteSelectionButton: some View {
        Button(role: .destructive, action: deleteSelection) {
            Label { JText("Delete") } icon: { Image(systemName: "trash") }
        }
        .help(jp("Delete") + " (⌫)")
    }

    /// ⌫, Esc and the arrows (see `JournalEditorKeys` for why not SwiftUI).
    private var shortcutKeys: some View {
        JournalEditorKeys(active: keysActive) { key, shift in
            let step = shift ? 0.5 : 0.1
            switch key {
            case .delete: deleteSelection()
            case .escape:
                if selection != nil { selection = nil } else if changed && onDrawingChange == nil { confirmingDiscard = true } else { dismiss() }
            case .left: nudgeOnScreen(-step, 0)
            case .right: nudgeOnScreen(step, 0)
            case .up: nudgeOnScreen(0, -step)
            case .down: nudgeOnScreen(0, step)
            }
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
    }

    /// ⌫: a defender, a cone or a line goes; players stay (a play always has
    /// five), except in a drill.
    private func deleteSelection() {
        switch selection {
        case .player(let n)?:
            guard isDrill, diagram.player(n) != nil else { return }
            pushUndo()
            diagram = JournalPlayMath.removing(player: n, from: diagram)
        case .cone(let i)?:
            guard diagram.cones.indices.contains(i) else { return }
            pushUndo()
            diagram.cones.remove(at: i)
        case .defender(let i)?:
            guard diagram.defense.indices.contains(i) else { return }
            pushUndo()
            diagram = JournalPlayMath.removing(defender: i, from: diagram)
        case .action(let i)?:
            guard diagram.actions.indices.contains(i) else { return }
            pushUndo()
            diagram.actions.remove(at: i)
        default:
            return
        }
        selection = nil
    }

    /// Arrow keys move the selected player or defender a little (metres).
    /// An arrow key moves the selection the way it points on screen (the
    /// full court is drawn turned: screen right = court y, screen up = court x).
    private func nudgeOnScreen(_ dx: Double, _ dy: Double) {
        if JournalPlayCourt.isUpright(court) { nudge(-dy, dx) } else { nudge(dx, dy) }
    }

    private func nudge(_ dx: Double, _ dy: Double) {
        switch selection {
        case .player(let n)?:
            guard let at = diagram.player(n)?.at else { return }
            pushUndo()
            diagram = JournalPlayMath.moving(player: n, to: JournalCourtPoint(at.x + dx, at.y + dy), in: diagram)
        case .defender(let i)?:
            guard diagram.defense.indices.contains(i) else { return }
            pushUndo()
            let at = diagram.defense[i].at
            if diagram.defenseMode != nil {
                diagram = JournalPlayMath.nudging(defender: i, to: JournalCourtPoint(at.x + dx, at.y + dy), in: diagram, court: court)
            } else {
                diagram = JournalPlayMath.moving(defender: i, to: JournalCourtPoint(at.x + dx, at.y + dy), in: diagram)
            }
        case .cone(let i)?:
            guard diagram.cones.indices.contains(i) else { return }
            pushUndo()
            diagram.cones[i].x += dx
            diagram.cones[i].y += dy
        default:
            break
        }
    }

    /// Clears a selection whose element is gone (after undo, erase…).
    private func validateSelection() {
        switch selection {
        case .player(let n)?: if diagram.player(n) == nil { selection = nil }
        case .defender(let i)?: if !diagram.defense.indices.contains(i) { selection = nil }
        case .cone(let i)?: if !diagram.cones.indices.contains(i) { selection = nil }
        case .action(let i)?: if !diagram.actions.indices.contains(i) { selection = nil }
        case nil: break
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        JournalPlayDiagramView(diagram: shown, court: court, showsBends: tool == .move, highlight: selection?.hit,
                               showsInk: !annotating)
            .overlay {
                GeometryReader { proxy in
                    CourtInputLayer(
                        onTouch: { handle($0, size: proxy.size) },
                        onHover: { point in hoverPoint = point.map { metres($0, size: proxy.size) } },
                        onUndo: { cancelDrag(); undo() },
                        onRedo: { cancelDrag(); redo() },
                        onPencil: { shortcut, at in pencilShortcut(shortcut, at: at, size: proxy.size) })
                    .overlay(alignment: .topLeading) { hoverRing(size: proxy.size) }
                    .overlay(alignment: .topLeading) { pencilPalette(size: proxy.size) }
                    .overlay {
                        if annotating { annotationCanvas(size: proxy.size) }
                    }
                }
            }
            .padding(JSpacing.xs)
            .background(JPalette.background, in: .rect(cornerRadius: JRadius.tile))
            .overlay(RoundedRectangle(cornerRadius: JRadius.tile).strokeBorder(JPalette.courtLine, lineWidth: 0.5))
            .accessibilityElement()
            .accessibilityLabel(JText("Drawing of step \(number)"))
            .accessibilityHint(JText(tool.hint(drill: isDrill)))
    }

    /// The drawing with the line being drawn, already straight or curved
    /// as it will be kept, so the hand's shake never shows.
    private var shown: JournalPlayDiagram {
        guard case .line(let player, let points)? = drag, points.count >= 2, let kind = activeTool.lineKind else {
            return diagram
        }
        var out = diagram
        if kind == .handoff {
            // Over a teammate: the hand-off as it will be kept; on the way,
            // the dribble it starts with.
            if let snapped = JournalPlayMath.addingHandoff(by: player, along: points, to: diagram, radius: 0.9, shape: lineShape) {
                return snapped
            }
            out.actions.append(.init(kind: .dribble, player: player, path: JournalPlayMath.shaped(points, lineShape), shape: lineShape))
        } else if kind.hasReceiver {
            out.actions.append(.init(kind: kind, player: player, path: [points[0], points[points.count - 1]]))
        } else if kind == .shot {
            let end = points[points.count - 1]
            let rim = court.baskets.min { $0.distance(to: end) < $1.distance(to: end) } ?? end
            out.actions.append(.init(kind: kind, player: player, path: [points[0], rim]))
        } else {
            out.actions.append(.init(kind: kind, player: player, path: JournalPlayMath.shaped(points, lineShape),
                                     shape: lineShape))
        }
        return out
    }

    private func metres(_ p: CGPoint, size: CGSize) -> JournalCourtPoint {
        JournalPlayCourt.courtPoint(p, scale: JournalPlayCourt.scale(court, width: size.width), court: court)
    }

    private func viewPoint(_ m: JournalCourtPoint, size: CGSize) -> CGPoint {
        JournalPlayCourt.point(m, scale: JournalPlayCourt.scale(court, width: size.width), court: court)
    }

    /// A finger's reach: a player's circle, at least 22 pt; a pointer or the
    /// Pencil is precise, so they only ask for the circle (at least 12 pt).
    private func hitRadius(size: CGSize, precise: Bool) -> Double {
        let s = JournalPlayCourt.scale(court, width: size.width)
        return (isWorkspace || precise)
            ? max(JournalPlayCourt.playerRadius * max(1, 17 / s), 12 / s)
            : max(JournalPlayCourt.playerRadius * max(1, 17 / s) * 1.3, 22 / s)
    }

    /// One touch from the court's input layer (a finger, the Pencil, the
    /// Mac's pointer): the old drag gesture's rules, with the Pencil's.
    private func handle(_ event: CourtInputEvent, size: CGSize) {
        let point = metres(event.location, size: size)
        let radius = hitRadius(size: size, precise: event.isPencil)
        switch event.phase {
        case .began:
            paletteAt = nil
            if event.isPencil { pencilSeen = true }
            // Pencil mode: the Pencil draws with the tool, a finger moves.
            gestureTool = (pencilDraws && pencilSeen && !event.isPencil) ? .move : nil
            focus = nil
            dragStart = event.location
            drag = begin(at: point, radius: radius)
        case .moved:
            guard drag != nil, let start = dragStart,
                  hypot(event.location.x - start.x, event.location.y - start.y) > 4 else { return }
            update(to: point)
        case .ended:
            guard drag != nil else { return }
            let start = dragStart ?? event.location
            let distance = hypot(event.location.x - start.x, event.location.y - start.y)
            finish(at: point, isTap: distance <= 8, radius: radius)
            drag = nil
            gestureTool = nil
            dragStart = nil
        case .cancelled:
            cancelDrag()
        }
    }

    /// Drops the touch in progress as if it never happened (a second finger
    /// came down, the Pencil took over).
    private func cancelDrag() {
        switch drag {
        case .player, .defender, .cone, .actionEnd, .bend:
            if let previous = undoStack.popLast() { diagram = previous }
        default:
            break
        }
        drag = nil
        gestureTool = nil
        dragStart = nil
    }

    private func pencilShortcut(_ shortcut: PencilShortcut, at: CGPoint?, size: CGSize) {
        pencilSeen = true
        switch shortcut {
        case .eraser:
            if tool == .erase { tool = previousTool == .erase ? .move : previousTool } else { tool = .erase }
        case .previousTool:
            let back = previousTool
            tool = back
        case .palette:
            paletteAt = at ?? CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    /// A ring on what a Pencil stroke (or the pointer) would use: the
    /// player a line starts from, or what Move picks up.
    @ViewBuilder
    private func hoverRing(size: CGSize) -> some View {
        if drag == nil, let hover = hoverPoint, let target = hoverTarget(hover, size: size) {
            let s = JournalPlayCourt.scale(court, width: size.width)
            let d = JournalPlayCourt.playerRadius * s * 2 + 10
            Circle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: tool.lineKind != nil ? [4, 3] : []))
                .frame(width: d, height: d)
                .position(viewPoint(target, size: size))
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.12), value: target.x + target.y)
        }
    }

    private func hoverTarget(_ point: JournalCourtPoint, size: CGSize) -> JournalCourtPoint? {
        let radius = hitRadius(size: size, precise: true)
        if let kind = tool.lineKind {
            guard let start = JournalPlayMath.lineStart(at: point, in: diagram, radius: radius, defenders: kind == .cut),
                  Self.mayStart(kind, by: start.player, in: diagram) else { return nil }
            return start.from
        }
        guard tool == .move || tool == .erase || tool == .ball || tool == .defender else { return nil }
        switch JournalPlayMath.hit(point, in: diagram, radius: radius) {
        case .player(let n)?: return diagram.player(n)?.at
        case .defender(let i)?: return diagram.defense.indices.contains(i) ? diagram.defense[i].at : nil
        case .cone(let i)?: return diagram.cones.indices.contains(i) ? diagram.cones[i] : nil
        default: return nil
        }
    }

    /// The tools at the Pencil tip (squeeze / the system's palette action).
    @ViewBuilder
    private func pencilPalette(size: CGSize) -> some View {
        if let at = paletteAt {
            let items = Tool.available(drill: isDrill)
            let width = CGFloat(items.count) * 40 + 16
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        tool = item
                        paletteAt = nil
                    } label: {
                        icon(item)
                            .frame(width: 24, height: 22)
                            .frame(width: 40, height: 40)
                            .background(tool == item ? JPalette.fill : .clear, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(JText(item.label))
                }
            }
            .padding(8)
            .glassEffect(.regular, in: .capsule)
            .position(x: min(max(at.x, width / 2 + 4), size.width - width / 2 - 4),
                      y: max(at.y - 56, 28))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func begin(at point: JournalCourtPoint, radius: Double) -> Drag {
        if activeTool == .move {
            let hit = JournalPlayMath.hit(point, in: diagram, radius: radius)
            if isWorkspace {
                // Whatever is picked up is selected, for the inspector and keys.
                switch hit {
                case .player(let n): selection = .player(n)
                case .defender(let i): selection = .defender(i)
                case .cone(let i): selection = .cone(i)
                case .actionEnd(let i), .actionBend(let i, _), .action(let i): selection = .action(i)
                case .note, nil: selection = nil
                }
            }
            switch hit {
            case .player(let n): pushUndo(); return .player(n)
            case .defender(let i): pushUndo(); return .defender(i)
            case .cone(let i): pushUndo(); return .cone(i)
            case .actionEnd(let i): pushUndo(); return .actionEnd(i)
            case .actionBend(let a, let p): pushUndo(); return .bend(action: a, point: p)
            default: return .tap
            }
        }
        if let kind = activeTool.lineKind,
           let start = JournalPlayMath.lineStart(at: point, in: diagram, radius: radius, defenders: kind == .cut),
           Self.mayStart(kind, by: start.player, in: diagram) {
            return .line(player: start.player, points: [start.from])
        }
        return .tap
    }

    /// THE BALL RULE (17 Nov 2026, Luther: "a pass can only be drawn from a
    /// player with a ball, otherwise nothing is drawn; a dribble same"): a
    /// pass, dribble, shot or hand-off starts only from a player who holds a
    /// ball at that point of the step — at the start, or after the passes
    /// already drawn (`ballsAfter`). Cuts and screens need none.
    static func mayStart(_ kind: JournalPlayDiagram.ActionKind, by player: Int, in diagram: JournalPlayDiagram) -> Bool {
        let needsBall = kind.throwsBall || kind == .dribble || kind == .handoff
        return !needsBall || JournalPlayMath.ballsAfter(diagram).contains(player)
    }

    private func update(to point: JournalCourtPoint) {
        switch drag {
        case .player(let n): diagram = JournalPlayMath.moving(player: n, to: point, in: diagram)
        case .defender(let i):
            guard diagram.defense.indices.contains(i) else { break }
            if diagram.defenseMode != nil {
                diagram = JournalPlayMath.nudging(defender: i, to: point, in: diagram, court: court)
            } else {
                diagram = JournalPlayMath.moving(defender: i, to: point, in: diagram)
            }
        case .cone(let i): if diagram.cones.indices.contains(i) { diagram.cones[i] = point }
        case .actionEnd(let i): diagram = JournalPlayMath.moving(endOf: i, to: point, in: diagram)
        case .bend(let a, let p): diagram = JournalPlayMath.moving(bend: p, of: a, to: point, in: diagram)
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
            if let kind = activeTool.lineKind,
               let added = JournalPlayMath.adding(kind, by: player, along: points + [point], to: diagram, radius: radius,
                                                  shape: lineShape, court: court) {
                pushUndo()
                diagram = added
            }
        case .player, .defender, .cone, .actionEnd:
            // A touch that didn't move changes nothing.
            if isTap, let previous = undoStack.popLast() { diagram = previous }
        case .bend(let a, _):
            // A tap on a bend turns its line straight, like a tap on the line
            // (the workspace selects instead: the inspector changes the shape).
            if isTap {
                if let previous = undoStack.popLast() { diagram = previous }
                if !isWorkspace {
                    pushUndo()
                    diagram = JournalPlayMath.toggledShape(of: a, in: diagram)
                }
            }
        case .tap, nil:
            guard isTap else { return }
            tap(at: point, radius: radius)
        }
    }

    private func tap(at point: JournalCourtPoint, radius: Double) {
        let hit = JournalPlayMath.hit(point, in: diagram, radius: radius)
        switch activeTool {
        case .move:
            guard !isWorkspace, case .action(let i)? = hit, diagram.actions[i].kind.movesPlayer else { return }
            pushUndo()
            diagram = JournalPlayMath.toggledShape(of: i, in: diagram)
        case .player:
            // A new player where the court is free; a tap on one does nothing.
            if case .player? = hit { return }
            pushUndo()
            diagram.offense.append(.init(number: diagram.nextPlayerNumber, at: point))
        case .cone:
            pushUndo()
            diagram.cones.append(point)
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
            // Each player holds at most one ball here; several players can
            // hold one each (a drill with more than one ball).
            if let i = diagram.balls.firstIndex(of: n) {
                diagram.balls.remove(at: i)
            } else {
                diagram.balls.append(n)
            }
        case .erase:
            guard let hit else { return }
            if case .player(let n) = hit {
                guard isDrill else { return }
                pushUndo()
                diagram = JournalPlayMath.removing(player: n, from: diagram)
                selection = nil
                return
            }
            pushUndo()
            diagram = JournalPlayMath.erasing(hit, in: diagram)
            selection = nil
        default:
            break
        }
    }

    // MARK: - Tools

    /// Two rows of five, all in reach: 44 pt high, icon and name.
    /// A drill's twelve tools sit six and six, the name under the icon.
    private var tools: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: JSpacing.xxs), count: isDrill ? 6 : 5)
        return LazyVGrid(columns: columns, spacing: JSpacing.xxs) {
            ForEach(Tool.available(drill: isDrill)) { item in
                Button {
                    tool = item
                } label: {
                    let layout = isDrill ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 2))
                    layout {
                        icon(item)
                            .frame(width: 24, height: 20)
                        JText(item.label)
                            .font(isDrill ? .caption2.weight(tool == item ? .semibold : .regular)
                                  : .caption.weight(tool == item ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
                .accessibilityIdentifier("plays.editor.tool.\(item.rawValue)")
            }
        }
    }

    /// Every tool's icon, everywhere (rail, phone grid, Pencil palette):
    /// one drawn family — EditorToolGlyph.
    private func icon(_ tool: Tool, colored: Bool = true) -> some View {
        EditorToolGlyph(tool: tool, size: 20, colored: colored)
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
        validateSelection()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(diagram)
        diagram = next
        validateSelection()
    }

    /// Every step as it stands, the one on screen included (no state written).
    private var drawingNow: DrillDrawing {
        DrillDrawing(court: court, steps: pages.map { page in
            let draft = page.id == current ? Draft(diagram: diagram, caption: caption, text: text) : page.draft
            return DrillDrawing.Step(diagram: kept(draft.diagram), caption: draft.caption, text: draft.text)
        })
    }

    /// The step as it is kept: its annotations only when the coach chose to
    /// keep them.
    private func kept(_ d: JournalPlayDiagram) -> JournalPlayDiagram {
        guard !keepAnnotations, d.ink != nil else { return d }
        var out = d
        out.ink = nil
        return out
    }

    private func reportDrawing() {
        onDrawingChange?(drawingNow)
    }

    /// Every step's draft is written, then saved once.
    private func save() {
        stash()
        func trimmed(_ string: String) -> String { string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let onSaveDrill {
            onSaveDrill(DrillDrawing(court: court, steps: pages.map { page in
                DrillDrawing.Step(diagram: kept(page.draft.diagram), caption: trimmed(page.draft.caption),
                                  text: trimmed(page.draft.text))
            }))
            dismiss()
            return
        }
        for gone in deleted { if let model = gone.model { context.delete(model) } }
        for (order, page) in pages.enumerated() {
            let model: JournalPlayStep
            if let existing = page.model {
                model = existing
            } else {
                guard let part else { continue }
                model = JournalPlayStep(order: order)
                context.insert(model)
                part.steps?.append(model)
            }
            if model.order != order { model.order = order }
            let content = Content(diagram: kept(page.draft.diagram), caption: trimmed(page.draft.caption),
                                  text: trimmed(page.draft.text))
            guard page.model == nil || content != page.saved else { continue }
            model.caption = content.caption
            model.text = content.text
            model.diagram = content.diagram
        }
        try? context.save()
        if let play = part?.play { PlayActivity.edited(play) }
        dismiss()
    }

    /// Cancel: the drafts are dropped. Nothing was written, so nothing to undo.
    private func discard() {
        dismiss()
    }
}

