import SwiftData
import SwiftUI

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
struct JournalPlayStepEditor: View {
    let court: JournalCourtKind
    /// The step on screen; `diagram`, `caption`, `text` and the undo stacks
    /// are its working copy.
    @State private var step: JournalPlayStep
    /// Other steps' drafts, stashed when the editor moved off them.
    @State private var drafts: [PersistentIdentifier: Draft] = [:]
    /// Steps added in this editor (Cancel removes them).
    @State private var added: [JournalPlayStep] = []
    /// Saved steps deleted in this editor: hidden now, deleted on Done,
    /// back on Cancel.
    @State private var deleted: [JournalPlayStep] = []
    @State private var confirmingDeleteStep = false

    private struct Draft {
        var diagram: JournalPlayDiagram
        var caption: String
        var text: String
        var undo: [JournalPlayDiagram]
        var redo: [JournalPlayDiagram]
    }

    private var steps: [JournalPlayStep] {
        (step.part?.sortedSteps ?? [step]).filter { other in !deleted.contains { $0 === other } }
    }
    private var number: Int { (steps.firstIndex { $0 === step } ?? 0) + 1 }

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
    @State private var selection: Selection?
    /// The rail tool under the pointer: its name shows beside it.
    @State private var hoveredTool: Tool?
    @FocusState private var focus: Field?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Field { case caption, notes }

    /// What the Move tool picked (regular width).
    enum Selection: Equatable {
        case player(Int)
        case defender(Int)
        case action(Int)

        var hit: JournalPlayMath.PlayHit {
            switch self {
            case .player(let n): .player(n)
            case .defender(let i): .defender(i)
            case .action(let i): .action(i)
            }
        }
    }

    private var isWorkspace: Bool { sizeClass == .regular }
    /// Single-key shortcuts only in the workspace, and never while typing.
    private var keysActive: Bool { isWorkspace && focus == nil }
    /// Straight or curved for new lines; remembered on this device.
    @AppStorage("plays.lineShape") private var lineShapeRaw = JournalPlayDiagram.PathShape.straight.rawValue

    private var lineShape: JournalPlayDiagram.PathShape {
        JournalPlayDiagram.PathShape(rawValue: lineShapeRaw) ?? .straight
    }

    enum Tool: String, CaseIterable, Identifiable {
        case move, cut, dribble, pass, shot, screen, defender, ball, erase
        var id: String { rawValue }

        var label: JPString {
            switch self {
            case .move: "Move"
            case .cut: "Cut"
            case .dribble: "legend.dribble"
            case .pass: "Pass"
            case .shot: "Shot"
            case .screen: "Screen"
            case .defender: "Defender"
            case .ball: "Ball"
            case .erase: "Erase"
            }
        }

        var hint: JPString {
            switch self {
            case .move: "Drag a player, a defender, the end of a line or a bend. Tap a line to make it straight or curved."
            case .cut: "Drag from a player to where they run."
            case .dribble: "Drag from the ball handler to where they dribble."
            case .pass: "Drag from the passer to a teammate."
            case .shot: "Drag from the shooter toward the basket; the line ends in the rim."
            case .screen: "Drag from a player to where they set the screen."
            case .defender: "Tap the court to add a defender; tap one to mark the one to read."
            case .ball: "Tap a player to give or take a ball. Several players can each have one."
            case .erase: "Tap a line, a defender or a note to erase it."
            }
        }

        var lineKind: JournalPlayDiagram.ActionKind? {
            switch self {
            case .cut: .cut
            case .dribble: .dribble
            case .pass: .pass
            case .shot: .shot
            case .screen: .screen
            default: nil
            }
        }

        /// Lines that can run straight or curved (a pass is always straight).
        var shapesLine: Bool { self == .cut || self == .dribble || self == .screen }

        /// The workspace's single-key shortcut (graphics-app convention:
        /// V for the pointer).
        var key: Character {
            switch self {
            case .move: "v"
            case .cut: "c"
            case .dribble: "d"
            case .pass: "p"
            case .shot: "h"
            case .screen: "s"
            case .defender: "x"
            case .ball: "b"
            case .erase: "e"
            }
        }

        /// The rail's groups: select | lines | marks | erase.
        static let railGroups: [[Tool]] = [[.move], [.cut, .dribble, .pass, .shot, .screen], [.defender, .ball], [.erase]]
    }

    /// What the finger is doing.
    private enum Drag {
        case player(Int)
        case defender(Int)
        case actionEnd(Int)
        case bend(action: Int, point: Int)
        case line(player: Int, points: [JournalCourtPoint])
        case tap
    }

