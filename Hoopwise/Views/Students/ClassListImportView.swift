import SwiftUI
import UniformTypeIdentifiers

// MARK: - Class list (上课名单) import / export — iPhone
//
// October 2026 (Luther's request, the sixth sanctioned exception to the iOS UI
// freeze): every coach keeps an Excel class list; the phone imports it —
// students, balances, classes, calendar — after a preview, and exports the
// same sheet back with live numbers. All decisions live in ClassList
// (Services/ClassListImport.swift, shared with the Mac); this is the screen.

struct ClassListImportView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    /// A file to open without the picker (DEBUG screenshot harness).
    var preloadURL: URL? = nil

    @State private var showingPicker = false
    @State private var fileName: String?
    @State private var sheet: ClassList.Sheet?
    @State private var through = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
    @State private var errorMessage: String?
    @State private var imported: SwiftDataManager.ClassListImportResult?
    @State private var importedSummary: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var plan: ClassList.Plan? {
        guard let sheet else { return nil }
        return ClassList.plan(sheet,
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
        NavigationStack {
            Group {
                if let importedSummary {
                    doneView(importedSummary)
                } else if let plan {
                    preview(plan)
                } else if let errorMessage {
                    ContentUnavailableView(isChinese ? "无法读取" : "Could not read the file",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else {
                    ContentUnavailableView(isChinese ? "选择上课名单" : "Choose a class list",
                                           systemImage: "tablecells",
                                           description: Text(isChinese ? "Excel 文件（.xlsx）" : "An Excel file (.xlsx)"))
                }
            }
            .navigationTitle(isChinese ? "导入上课名单" : "Import Class List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importedSummary == nil ? (isChinese ? "取消" : "Cancel") : (isChinese ? "完成" : "Done")) {
                        dismiss()
                    }
                }
                if importedSummary == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isChinese ? "选择文件" : "Choose File") { showingPicker = true }
                    }
                }
            }
        }
        .onAppear {
            if let preloadURL { load(.success(preloadURL)) } else if sheet == nil { showingPicker = true }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            load(result)
        }
    }

    // MARK: Preview

    private func preview(_ plan: ClassList.Plan) -> some View {
        Form {
            Section {
                summaryRow(isChinese ? "新学员" : "New students", plan.newStudentCount)
                summaryRow(isChinese ? "课时余额" : "Balances", plan.balanceCount)
                summaryRow(isChinese ? "新班级" : "New classes", plan.newClassCount)
                summaryRow(isChinese ? "课程（日历）" : "Sessions on the calendar", plan.sessionCount)
                DatePicker(isChinese ? "排课至" : "Schedule through", selection: $through,
                           in: Date()..., displayedComponents: .date)
            } header: {
                Text(fileName ?? "")
            } footer: {
                Text(isChinese
                     ? "每节课 \(plan.options.durationMinutes) 分钟。按月的余额按每月 4 节（每周一次）换算成课时。阶段可以之后再添加。"
                     : "Classes are \(plan.options.durationMinutes) minutes. Month balances become sessions at 4 a month (one class a week). Phases can be added later.")
            }

            if !plan.issues.isEmpty {
                Section(isChinese ? "请检查" : "Check these") {
                    ForEach(plan.issues) { issue in
                        Label {
                            Text(issue.row.map { (isChinese ? "第 \($0) 行 · " : "Row \($0) · ") } ?? "")
                                .foregroundStyle(.secondary)
                            + Text(issue.message)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.footnote)
                    }
                }
            }

            ForEach(plan.classes) { planned in
                Section {
                    ForEach(planned.studentIds, id: \.self) { id in
                        studentRow(plan.students.first { $0.id == id })
                    }
                } header: {
                    HStack {
                        Text(planned.block.canonicalTitle)
                        Spacer()
                        Text(planned.isNew ? (isChinese ? "新建" : "New") : (isChinese ? "已有" : "Existing"))
                    }
                } footer: {
                    Text(isChinese
                         ? "\(planned.block.coach ?? "未指定教练") · 新增 \(planned.sessionStarts.count) 节课"
                         : "\(planned.block.coach ?? "No coach") · \(planned.sessionStarts.count) sessions added")
                }
            }

            if !plan.withoutClass.isEmpty {
                Section(isChinese ? "无班级（长期不来）" : "No class (long-term absent)") {
                    ForEach(plan.withoutClass, id: \.self) { id in
                        studentRow(plan.students.first { $0.id == id })
                    }
                }
            }

            Section {
                Button {
                    apply(plan)
                } label: {
                    Text(isChinese ? "导入" : "Import")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: Int) -> some View {
        LabeledContent(title) { Text("\(value)").monospacedDigit() }
    }

    @ViewBuilder
    private func studentRow(_ student: ClassList.PlannedStudent?) -> some View {
        if let student {
            HStack {
                Text(student.name)
                if student.isNew {
                    Text(isChinese ? "新" : "New")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(balanceText(student))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func balanceText(_ student: ClassList.PlannedStudent) -> String {
        if let kept = student.keptExistingBalance {
            return isChinese ? "保留 \(kept) 节" : "keeps \(kept)"
        }
        guard let sessions = student.balanceSessions else { return "—" }
        if student.monthsBased, let months = student.monthsLeft {
            return isChinese ? "\(months.formatted()) 月 = \(sessions) 节" : "\(months.formatted()) mo = \(sessions)"
        }
        return isChinese ? "\(sessions) 节" : "\(sessions) sessions"
    }

    // MARK: Done

    private func doneView(_ summary: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(summary)
                .multilineTextAlignment(.center)
            if let imported {
                Button(role: .destructive) {
                    dataManager.undoClassListImport(imported)
                    self.imported = nil
                    importedSummary = nil
                } label: {
                    Label(isChinese ? "撤销这次导入" : "Undo this import", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: Actions

    private func load(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let parsed = ClassList.parse(try XLSX.read(data)) else {
                    errorMessage = isChinese
                        ? "没有找到「课程 · 教练 · 学生」表头。"
                        : "No 课程 · 教练 · 学生 header row was found."
                    return
                }
                fileName = url.lastPathComponent
                sheet = parsed
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ plan: ClassList.Plan) {
        imported = dataManager.applyClassListImport(plan)
        importedSummary = isChinese
            ? "已导入 \(plan.students.count) 名学员、\(plan.classes.count) 个班级、\(plan.sessionCount) 节课。"
            : "Imported \(plan.students.count) students, \(plan.classes.count) classes and \(plan.sessionCount) sessions."
    }
}

/// Writes the class list for the share sheet (WeChat, Files, AirDrop).
enum ClassListExport {
    static func file(dataManager: DataManager) throws -> URL {
        let sheets = ClassList.export(programs: dataManager.programs,
                                      students: dataManager.students,
                                      contracts: dataManager.contracts,
                                      coaches: dataManager.staffCoaches,
                                      accountCoach: (dataManager.coach.id, dataManager.coach.name))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ClassList.exportFilename())
        try XLSX.write(sheets, stylesheet: ClassList.exportStylesheet).write(to: url, options: .atomic)
        return url
    }
}
