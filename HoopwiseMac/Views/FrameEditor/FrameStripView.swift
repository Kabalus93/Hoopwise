import SwiftUI
import UniformTypeIdentifiers

/// The frame strip — v2's primary chrome, where the timeline used to be.
///
/// Numbered cards, current one highlighted, `+` to add, drag to reorder,
/// context menu to duplicate or delete. The caption is edited HERE rather than
/// in an inspector, because the caption belongs to the frame and the frame is
/// what you are looking at.
///
/// Thumbnails are Phase C: this shows the frame's number, its actions in words,
/// and its caption, which is enough to navigate by and costs no render.
struct FrameStripView: View {
    @ObservedObject var model: FrameEditorModel
    @FocusState private var captionFocused: Bool
    @State private var draggingIndex: Int?

    /// Cards carry a live thumbnail, so they are wider than tall and the strip
    /// stays short — every point it does not take is court.
    private let cardWidth: CGFloat = 126
    private let cardHeight: CGFloat = 92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                            card(index: index, frame: frame)
                                .id(index)
                        }
                        addButton
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .onChange(of: model.frameIndex) { _, index in
                    // 180ms, and none at all under Reduce Motion.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("FRAMES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(model.frameIndex + 1) of \(max(1, model.frameCount))")
                .font(.caption2).foregroundStyle(.tertiary)

            Spacer()

            // Which READ is being authored, and how to branch. The full reads
            // panel becomes a popover in Phase C; this is the minimum that
            // makes a branched play authorable now.
            Menu {
                ForEach(model.reads, id: \.id) { read in
                    Button {
                        model.selectRead(read.id)
                    } label: {
                        if read.id == model.activeNodeId {
                            Label(readTitle(read), systemImage: "checkmark")
                        } else {
                            Text(readTitle(read))
                        }
                    }
                }
                Divider()
                Button("Branch After This Frame…") { beginBranch() }
            } label: {
                Label(model.node.map(readTitle) ?? "Read", systemImage: "arrow.triangle.branch")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Toggle(isOn: $model.showOnionSkin) {
                Label("Onion", systemImage: "circle.dashed")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Ghost the previous frame's end formation (O)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .alert("Branch After Frame \(model.frameIndex + 1)", isPresented: $askingBranch) {
            TextField("If the defender…", text: $branchCondition)
            Button("Cancel", role: .cancel) { askingBranch = false }
            Button("Add Read") {
                model.addRead(after: model.frameIndex, condition: branchCondition)
            }
        } message: {
            Text("The new read continues from where this frame leaves everyone.")
        }
    }

    private func readTitle(_ read: ReadNode) -> String {
        read.id == model.diagram.rootNodeId ? read.title
            : (model.condition(of: read.id).map { "if \($0)" } ?? read.title)
    }

    @State private var branchCondition = ""
    @State private var askingBranch = false

    private func beginBranch() {
        branchCondition = ""
        askingBranch = true
    }

    // MARK: - Cards

    private func card(index: Int, frame: PlayFrame) -> some View {
        let isCurrent = index == model.frameIndex
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                FrameThumbnail(model: model, index: index)
                    .frame(height: 52)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? Color.white : .secondary)
                    .frame(width: 16, height: 16)
                    .background(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35),
                                in: Circle())
                    .padding(3)
            }
            Divider().opacity(0.4)
            captionField(index: index, frame: frame, isCurrent: isCurrent)
                .frame(height: 22)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(isCurrent ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectFrame(index) }
        .help(model.summary(of: frame))
        .onDrag {
            draggingIndex = index
            return NSItemProvider(object: NSString(string: "\(index)"))
        }
        .onDrop(of: [.text], delegate: ReorderDrop(index: index, model: model,
                                                   dragging: $draggingIndex))
        .contextMenu {
            Button("Duplicate") { model.duplicateFrame(at: index) }
            Button("Insert Frame After") { model.addFrameAfter(index) }
            Divider()
            Button("Delete", role: .destructive) { model.deleteFrame(at: index) }
        }
    }

    /// The caption lives ON the card — edit in place, per the spec, and no
    /// separate row eating court height.
    @ViewBuilder
    private func captionField(index: Int, frame: PlayFrame, isCurrent: Bool) -> some View {
        if isCurrent {
            TextField("Caption…", text: Binding(
                get: { model.frames.indices.contains(index) ? model.frames[index].caption : "" },
                set: { model.setCaption($0, at: index) }))
            .textFieldStyle(.plain)
            .font(.system(size: 10))
            .focused($captionFocused)
            .onSubmit { captionFocused = false }
            .padding(.horizontal, 6)
        } else {
            Text(frame.caption.isEmpty ? model.summary(of: frame) : frame.caption)
                .font(.system(size: 10))
                .foregroundStyle(frame.caption.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addButton: some View {
        Button(action: model.addFrame) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("Frame").font(.caption2)
            }
            .frame(width: 58, height: cardHeight)
            .foregroundStyle(.secondary)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help("Add a frame continuing from this one (N)")
    }

}

/// Drag-to-reorder. Dropping on a card moves the dragged frame to that slot.
private struct ReorderDrop: DropDelegate {
    let index: Int
    let model: FrameEditorModel
    @Binding var dragging: Int?

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let source = dragging, source != index else { return false }
        model.moveFrame(from: source, to: index)
        return true
    }
}