    /// Opens on `step`; its part's other steps are a menu away.
    init(step: JournalPlayStep, court: JournalCourtKind) {
        self.court = court
        _step = State(initialValue: step)
        _diagram = State(initialValue: step.diagram)
        _caption = State(initialValue: step.caption)
        _text = State(initialValue: step.text)
    }

    private var changed: Bool {
        if !added.isEmpty || !deleted.isEmpty { return true }
        if diagram != step.diagram || caption != step.caption || text != step.text { return true }
        return steps.contains { other in
            guard let draft = drafts[other.persistentModelID] else { return false }
            return draft.diagram != other.diagram || draft.caption != other.caption || draft.text != other.text
        }
    }

    // MARK: - Steps

    /// The working copy goes back into the drafts.
    private func stash() {
        drafts[step.persistentModelID] = Draft(diagram: diagram, caption: caption, text: text,
                                               undo: undoStack, redo: redoStack)
    }

    /// Another step on screen, with its draft if it has one.
    private func show(_ other: JournalPlayStep) {
        guard other !== step else { return }
        stash()
        let draft = drafts[other.persistentModelID]
        step = other
        diagram = draft?.diagram ?? other.diagram
        caption = draft?.caption ?? other.caption
        text = draft?.text ?? other.text
        undoStack = draft?.undo ?? []
        redoStack = draft?.redo ?? []
        selection = nil
        drag = nil
        focus = nil
    }

    private func go(by offset: Int) {
        let all = steps
        guard let i = all.firstIndex(where: { $0 === step }), all.indices.contains(i + offset) else { return }
        show(all[i + offset])
    }

    /// A step after this one, starting where this one's DRAFT ends.
    private func addStep() {
        guard let part = step.part else { return }
        let new = part.addStep(after: step, in: context)
        new.diagram = JournalPlayMath.startOfNextStep(after: diagram)
        added.append(new)
        show(new)
    }

    /// The step on screen goes; its neighbour (the next, else the one before)
    /// comes up. A step added here is deleted outright; a saved one waits
    /// for Done, so Cancel brings it back. The last step stays.
    private func deleteStep() {
        let all = steps
        guard all.count > 1, let i = all.firstIndex(where: { $0 === step }) else { return }
        let gone = step
        let neighbour = all.indices.contains(i + 1) ? all[i + 1] : all[i - 1]
        show(neighbour)
        drafts[gone.persistentModelID] = nil
        if let a = added.firstIndex(where: { $0 === gone }) {
            added.remove(at: a)
            let part = gone.part
            context.delete(gone)
            try? context.save()
            part?.renumberSteps()
        } else {
            deleted.append(gone)
        }
    }

    /// The diagram a step shows in the Steps list: its draft, else saved.
    private func shownDiagram(_ other: JournalPlayStep) -> JournalPlayDiagram {
        other === step ? diagram : drafts[other.persistentModelID]?.diagram ?? other.diagram
    }

    private func caption(of other: JournalPlayStep) -> String {
        other === step ? caption : drafts[other.persistentModelID]?.caption ?? other.caption
    }

