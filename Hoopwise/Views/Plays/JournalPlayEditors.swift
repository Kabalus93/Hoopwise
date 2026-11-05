import SwiftData
import SwiftUI

/// A new play: its name, when it's run and on which court. It starts with
/// five players in the default alignment, ready to draw.
struct JournalNewPlaySheet: View {
    let created: (JournalPlay) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var category = JournalPlayCategory.halfCourt
    @State private var court = JournalCourtKind.half
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $name) { JText("Name, like “Horns” or “Box”") }
                        .focused($nameFocused)
                        .submitLabel(.done)
                }
                Section {
                    JournalPlayCategoryPicker(selection: $category)
                    JournalPlayCourtPicker(selection: $court)
                } footer: {
                    JText("It starts five out, ready for you to draw the first step.")
                }
            }
            .navigationTitle(JText("New play"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { JText("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let play = JournalPlay.create(name: trimmed, category: category, court: court, in: context)
                        try? context.save()
                        dismiss()
                        created(play)
                    } label: {
                        JText("Create")
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A play's name, when it's run, the court, the idea and the source.
struct JournalPlayDetailsSheet: View {
    @Bindable var play: JournalPlay

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $play.name) { JText("Name") }
                    JournalPlayCategoryPicker(selection: $play.category)
                    JournalPlayCourtPicker(selection: Binding(get: { play.court }, set: { play.changeCourt(to: $0) }))
                } footer: {
                    JText("Changing the court turns every step's drawing to the new court.")
                }
                Section {
                    TextField(text: $play.situation, axis: .vertical) { JText("When you run it") }
                        .lineLimit(1...4)
                } header: {
                    JText("When")
                }
                Section {
                    TextField(text: $play.concept, axis: .vertical) { JText("The idea, and each player's job") }
                        .lineLimit(3...10)
                } header: {
                    JText("The idea")
                }
                Section {
                    TextField(text: $play.source) { JText("Where it comes from") }
                    TextField(text: Binding(get: { play.sourceURL ?? "" },
                                            set: { play.sourceURL = $0.isEmpty ? nil : $0 })) {
                        JText("Link")
                    }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    JText("Source")
                }
            }
            .navigationTitle(JText("Play details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { JText("Done") }
                }
            }
        }
    }
}

/// A wrinkle or variation's name and what it changes; new or renamed.
struct JournalPlayPartSheet: View {
    enum Mode {
        case add(JournalPlay, JournalPlayPartKind)
        case edit(JournalPlayPart)
    }

    let mode: Mode
    var added: (JournalPlayPart) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var notes: String

    init(mode: Mode, added: @escaping (JournalPlayPart) -> Void = { _ in }) {
        self.mode = mode
        self.added = added
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
        case .edit(let part):
            _name = State(initialValue: part.name)
            _notes = State(initialValue: part.notes)
        }
    }

    private var kind: JournalPlayPartKind {
        switch mode {
        case .add(_, let kind): kind
        case .edit(let part): part.kind
        }
    }

    private var title: Text {
        switch mode {
        case .add(_, .wrinkle): JText("New wrinkle")
        case .add: JText("New variation")
        case .edit: JText("Rename")
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $name) { JText("Name, like “Twist” or “Horns Down”") }
                    if kind != .concept {
                        TextField(text: $notes, axis: .vertical) { JText("What it changes, in one line") }
                            .lineLimit(1...3)
                    }
                } footer: {
                    if case .add = mode {
                        JText("Its first step starts from the concept's set.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { JText("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { JText("Done") }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .add(let play, let kind):
            let part = play.addPart(kind, name: trimmed, in: context)
            part.notes = notes
            try? context.save()
            dismiss()
            added(part)
        case .edit(let part):
            part.name = trimmed
            part.notes = notes
            try? context.save()
            dismiss()
        }
    }
}

struct JournalPlayCategoryPicker: View {
    @Binding var selection: JournalPlayCategory

    var body: some View {
        Picker(selection: $selection) {
            ForEach(JournalPlayCategory.allCases) { category in
                JText(category.label).tag(category)
            }
        } label: {
            JText("Category")
        }
    }
}

struct JournalPlayCourtPicker: View {
    @Binding var selection: JournalCourtKind

    var body: some View {
        Picker(selection: $selection) {
            ForEach(JournalCourtKind.allCases) { court in
                JText(court.label).tag(court)
            }
        } label: {
            JText("Court")
        }
    }
}
