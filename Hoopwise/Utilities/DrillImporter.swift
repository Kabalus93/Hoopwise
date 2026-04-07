import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drill Import Data Structures
struct DrillImportFile: Codable {
    let drills: [DrillImportItem]
}

struct DrillImportItem: Codable {
    let name: String
    let category: String
    let difficulty: String
    let durationMinutes: Int
    let description: String
    let instructions: [String]?
    let keyPoints: [String]?
    let equipmentNeeded: [String]?
    let minPlayers: Int?
    let maxPlayers: Int?
    let variations: [String]?
    let videoUrl: String?
    let tags: [String]?
    
    func toDrillItem() -> DrillItem? {
        guard let category = DrillCategory(rawValue: category.lowercased()),
              let difficulty = DifficultyLevel(rawValue: difficulty.lowercased()) else {
            return nil
        }
        
        return DrillItem(
            name: name,
            category: category,
            difficulty: difficulty,
            durationMinutes: durationMinutes,
            description: description,
            instructions: instructions ?? [],
            keyPoints: keyPoints ?? [],
            equipmentNeeded: equipmentNeeded ?? [],
            minPlayers: minPlayers ?? 1,
            maxPlayers: maxPlayers,
            variations: variations ?? [],
            videoUrl: videoUrl,
            tags: tags ?? []
        )
    }
}

// MARK: - Drill Importer
class DrillImporter {
    
    enum ImportError: LocalizedError {
        case invalidFile
        case parsingError(String)
        case noValidDrills
        
        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected file is not a valid drill import file."
            case .parsingError(let message):
                return "Failed to parse drills: \(message)"
            case .noValidDrills:
                return "No valid drills found in the import file."
            }
        }
    }
    
    struct ImportResult {
        let successCount: Int
        let failedCount: Int
        let drills: [DrillItem]
        let errors: [String]
    }
    
    /// Import drills from JSON data
    static func importDrills(from data: Data) -> Result<ImportResult, ImportError> {
        let decoder = JSONDecoder()
        
        do {
            let importFile = try decoder.decode(DrillImportFile.self, from: data)
            
            var drills: [DrillItem] = []
            var errors: [String] = []
            
            for (index, importItem) in importFile.drills.enumerated() {
                if let drill = importItem.toDrillItem() {
                    drills.append(drill)
                } else {
                    errors.append("Drill #\(index + 1) '\(importItem.name)': Invalid category '\(importItem.category)' or difficulty '\(importItem.difficulty)'")
                }
            }
            
            if drills.isEmpty {
                return .failure(.noValidDrills)
            }
            
            return .success(ImportResult(
                successCount: drills.count,
                failedCount: errors.count,
                drills: drills,
                errors: errors
            ))
            
        } catch let decodingError as DecodingError {
            let message: String
            switch decodingError {
            case .keyNotFound(let key, _):
                message = "Missing required field: \(key.stringValue)"
            case .typeMismatch(_, let context):
                message = "Type mismatch at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .valueNotFound(_, let context):
                message = "Value not found at: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .dataCorrupted(let context):
                message = "Data corrupted: \(context.debugDescription)"
            @unknown default:
                message = decodingError.localizedDescription
            }
            return .failure(.parsingError(message))
        } catch {
            return .failure(.parsingError(error.localizedDescription))
        }
    }
    
    /// Import drills from a file URL
    static func importDrills(from url: URL) -> Result<ImportResult, ImportError> {
        do {
            let data = try Data(contentsOf: url)
            return importDrills(from: data)
        } catch {
            return .failure(.invalidFile)
        }
    }
    
    /// Export drills to JSON data
    static func exportDrills(_ drills: [DrillItem]) -> Data? {
        let exportItems = drills.map { drill in
            DrillImportItem(
                name: drill.name,
                category: drill.category.rawValue,
                difficulty: drill.difficulty.rawValue,
                durationMinutes: drill.durationMinutes,
                description: drill.description,
                instructions: drill.instructions,
                keyPoints: drill.keyPoints,
                equipmentNeeded: drill.equipmentNeeded,
                minPlayers: drill.minPlayers,
                maxPlayers: drill.maxPlayers,
                variations: drill.variations,
                videoUrl: drill.videoUrl,
                tags: drill.tags
            )
        }
        
        let exportFile = DrillImportFile(drills: exportItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try? encoder.encode(exportFile)
    }
}

#if os(iOS)
// MARK: - Document Picker for Drill Import
struct DrillImportDocumentPicker: UIViewControllerRepresentable {
    let onImport: (Result<DrillImporter.ImportResult, DrillImporter.ImportError>) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImport: onImport)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onImport: (Result<DrillImporter.ImportResult, DrillImporter.ImportError>) -> Void
        
        init(onImport: @escaping (Result<DrillImporter.ImportResult, DrillImporter.ImportError>) -> Void) {
            self.onImport = onImport
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onImport(.failure(.invalidFile))
                return
            }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                onImport(.failure(.invalidFile))
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            let result = DrillImporter.importDrills(from: url)
            onImport(result)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - no action needed
        }
    }
}

#endif

// MARK: - Import Drills View
struct ImportDrillsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var showingFilePicker = false
    @State private var importResult: DrillImporter.ImportResult?
    @State private var importError: DrillImporter.ImportError?
    @State private var showingResult = false
    @State private var isImporting = false
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header illustration
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text(isChinese ? "导入训练" : "Import Drills")
                        .font(.title2.bold())
                    
                    Text(isChinese ? "从JSON文件导入训练到你的库中" : "Import drills from a JSON file into your library")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    instructionRow(number: 1, text: isChinese ? "准备一个符合模板格式的JSON文件" : "Prepare a JSON file matching the template format")
                    instructionRow(number: 2, text: isChinese ? "点击下方按钮选择文件" : "Tap the button below to select your file")
                    instructionRow(number: 3, text: isChinese ? "确认导入训练到你的库中" : "Confirm to import drills into your library")
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                
                Spacer()
                
                // Import button
                Button(action: { showingFilePicker = true }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(isChinese ? "选择JSON文件" : "Select JSON File")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isImporting)
                
                // Template hint
                Text(isChinese ? "需要模板? 查看项目根目录的 DrillImportTemplate.json" : "Need a template? Check DrillImportTemplate.json in the project root")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(isChinese ? "导入训练" : "Import Drills")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingFilePicker) {
                DrillImportDocumentPicker { result in
                    handleImportResult(result)
                }
            }
            #endif
            .alert(isChinese ? "导入结果" : "Import Result", isPresented: $showingResult) {
                Button("OK") {
                    if importResult != nil && importError == nil {
                        dismiss()
                    }
                }
            } message: {
                if let result = importResult {
                    Text(isChinese ?
                         "成功导入 \(result.successCount) 个训练\(result.failedCount > 0 ? "\n\(result.failedCount) 个失败" : "")" :
                         "Successfully imported \(result.successCount) drills\(result.failedCount > 0 ? "\n\(result.failedCount) failed" : "")")
                } else if let error = importError {
                    Text(error.localizedDescription)
                }
            }
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    private func handleImportResult(_ result: Result<DrillImporter.ImportResult, DrillImporter.ImportError>) {
        switch result {
        case .success(let importResult):
            self.importResult = importResult
            self.importError = nil
            
            // Add drills to data manager
            for drill in importResult.drills {
                dataManager.addDrill(drill)
            }
            
            HapticFeedback.notification(.success)
            
        case .failure(let error):
            self.importResult = nil
            self.importError = error
            HapticFeedback.notification(.error)
        }
        
        showingResult = true
    }
}