    /// The title: "Step 2 of 3" opening a menu of the part's steps.
    private var stepMenu: some View {
        Menu {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, other in
                Button { show(other) } label: {
                    let name = caption(of: other)
                    if other === step {
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
            if steps.count > 1 {
                Button(role: .destructive) { confirmingDeleteStep = true } label: {
                    Label { JText("Delete step") } icon: { Image(systemName: "trash") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                JText("Step \(number) of \(steps.count)")
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

    /// The workspace's list of steps: small drawings, click to edit.
    private var stepsSection: some View {
        inspectorSection("Steps") {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, other in
                Button { show(other) } label: {
                    HStack(spacing: JSpacing.s) {
                        JournalPlayThumbnail(diagram: shownDiagram(other), court: court, width: 56, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            JText("Step \(i + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(verbatim: caption(of: other))
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(4)
                    .background(other === step ? JPalette.fill : .clear, in: .rect(cornerRadius: 8))
                    .overlay {
                        if other === step { RoundedRectangle(cornerRadius: 8).strokeBorder(JPalette.ink, lineWidth: 1) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plays.editor.step.\(i + 1)")
            }
            HStack {
                Button { go(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(number <= 1)
                    .keyboardShortcut(keysActive ? KeyboardShortcut("[", modifiers: .command) : nil)
                    .help(jp("Previous step") + " (⌘[)")
                Button { go(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(number >= steps.count)
                    .keyboardShortcut(keysActive ? KeyboardShortcut("]", modifiers: .command) : nil)
                    .help(jp("Next step") + " (⌘])")
                Spacer()
                Button(role: .destructive) { confirmingDeleteStep = true } label: {
                    Label { JText("Delete step") } icon: { Image(systemName: "trash") }
                        .labelStyle(.iconOnly)
                }
                .disabled(steps.count <= 1)
                .help(jp("Delete step"))
                .accessibilityIdentifier("plays.editor.deleteStep")
                Button(action: addStep) {
                    Label { JText("Add a step") } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("plays.editor.addStep")
            }
            .buttonStyle(.bordered)
        }
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if isWorkspace { workspace } else { compactLayout }
            }
            .background(JPalette.background)
            .navigationTitle(JText("Step \(number)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { stepMenu }
                ToolbarItem(placement: .cancellationAction) {
                    // Esc deselects first, then cancels (`shortcutKeys`).
                    Button { changed ? confirmingDiscard = true : dismiss() } label: { JText("Cancel") }
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
        .interactiveDismissDisabled(changed)
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
                canvas
                    .frame(maxHeight: .infinity, alignment: .top)
                tools
                HStack(alignment: .top, spacing: JSpacing.s) {
                    JText(tool.hint)
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
            canvas
                .padding(JSpacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inspector
                .frame(width: 300)
        }
        .background { shortcutKeys }
    }

    /// One column of tools, grouped like a graphics app's: select, the four
    /// lines, the marks, erase. Each says its name and key on hover.
    private var toolRail: some View {
        VStack(spacing: JSpacing.xs) {
            ForEach(Array(Tool.railGroups.enumerated()), id: \.offset) { i, group in
                if i > 0 {
                    Divider().frame(width: 28)
                }
                ForEach(group) { item in railButton(item) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, JSpacing.s)
        .frame(width: 60)
        .background(JPalette.card)
        // The hover labels reach over the court.
        .zIndex(1)
    }

    private func railButton(_ item: Tool) -> some View {
        Button {
            select(tool: item)
        } label: {
            SwiftUI.Group {
                // The pointer, as in graphics apps; the phone keeps its hand.
                if item == .move { Image(systemName: "cursorarrow").font(.body) } else { icon(item) }
            }
                .frame(width: 24, height: 20)
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(tool == item ? JPalette.fill : .clear, in: .rect(cornerRadius: 8))
                .overlay {
                    if tool == item {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(JPalette.ink, lineWidth: 1)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keysActive ? KeyboardShortcut(KeyEquivalent(item.key), modifiers: []) : nil)
        // The tool's name, at once, beside the rail (a system tooltip waits
        // and sits under the pointer).
        .onHover { inside in
            if inside { hoveredTool = item } else if hoveredTool == item { hoveredTool = nil }
        }
        .overlay(alignment: .leading) {
            if hoveredTool == item {
                JText(item.label)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: .capsule)
                    .overlay(Capsule().strokeBorder(JPalette.courtLine, lineWidth: 0.5))
                    .fixedSize()
                    .offset(x: 50)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(JText(item.label))
        .accessibilityAddTraits(tool == item ? .isSelected : [])
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
                inspectorSection("This step") {
                    TextField(text: $caption) { JText("Caption, like “Set” or “The read”") }
                        .font(.headline)
                        .focused($focus, equals: .caption)
                        .textFieldStyle(.roundedBorder)
                    TextField(text: $text, axis: .vertical) { JText("What happens, and what to read") }
                        .lineLimit(3...10)
                        .focused($focus, equals: .notes)
                        .textFieldStyle(.roundedBorder)
                }
                inspectorSection(tool.label) {
                    JText(tool == .move ? "Click to select a player, a defender or a line; drag to move it, or the end or a bend of a line." : tool.hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if tool.shapesLine {
                        shapePicker($lineShapeRaw)
                    }
                }
                if let selection {
                    selectionSection(selection)
                }
            }
            .padding(JSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JPalette.card)
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
                inspectorSection(action.kind == .pass ? "Pass from \(action.player) to \(action.receiver ?? 0)"
                                 : action.kind == .shot ? "Shot by \(action.player)" : "Line by \(action.player)") {
                    if action.kind.movesPlayer {
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
                if selection != nil { selection = nil } else if changed { confirmingDiscard = true } else { dismiss() }
            case .left: nudge(-step, 0)
            case .right: nudge(step, 0)
            case .up: nudge(0, -step)
            case .down: nudge(0, step)
            }
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
    }

    /// ⌫: a defender or a line goes; players stay (always five).
    private func deleteSelection() {
        switch selection {
        case .defender(let i)?:
            guard diagram.defense.indices.contains(i) else { return }
            pushUndo()
            diagram.defense.remove(at: i)
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
    private func nudge(_ dx: Double, _ dy: Double) {
        switch selection {
        case .player(let n)?:
            guard let at = diagram.player(n)?.at else { return }
            pushUndo()
            diagram = JournalPlayMath.moving(player: n, to: JournalCourtPoint(at.x + dx, at.y + dy), in: diagram)
        case .defender(let i)?:
            guard diagram.defense.indices.contains(i) else { return }
            pushUndo()
            diagram.defense[i].at.x += dx
            diagram.defense[i].at.y += dy
        default:
            break
        }
    }

    /// Clears a selection whose element is gone (after undo, erase…).
    private func validateSelection() {
        switch selection {
        case .player(let n)?: if diagram.player(n) == nil { selection = nil }
        case .defender(let i)?: if !diagram.defense.indices.contains(i) { selection = nil }
        case .action(let i)?: if !diagram.actions.indices.contains(i) { selection = nil }
        case nil: break
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        JournalPlayDiagramView(diagram: shown, court: court, showsBends: tool == .move, highlight: selection?.hit)
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

    /// The drawing with the line being drawn, already straight or curved
    /// as it will be kept, so the hand's shake never shows.
    private var shown: JournalPlayDiagram {
        guard case .line(let player, let points)? = drag, points.count >= 2, let kind = tool.lineKind else {
            return diagram
        }
        var out = diagram
        if kind == .pass {
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

    private func gesture(size: CGSize) -> some Gesture {
        let s = JournalPlayCourt.scale(court, width: size.width)
        func metres(_ p: CGPoint) -> JournalCourtPoint {
            JournalCourtPoint(p.x / s - JournalPlayCourt.margin, p.y / s - JournalPlayCourt.margin)
        }
        // A finger's reach: a player's circle, at least 22 pt; a pointer is
        // precise, so the workspace only asks for the circle (at least 12 pt).
        let radius = isWorkspace
            ? max(JournalPlayCourt.playerRadius * max(1, 17 / s), 12 / s)
            : max(JournalPlayCourt.playerRadius * max(1, 17 / s) * 1.3, 22 / s)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    focus = nil
                    drag = begin(at: metres(value.startLocation), radius: radius)
                }
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
            let hit = JournalPlayMath.hit(point, in: diagram, radius: radius)
            if isWorkspace {
                // Whatever is picked up is selected, for the inspector and keys.
                switch hit {
                case .player(let n): selection = .player(n)
                case .defender(let i): selection = .defender(i)
                case .actionEnd(let i), .actionBend(let i, _), .action(let i): selection = .action(i)
                case .note, nil: selection = nil
                }
            }
            switch hit {
            case .player(let n): pushUndo(); return .player(n)
            case .defender(let i): pushUndo(); return .defender(i)
            case .actionEnd(let i): pushUndo(); return .actionEnd(i)
            case .actionBend(let a, let p): pushUndo(); return .bend(action: a, point: p)
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
            if let kind = tool.lineKind,
               let added = JournalPlayMath.adding(kind, by: player, along: points + [point], to: diagram, radius: radius,
                                                  shape: lineShape, court: court) {
                pushUndo()
                diagram = added
            }
        case .player, .defender, .actionEnd:
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
        switch tool {
        case .move:
            guard !isWorkspace, case .action(let i)? = hit, diagram.actions[i].kind.movesPlayer else { return }
            pushUndo()
            diagram = JournalPlayMath.toggledShape(of: i, in: diagram)
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
            if case .player = hit { return }
            pushUndo()
            diagram = JournalPlayMath.erasing(hit, in: diagram)
            selection = nil
        default:
            break
        }
    }

    // MARK: - Tools

    /// Two rows (five, then four), all in reach: 44 pt high, icon and name.
    private var tools: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: JSpacing.xxs), count: 5)
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
        case .shot: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .shot, player: 0, path: line)]))
        // Upright, so the screen's bar reads as a T.
        case .screen: JournalPlayMark(diagram: JournalPlayDiagram(actions: [.init(kind: .screen, player: 0, path: [JournalCourtPoint(1, 2.4), JournalCourtPoint(1, 0.15)])]))
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
        validateSelection()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(diagram)
        diagram = next
        validateSelection()
    }

    /// Every step's draft is written, then saved once.
    private func save() {
        stash()
        if !deleted.isEmpty {
            let part = step.part
            for gone in deleted { context.delete(gone) }
            try? context.save()
            part?.renumberSteps()
        }
        for other in steps {
            guard let draft = drafts[other.persistentModelID] else { continue }
            other.caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            other.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            other.diagram = draft.diagram
        }
        try? context.save()
        dismiss()
    }

    /// Cancel: drafts dropped, steps added here removed.
    private func discard() {
        if !added.isEmpty {
            let part = step.part
            for new in added { context.delete(new) }
            try? context.save()
            part?.renumberSteps()
            try? context.save()
        }
        dismiss()
    }
}
