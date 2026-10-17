import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bundle Format
/// Versioned wire format for sharing student data between Hoopwise installs.
/// Every per-student entity travels with the student so the recipient gets
/// a complete record, including profile photo bytes (Data is base64 in JSON).
struct StudentTransferBundle: Codable {
    static let currentSchemaVersion = 1
    static let fileExtension = "hoopwise"

    let schemaVersion: Int
    let exportedAt: Date
    let exportedBy: String?
    let students: [Student]
    let players: [Player]
    let contracts: [Contract]
    let measurements: [PlayerMeasurement]
    let auditEntries: [ProfileAuditEntry]
}

// MARK: - Transferable file wrapper
private struct TransferDocument: Transferable {
    let data: Data
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.suggestedName }
    }
}

// MARK: - Entry View
struct StudentTransferView: View {
    enum Mode: String, Identifiable, Hashable {
        case export, importing
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    var initialMode: Mode = .export

    @State private var mode: Mode = .export

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .export:    TransferExportView()
                case .importing: TransferImportView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        Text("Export").tag(Mode.export)
                        Text("Import").tag(Mode.importing)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
        .onAppear { mode = initialMode }
    }
}

// MARK: - Export
private struct TransferExportView: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var selectedIds: Set<UUID> = []
    @State private var searchText = ""

    private var sortedStudents: [Student] {
        dataManager.students.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredStudents: [Student] {
        guard !searchText.isEmpty else { return sortedStudents }
        return sortedStudents.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.chineseName ?? "").localizedStandardContains(searchText)
        }
    }

    private var selectedStudents: [Student] {
        sortedStudents.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Button {
                        if selectedIds.count == sortedStudents.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(sortedStudents.map(\.id))
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedIds.count == sortedStudents.count
                                  ? "checkmark.square.fill"
                                  : "square")
                                .foregroundStyle(Color.accentColor)
                            Text(selectedIds.count == sortedStudents.count ? "Deselect all" : "Select all")
                            Spacer()
                            Text("\(selectedIds.count) of \(sortedStudents.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    ForEach(filteredStudents) { student in
                        Button {
                            if selectedIds.contains(student.id) { selectedIds.remove(student.id) }
                            else { selectedIds.insert(student.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIds.contains(student.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(selectedIds.contains(student.id) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.primaryDisplayName).foregroundStyle(.primary)
                                    if let cn = student.secondaryNameLine {
                                        Text(cn).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Students")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search")

            shareBar
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayModeCompat(.inline)
    }

    private var shareBar: some View {
        VStack(spacing: 8) {
            if let doc = buildDocument() {
                ShareLink(item: doc, preview: SharePreview(doc.suggestedName, image: Image(systemName: "doc.fill"))) {
                    Label("Share \(selectedIds.count) student\(selectedIds.count == 1 ? "" : "s")",
                          systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedIds.isEmpty)
            } else {
                Label("Select students to share", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footerText: String {
        guard !selectedIds.isEmpty else {
            return "Pick at least one student to export. Profile photos and history are included."
        }
        let bundleSummary = countSummary(for: selectedStudents)
        return "Includes \(bundleSummary). Recipient opens the file in Hoopwise → Import."
    }

    private func countSummary(for students: [Student]) -> String {
        let ids = Set(students.map(\.id))
        let players = dataManager.players.filter { ids.contains($0.studentId) }.count
        let contracts = dataManager.contracts.filter { ids.contains($0.studentId) }.count
        let measurements = dataManager.measurements.filter { ids.contains($0.studentId) }.count
        var parts: [String] = ["\(students.count) student\(students.count == 1 ? "" : "s")"]
        if players > 0 { parts.append("\(players) profile\(players == 1 ? "" : "s")") }
        if contracts > 0 { parts.append("\(contracts) contract\(contracts == 1 ? "" : "s")") }
        if measurements > 0 { parts.append("\(measurements) measurement\(measurements == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    private func buildDocument() -> TransferDocument? {
        guard !selectedIds.isEmpty else { return nil }
        let chosen = sortedStudents.filter { selectedIds.contains($0.id) }
        let chosenIds = Set(chosen.map(\.id))
        let bundle = StudentTransferBundle(
            schemaVersion: StudentTransferBundle.currentSchemaVersion,
            exportedAt: Date(),
            exportedBy: dataManager.coach.name,
            students: chosen,
            players: dataManager.players.filter { chosenIds.contains($0.studentId) },
            contracts: dataManager.contracts.filter { chosenIds.contains($0.studentId) },
            measurements: dataManager.measurements.filter { chosenIds.contains($0.studentId) },
            auditEntries: chosen.flatMap { AuditLogger.shared.entries(for: $0.id) }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bundle) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let name = "Hoopwise-Students-\(stamp).\(StudentTransferBundle.fileExtension).json"
        return TransferDocument(data: data, suggestedName: name)
    }
}

// MARK: - Import
private struct TransferImportView: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var bundle: StudentTransferBundle?
    @State private var sourceURL: URL?
    @State private var pickerVisible = false
    @State private var errorMessage: String?
    @State private var importResult: ImportResult?

    struct ImportResult {
        var added: Int
        var skipped: Int
    }

    var body: some View {
        Group {
            if let result = importResult {
                completedView(result: result)
            } else if let bundle {
                previewView(bundle: bundle)
            } else {
                pickerPrompt
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayModeCompat(.inline)
        .fileImporter(
            isPresented: $pickerVisible,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                load(from: url)
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }

    private var pickerPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Choose a Hoopwise export file")
                .font(.headline)
            Text("The recipient app will skip any student that already exists by ID, so re-importing is safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                pickerVisible = true
            } label: {
                Label("Choose File", systemImage: "folder")
                    .frame(maxWidth: 260)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func previewView(bundle: StudentTransferBundle) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    summaryRow("Schema", "v\(bundle.schemaVersion)")
                    summaryRow("Exported", bundle.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    if let by = bundle.exportedBy { summaryRow("From", by) }
                }
                Section {
                    summaryRow("Students", "\(bundle.students.count)")
                    summaryRow("Profiles", "\(bundle.players.count)")
                    summaryRow("Contracts", "\(bundle.contracts.count)")
                    summaryRow("Measurements", "\(bundle.measurements.count)")
                    summaryRow("Audit entries", "\(bundle.auditEntries.count)")
                }
                Section("Will be imported") {
                    let collisions = bundle.students.filter { incoming in
                        dataManager.students.contains(where: { $0.id == incoming.id })
                    }
                    if !collisions.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("\(collisions.count) already exist on this device — they'll be skipped.")
                                .font(.subheadline)
                        }
                    }
                    ForEach(bundle.students.prefix(20)) { s in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.primaryDisplayName)
                                if let cn = s.secondaryNameLine {
                                    Text(cn).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if bundle.students.count > 20 {
                        Text("and \(bundle.students.count - 20) more")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    self.bundle = nil
                    self.sourceURL = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    performImport(bundle: bundle)
                } label: {
                    Label("Import", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func completedView(result: ImportResult) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Imported \(result.added) student\(result.added == 1 ? "" : "s")")
                .font(.headline)
            if result.skipped > 0 {
                Text("\(result.skipped) skipped (already on this device)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Done") {
                bundle = nil
                sourceURL = nil
                importResult = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func load(from url: URL) {
        // Security-scoped resource is needed for files chosen via fileImporter.
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let parsed = try decoder.decode(StudentTransferBundle.self, from: data)
            guard parsed.schemaVersion <= StudentTransferBundle.currentSchemaVersion else {
                errorMessage = "This file was exported by a newer version of Hoopwise."
                return
            }
            bundle = parsed
            sourceURL = url
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't read this file. It may be corrupted or not a Hoopwise export."
        }
    }

    private func performImport(bundle: StudentTransferBundle) {
        let existingStudentIds = Set(dataManager.students.map(\.id))
        let existingPlayerIds = Set(dataManager.players.map(\.id))
        let existingContractIds = Set(dataManager.contracts.map(\.id))
        let existingMeasurementIds = Set(dataManager.measurements.map(\.id))

        var added = 0
        var skipped = 0

        for student in bundle.students {
            if existingStudentIds.contains(student.id) {
                skipped += 1
                continue
            }
            let pairedPlayer = bundle.players.first(where: { $0.studentId == student.id })
            dataManager.addStudent(student, player: pairedPlayer)
            added += 1
        }

        // Players that weren't paired with a student already-added (e.g., the
        // student was skipped). Add any additional players that aren't yet on device.
        for player in bundle.players where !existingPlayerIds.contains(player.id) {
            // If we already added the student with this player above, addStudent
            // already inserted the player; skip duplicates by id.
            if dataManager.players.contains(where: { $0.id == player.id }) { continue }
            dataManager.addPlayer(player)
        }

        for contract in bundle.contracts where !existingContractIds.contains(contract.id) {
            dataManager.addContract(contract)
        }

        for m in bundle.measurements where !existingMeasurementIds.contains(m.id) {
            dataManager.addMeasurement(m)
        }

        importResult = ImportResult(added: added, skipped: skipped)
    }
}
