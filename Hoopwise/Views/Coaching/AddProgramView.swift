import SwiftUI

// MARK: - Add Program View (Recreated)
struct AddProgramView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name = ""
    @State private var description = ""
    @State private var colorHex = "#3B82F6"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Program Details") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description)
                }
            }
            .navigationTitle("New Program")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Student Picker View
struct StudentPickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedIds: Set<UUID>
    var ageGroup: AgeGroup? = nil
    
    var filteredStudents: [Student] {
        if let ageGroup = ageGroup {
            return dataManager.students.filter { $0.ageGroup == ageGroup }
        }
        return dataManager.students
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredStudents) { student in
                    HStack {
                        Text(student.name)
                        Spacer()
                        if selectedIds.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIds.contains(student.id) {
                            selectedIds.remove(student.id)
                        } else {
                            selectedIds.insert(student.id)
                        }
                    }
                }
            }
            .navigationTitle("Select Students")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit Enrolled Students View
struct EditEnrolledStudentsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var program: Program
    @Binding var selectedIds: Set<UUID>
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(dataManager.students) { student in
                    HStack {
                        Text(student.name)
                        Spacer()
                        if selectedIds.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIds.contains(student.id) {
                            selectedIds.remove(student.id)
                        } else {
                            selectedIds.insert(student.id)
                        }
                    }
                }
            }
            .navigationTitle("Edit Enrolled Students")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updatedProgram = program
                        updatedProgram.enrolledStudentIds = Array(selectedIds)
                        dataManager.updateProgram(updatedProgram)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add Phase View
struct AddPhaseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    let nextPhaseNumber: Int
    
    @State private var name = ""
    @State private var focus = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Phase Details") {
                    TextField("Name", text: $name)
                    TextField("Focus", text: $focus)
                }
            }
            .navigationTitle("New Phase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let phase = MicroCycle(
                            id: UUID(),
                            programId: program.id,
                            phaseNumber: nextPhaseNumber,
                            title: name.isEmpty ? "Phase \(nextPhaseNumber)" : name,
                            focus: [],
                            durationWeeks: 1,
                            description: focus.isEmpty ? nil : focus,
                            objectives: [],
                            startDate: Date(),
                            endDate: Date().addingTimeInterval(7 * 24 * 3600),
                            intensity: 5,
                            volume: 5,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        dataManager.addMicroCycle(phase)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Edit Program View
struct EditProgramView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var program: Program
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Name", text: $program.name)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                TextField("Description", text: Binding(
                    get: { program.description ?? "" },
                    set: { program.description = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Edit Program")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dataManager.updateProgram(program)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - MicroCycle Detail View
struct MicroCycleDetailView: View {
    let microCycle: MicroCycle
    let program: Program
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(microCycle.title)
                    .font(.title)
                Text(microCycle.description ?? "")
                    .foregroundColor(.secondary)
                
                if let startDate = microCycle.startDate, let endDate = microCycle.endDate {
                    HStack {
                        Text("Duration:")
                            .foregroundColor(.secondary)
                        Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(microCycle.title)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}
