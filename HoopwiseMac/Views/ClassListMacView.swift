import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Class list (上课名单) import / export — Mac
//
// Same decisions as the iPhone (ClassList in Services/ClassListImport.swift):
// open the coach's .xlsx, preview what will be created, import, undo; or
// save the sheet back with live numbers.

struct ClassListMacSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var preview: ClassListPreviewItem?
    @State private var message: String?

    var body: some View {
        Section {
            HStack {
                Button("Import Class List (Excel)…") { openSheet() }
                Button("Export Class List (Excel)…") { saveSheet() }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Class list · 上课名单")
        } footer: {
            Text("Classes become programs, students get session balances (months at 4 sessions each), and the calendar fills on each class's weekday.")
        }
        .sheet(item: $preview) { item in
            ClassListMacPreview(sheet: item.sheet, fileName: item.fileName) { summary in
                message = summary
                preview = nil
            }
            .environmentObject(dataManager)
        }
    }

    private func openSheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let sheet = ClassList.parse(try XLSX.read(Data(contentsOf: url))) else {
                message = "No 课程 · 教练 · 学生 header row was found in \(url.lastPathComponent)."
                return
            }
            preview = ClassListPreviewItem(sheet: sheet, fileName: url.lastPathComponent)
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = ClassList.exportFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let sheets = ClassList.export(programs: dataManager.programs,
                                          students: dataManager.students,
                                          contracts: dataManager.contracts,
                                          coaches: dataManager.staffCoaches,
                                          accountCoach: (dataManager.coach.id, dataManager.coach.name))
            try XLSX.write(sheets).write(to: url, options: .atomic)
            message = "Saved \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ClassListPreviewItem: Identifiable {
    let id = UUID()
    let sheet: ClassList.Sheet
    let fileName: String
}

private struct ClassListMacPreview: View {
    @EnvironmentObject var dataManager: DataManager
    let sheet: ClassList.Sheet
    let fileName: String
    let onFinish: (String?) -> Void

    @State private var through = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
    @State private var result: SwiftDataManager.ClassListImportResult?
    @State private var summary: String?

    private var plan: ClassList.Plan {
        ClassList.plan(sheet,
                       students: dataManager.students,
                       contracts: dataManager.contracts,
                       programs: dataManager.programs,
                       sessions: dataManager.sessionEvents,
                       coaches: dataManager.staffCoaches,
                       accountCoach: (dataManager.coach.id, dataManager.coach.name),
                       options: ClassList.Options(from: Calendar.current.startOfDay(for: Date()),
                                                  through: through))
    }

    var body: some View {
        let plan = plan
        VStack(alignment: .leading, spacing: 12) {
            Text("Import \(fileName)").font(.headline)
            if let summary {
                Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("New students"); Text("\(plan.newStudentCount)").monospacedDigit() }
                    GridRow { Text("Balances"); Text("\(plan.balanceCount)").monospacedDigit() }
                    GridRow { Text("New classes"); Text("\(plan.newClassCount)").monospacedDigit() }
                    GridRow { Text("Sessions on the calendar"); Text("\(plan.sessionCount)").monospacedDigit() }
                }
                DatePicker("Schedule through", selection: $through, in: Date()..., displayedComponents: .date)
                    .fixedSize()
            }
            List {
                if !plan.issues.isEmpty && summary == nil {
                    Section("Check these") {
                        ForEach(plan.issues) { issue in
                            Text((issue.row.map { "Row \($0) · " } ?? "") + issue.message)
                                .font(.callout)
                        }
                    }
                }
                ForEach(plan.classes) { planned in
                    Section("\(planned.block.canonicalTitle) · \(planned.block.coach ?? "no coach") · \(planned.isNew ? "new" : "existing") · \(planned.sessionStarts.count) sessions") {
                        ForEach(planned.studentIds, id: \.self) { id in
                            if let student = plan.students.first(where: { $0.id == id }) {
                                HStack {
                                    Text(student.name)
                                    Spacer()
                                    Text(balanceText(student)).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 320)
            HStack {
                if let result {
                    Button("Undo this import", role: .destructive) {
                        dataManager.undoClassListImport(result)
                        self.result = nil
                        summary = nil
                    }
                }
                Spacer()
                Button(summary == nil ? "Cancel" : "Done") { onFinish(summary) }
                    .keyboardShortcut(.cancelAction)
                if summary == nil {
                    Button("Import") {
                        result = dataManager.applyClassListImport(plan)
                        summary = "Imported \(plan.students.count) students, \(plan.classes.count) classes and \(plan.sessionCount) sessions."
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func balanceText(_ student: ClassList.PlannedStudent) -> String {
        if let kept = student.keptExistingBalance { return "keeps \(kept)" }
        guard let sessions = student.balanceSessions else { return "—" }
        if student.monthsBased, let months = student.monthsLeft {
            return "\(months.formatted()) mo = \(sessions)"
        }
        return "\(sessions) sessions"
    }
}
