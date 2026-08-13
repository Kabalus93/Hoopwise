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

    private let cardWidth: CGFloat = 148
    private let cardHeight: CGFloat = 74

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
                    .padding(.vertical, 8)
                }
                .onChange(of: model.frameIndex) { _, index in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            Divider()
            captionRow
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
        .padding(.vertical, 5)
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
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? Color.white : .secondary)
                    .frame(width: 18, height: 18)
                    .background(isCurrent ? Color.accentColor : Color.secondary.opacity(0.22),
                                in: Circle())
                Spacer(minLength: 0)
                if !frame.validActions.isEmpty {
                    Text("\(frame.validActions.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(model.summary(of: frame))
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if !frame.caption.isEmpty {
                Text(frame.caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(7)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(isCurrent ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectFrame(index) }
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

    private var addButton: some View {
        Button(action: model.addFrame) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("Frame").font(.caption2)
            }
            .frame(width: 66, height: cardHeight)
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

    // MARK: - Caption

    /// The caption is the frame's coaching text and is edited in place. It
    /// commits on Return or when focus leaves — one undo step either way.
    private var captionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("What happens in frame \(model.frameIndex + 1)…",
                      text: Binding(
                        get: { model.currentFrame?.caption ?? "" },
                        set: { model.setCaption($0, at: model.frameIndex) }))
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($captionFocused)
            .onSubmit { captionFocused = false }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
