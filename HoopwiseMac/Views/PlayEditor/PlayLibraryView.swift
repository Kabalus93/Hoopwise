import SwiftUI
import Combine

/// Named plays, backed by real SDPlay records.
///
/// This gates the work after it: the read-tree navigator edits a NAMED play,
/// the concept graph links to named plays, and the PDF play sheet needs a
/// title. A loose in-memory diagram cannot carry any of that.
struct PlayLibraryView: View {
    @EnvironmentObject private var dataManager: DataManager
    @ObservedObject var model: PlayEditorModel

    @State private var entries: [Entry] = []
    @State private var renaming: Entry?
    @State private var draftName = ""
    @State private var confirmingDelete: Entry?

    struct Entry: Identifiable, Hashable {
        let id: UUID          // diagram id
        let playId: UUID
        var name: String
        var category: PlayCategory
        var formation: String
        var updatedAt: Date
        var nodeCount: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 200)
        .onAppear(perform: reload)
        // Reload when the editor saves, so the list reflects renames and edits.
        .onReceive(model.$diagram.debounce(for: .seconds(1.4), scheduler: RunLoop.main)) { _ in
            reload()
        }
        .alert("Rename Play", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { commitRename() }
        }
        .alert("Delete Play?", isPresented: Binding(
            get: { confirmingDelete != nil },
            set: { if !$0 { confirmingDelete = nil } })) {
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
            Button("Delete", role: .destructive) { commitDelete() }
        } message: {
            Text("\(confirmingDelete?.name ?? "This play") and its diagram will be removed. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("PLAYS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(entries.count)")
                .font(.caption2).foregroundStyle(.tertiary)
            Button(action: newPlay) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Play (⌘N)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sportscourt")
                    .font(.title2).foregroundStyle(.tertiary)
                Text("No plays yet")
                    .font(.caption).foregroundStyle(.secondary)
                Button("New Play", action: newPlay)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    row(entry)
                        .listRowBackground(entry.id == model.currentDiagramId
                                           ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.callout.weight(entry.id == model.currentDiagramId ? .semibold : .regular))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(entry.category.displayName)
                if !entry.formation.isEmpty {
                    Text("·"); Text(entry.formation)
                }
                Spacer()
                Text("\(entry.nodeCount) read\(entry.nodeCount == 1 ? "" : "s")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { open(entry) }
        .contextMenu {
            Button("Open") { open(entry) }
            Button("Rename…") { beginRename(entry) }
            Button("Duplicate") { duplicate(entry) }
            Divider()
            Button("Delete…", role: .destructive) { confirmingDelete = entry }
        }
    }

    // MARK: - Actions

    private func reload() {
        entries = dataManager.allPlayDiagrams().map { row in
            let play = dataManager.plays.first { $0.id == row.diagram.playId }
            return Entry(id: row.id,
                         playId: row.diagram.playId,
                         name: row.name,
                         category: play?.category ?? .setPlays,
                         formation: play?.formation ?? "",
                         updatedAt: row.updatedAt,
                         nodeCount: row.diagram.nodeCount)
        }
    }

    private func newPlay() {
        // Save whatever is open before switching, so nothing is lost.
        model.save()
        let diagram = PlayEditorModel.newDiagram()
        model.load(diagram, name: "Untitled Play")
        model.save()
        reload()
    }

    private func open(_ entry: Entry) {
        guard entry.id != model.currentDiagramId else { return }
        model.save()
        guard let stored = dataManager.allPlayDiagrams().first(where: { $0.id == entry.id })
        else { return }
        model.load(stored.diagram, name: stored.name)
    }

    private func beginRename(_ entry: Entry) {
        draftName = entry.name
        renaming = entry
    }

    private func commitRename() {
        guard let entry = renaming else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        if entry.id == model.currentDiagramId {
            model.diagramName = name
            model.save()
        } else if let stored = dataManager.allPlayDiagrams().first(where: { $0.id == entry.id }) {
            dataManager.savePlayDiagram(stored.diagram, name: name)
        }
        reload()
    }

    private func duplicate(_ entry: Entry) {
        guard let stored = dataManager.allPlayDiagrams().first(where: { $0.id == entry.id })
        else { return }
        // New ids for both the diagram and its play, so the copy is genuinely
        // independent rather than aliasing the original's records.
        var copy = stored.diagram
        copy = PlayDiagram(playId: UUID(),
                           space: copy.space,
                           entities: copy.entities,
                           nodes: copy.nodes,
                           rootNodeId: copy.rootNodeId,
                           camera: copy.camera,
                           themeName: copy.themeName)
        dataManager.savePlayDiagram(copy, name: entry.name + " copy")
        reload()
    }

    private func commitDelete() {
        guard let entry = confirmingDelete else { return }
        confirmingDelete = nil
        dataManager.deletePlayDiagram(id: entry.id)
        if entry.id == model.currentDiagramId {
            model.load(PlayEditorModel.newDiagram(), name: "Untitled Play")
        }
        reload()
    }
}
