import SwiftUI

/// The read tree: every way the play can unfold.
///
/// A play is a tree of defensive reads, not a linear sequence, so this sits
/// alongside the timeline rather than inside it. The timeline is scoped to
/// whichever node is selected here.
struct ReadTreeView: View {
    @ObservedObject var model: PlayEditorModel

    @State private var branchingFrom: UUID?
    @State private var draftCondition = ""
    @State private var returningFrom: UUID?
    @State private var returnTarget: UUID?
    @State private var returnResumeAt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.treeRows) { row in
                        switch row.kind {
                        case .node(let node):
                            nodeRow(node, depth: row.depth, incoming: row.incoming)
                        case .returnEdge(let from, let edge):
                            returnRow(from: from, edge: edge, depth: row.depth)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            Divider()
            branchPicker
        }
        .frame(minWidth: 210)
        .alert("Add Alternative Read", isPresented: Binding(
            get: { branchingFrom != nil }, set: { if !$0 { branchingFrom = nil } })) {
            TextField("Defensive read, e.g. \"if they go under\"", text: $draftCondition)
            Button("Cancel", role: .cancel) { branchingFrom = nil }
            Button("Add") { commitBranch() }
        } message: {
            Text("Branches at \(String(format: "%.2f", model.playhead))s. The new read inherits everyone's position at that moment.")
        }
        .sheet(item: Binding(
            get: { returningFrom.map { IdentifiedUUID(id: $0) } },
            set: { if $0 == nil { returningFrom = nil } })) { wrapper in
            returnSheet(from: wrapper.id)
        }
    }

    private struct IdentifiedUUID: Identifiable { let id: UUID }

    private var header: some View {
        HStack(spacing: 6) {
            Text("READS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                draftCondition = ""
                branchingFrom = model.activeNodeId
            } label: { Image(systemName: "arrow.triangle.branch") }
            .buttonStyle(.borderless)
            .help("Add alternative read from here at \(String(format: "%.2f", model.playhead))s")

            Button {
                returnTarget = model.diagram.rootNodeId
                returnResumeAt = 0
                returningFrom = model.activeNodeId
            } label: { Image(systemName: "arrow.uturn.left") }
            .buttonStyle(.borderless)
            .help("Loop this read back to an earlier one")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    // MARK: - Rows

    private func nodeRow(_ node: ReadNode, depth: Int, incoming: ReadEdge?) -> some View {
        let isActive = model.activeNodeId == node.id
        let onPath = model.activePathNodeIds.contains(node.id)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: depth == 0 ? "play.circle.fill" : "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(onPath ? Color.accentColor : .secondary)
                Text(node.title)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1fs", node.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let incoming, let condition = incoming.condition {
                Text("\(condition) · at \(String(format: "%.2f", incoming.branchTime))s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, CGFloat(depth) * 14 + 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.16)
                    : (onPath ? Color.accentColor.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            // Selecting a node scopes the timeline to it.
            model.activeNodeId = node.id
            model.playhead = 0
        }
        .contextMenu {
            Button("Add Alternative Read…") {
                draftCondition = ""
                branchingFrom = node.id
            }
            Button("Loop Back To…") {
                returnTarget = model.diagram.rootNodeId
                returnResumeAt = 0
                returningFrom = node.id
            }
            Divider()
            if node.id != model.diagram.rootNodeId {
                Button("Delete Read", role: .destructive) { model.deleteNode(node.id) }
            }
        }
    }

    private func returnRow(from node: ReadNode, edge: ReadEdge, depth: Int) -> some View {
        let target = model.node(edge.targetId)
        let gap = model.returnContinuityGap(for: node.id)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 10)).foregroundStyle(.purple)
                Text("returns to \(target?.title ?? "?")")
                    .font(.caption).foregroundStyle(.purple)
                Spacer()
            }
            Text("departs \(String(format: "%.2f", edge.branchTime))s · resumes at \(String(format: "%.2f", edge.returnToTime ?? 0))s")
                .font(.caption2).foregroundStyle(.secondary)
            // A continuity offence returns to its starting alignment, so a big
            // jump means the play was mis-authored. Shown, not smoothed.
            if let gap, gap > 2.5 {
                Label(String(format: "%.1f ft jump on loop", gap), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, CGFloat(depth) * 14 + 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Remove Return", role: .destructive) {
                model.removeEdge(from: node.id, edgeId: edge.id)
            }
        }
    }

    // MARK: - Branch picker

    @ViewBuilder
    private var branchPicker: some View {
        let all = model.branches
        if all.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYBACK PATH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                // Clamped binding: NSPopUpButton traps on an out-of-range
                // selection index, so the binding itself must never hand it one.
                Picker("", selection: Binding(
                    get: { max(0, min(model.activeBranchIndex, all.count - 1)) },
                    set: { model.activeBranchIndex = max(0, min($0, all.count - 1)) })) {
                    ForEach(Array(all.enumerated()), id: \.offset) { index, branch in
                        Text(branch.nodes.map(\.title).joined(separator: " → "))
                            .tag(index)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                if let branch = model.activeBranch {
                    Text(String(format: "%.2fs to the end of this read", branch.duration))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
    }

    // MARK: - Actions

    private func commitBranch() {
        guard let from = branchingFrom else { return }
        let condition = draftCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        branchingFrom = nil
        if let child = model.addBranch(from: from, at: model.playhead, condition: condition) {
            model.activeNodeId = child
            model.playhead = 0
        }
    }

    private func returnSheet(from nodeId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loop Back").font(.headline)
            Text("This read ends by returning to an earlier one — a continuity offence resuming its alignment.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Returns to", selection: Binding(
                get: { returnTarget ?? model.diagram.rootNodeId },
                set: { returnTarget = $0 })) {
                ForEach(model.diagram.nodes, id: \.id) { node in
                    Text(node.title).tag(node.id)
                }
            }

            HStack {
                Text("Departs at")
                Spacer()
                Text(String(format: "%.2fs", model.playhead)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Resumes at")
                Spacer()
                TextField("0.00", value: $returnResumeAt, format: .number)
                    .frame(width: 70).multilineTextAlignment(.trailing)
                Text("s").foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { returningFrom = nil }
                Spacer()
                Button("Add Return") {
                    model.addReturn(from: nodeId,
                                    to: returnTarget ?? model.diagram.rootNodeId,
                                    departingAt: model.playhead,
                                    resumingAt: returnResumeAt,
                                    condition: "")
                    returningFrom = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}
