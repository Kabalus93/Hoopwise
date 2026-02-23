import SwiftUI
import UniformTypeIdentifiers

// MARK: - Student Import View
// Supports CSV import with Chinese column mapping (姓名, 联系方式, 金额, 课程类别, 销售)

#if os(macOS)
// MARK: - Validation Status
enum ImportValidationStatus {
    case valid
    case warning(String)
    case error(String)
    
    var isValid: Bool {
        if case .error = self { return false }
        return true
    }
    
    var color: Color {
        switch self {
        case .valid: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .valid: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var message: String? {
        switch self {
        case .valid: return nil
        case .warning(let msg), .error(let msg): return msg
        }
    }
}

// MARK: - Imported Student Row (Enhanced with Chinese Schema)
struct ImportedStudentData: Identifiable {
    let id = UUID()
    var studentName: String              // 姓名 (Xingming)
    var parentPhone: String?             // 联系方式 (Lianxi fangshi)
    var contractAmount: Double?          // 金额 (Jin'e)
    var contractAmountRaw: String?       // Original string for display
    var contractType: String?            // 课程类别 (Kecheng leibie)
    var enrollingCoach: String?          // 销售 (Xiaoshou)
    var isSelected: Bool = true
    
    // Validation statuses
    var nameValidation: ImportValidationStatus = .valid
    var phoneValidation: ImportValidationStatus = .valid
    var amountValidation: ImportValidationStatus = .valid
    var coachValidation: ImportValidationStatus = .valid
    
    var hasErrors: Bool {
        !nameValidation.isValid || !phoneValidation.isValid || !amountValidation.isValid
    }
    
    var hasWarnings: Bool {
        if case .warning = nameValidation { return true }
        if case .warning = phoneValidation { return true }
        if case .warning = amountValidation { return true }
        if case .warning = coachValidation { return true }
        return false
    }
}

// MARK: - CSV Parser with Multi-Encoding Support
struct EnhancedCSVParser {
    // Try multiple encodings for Chinese file support (UTF-8, GBK, GB2312)
    static func parse(from url: URL) throws -> [[String]] {
        // Try UTF-8 first (most common)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return parse(content: content)
        }
        
        // Try GBK/GB18030 (common Chinese encoding from Excel)
        let cfEncodingGB18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let gb18030Encoding = String.Encoding(rawValue: cfEncodingGB18030)
        if let content = try? String(contentsOf: url, encoding: gb18030Encoding) {
            return parse(content: content)
        }
        
        // Try GB2312
        let cfEncodingGB2312 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))
        let gb2312Encoding = String.Encoding(rawValue: cfEncodingGB2312)
        if let content = try? String(contentsOf: url, encoding: gb2312Encoding) {
            return parse(content: content)
        }
        
        // Try macOS Roman as last resort
        if let content = try? String(contentsOf: url, encoding: .macOSRoman) {
            return parse(content: content)
        }
        
        throw NSError(domain: "CSVParser", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "无法读取文件。请确保文件使用UTF-8或GBK编码。\nUnable to read file. Please ensure the file uses UTF-8 or GBK encoding."
        ])
    }
    
    static func parse(content: String) -> [[String]] {
        var rows: [[String]] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Handle CSV with quotes and Chinese characters
            var columns: [String] = []
            var currentColumn = ""
            var insideQuotes = false
            
            for char in trimmed {
                if char == "\"" {
                    insideQuotes.toggle()
                } else if char == "," && !insideQuotes {
                    columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
                    currentColumn = ""
                } else {
                    currentColumn.append(char)
                }
            }
            columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
            
            // Only add rows that have at least one non-empty column
            if columns.contains(where: { !$0.isEmpty }) {
                rows.append(columns)
            }
        }
        
        return rows
    }
}

// MARK: - Validation Helpers
struct StudentImportValidation {
    // Chinese mobile phone: 11 digits starting with 1
    static func validateChinesePhone(_ phone: String?) -> ImportValidationStatus {
        guard let phone = phone, !phone.isEmpty else {
            return .warning("未提供电话 (No phone)")
        }
        
        // Remove common separators and country code
        let cleaned = phone
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+86", with: "")
            .replacingOccurrences(of: "86", with: "", options: .anchored)
        
        // Check if all digits
        guard cleaned.allSatisfy({ $0.isNumber }) else {
            return .error("电话包含非数字字符 (Non-numeric characters)")
        }
        
        // Check length (11 digits for Chinese mobile)
        if cleaned.count == 11 && cleaned.hasPrefix("1") {
            return .valid
        } else if cleaned.count >= 7 && cleaned.count <= 12 {
            return .warning("电话格式可能不正确 (Format may be incorrect)")
        } else {
            return .error("电话号码长度无效 (Invalid length)")
        }
    }
    
    // Amount validation - parse as numeric/decimal
    static func validateAndParseAmount(_ amountStr: String?) -> (ImportValidationStatus, Double?) {
        guard let amountStr = amountStr, !amountStr.isEmpty else {
            return (.warning("未提供金额 (No amount)"), nil)
        }
        
        // Remove currency symbols, whitespace, and thousand separators
        let cleaned = amountStr
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if let amount = Double(cleaned) {
            if amount > 0 {
                return (.valid, amount)
            } else if amount == 0 {
                return (.warning("金额为零 (Amount is zero)"), amount)
            } else {
                return (.warning("金额为负数 (Negative amount)"), amount)
            }
        } else {
            return (.error("无法解析金额 (Cannot parse amount)"), nil)
        }
    }
    
    // Name validation
    static func validateName(_ name: String?) -> ImportValidationStatus {
        guard let name = name, !name.isEmpty else {
            return .error("姓名必填 (Name required)")
        }
        
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            return .warning("姓名太短 (Name too short)")
        }
        
        return .valid
    }
    
    // Coach validation - check if exists in system
    static func validateCoach(_ coachName: String?, existingCoaches: [String]) -> ImportValidationStatus {
        guard let coachName = coachName, !coachName.isEmpty else {
            return .warning("未指定销售 (No coach specified)")
        }
        
        let trimmed = coachName.trimmingCharacters(in: .whitespaces)
        if existingCoaches.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) || trimmed.localizedCaseInsensitiveContains($0) }) {
            return .valid
        } else {
            return .warning("销售不存在，将创建新记录 (Coach not found, will create)")
        }
    }
}

// MARK: - Column Mapping
struct ColumnMapping {
    var nameIndex: Int = 0           // 姓名
    var phoneIndex: Int? = nil       // 联系方式
    var amountIndex: Int? = nil      // 金额
    var typeIndex: Int? = nil        // 课程类别
    var coachIndex: Int? = nil       // 销售
    
    // Chinese column name patterns for auto-detection
    static let namePatterns = ["姓名", "name", "学生", "student", "名字"]
    static let phonePatterns = ["联系方式", "电话", "phone", "contact", "手机", "微信", "wechat"]
    static let amountPatterns = ["金额", "amount", "价格", "price", "费用", "cost"]
    static let typePatterns = ["课程类别", "课程", "type", "class", "类别", "套餐"]
    static let coachPatterns = ["销售", "coach", "教练", "顾问", "sales"]
    
    static func autoDetect(from headers: [String]) -> ColumnMapping {
        var mapping = ColumnMapping()
        
        for (idx, header) in headers.enumerated() {
            let lower = header.lowercased()
            let headerTrimmed = header.trimmingCharacters(in: .whitespaces)
            
            // Check name patterns
            if namePatterns.contains(where: { headerTrimmed.contains($0) || lower.contains($0.lowercased()) }) {
                mapping.nameIndex = idx
            }
            // Check phone patterns
            else if phonePatterns.contains(where: { headerTrimmed.contains($0) || lower.contains($0.lowercased()) }) {
                mapping.phoneIndex = idx
            }
            // Check amount patterns
            else if amountPatterns.contains(where: { headerTrimmed.contains($0) || lower.contains($0.lowercased()) }) {
                mapping.amountIndex = idx
            }
            // Check type patterns
            else if typePatterns.contains(where: { headerTrimmed.contains($0) || lower.contains($0.lowercased()) }) {
                mapping.typeIndex = idx
            }
            // Check coach patterns
            else if coachPatterns.contains(where: { headerTrimmed.contains($0) || lower.contains($0.lowercased()) }) {
                mapping.coachIndex = idx
            }
        }
        
        return mapping
    }
}

// MARK: - Enhanced Student Import View (macOS)
struct StudentImportViewMac: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    // Data
    @State private var rawRows: [[String]] = []
    @State private var importedStudents: [ImportedStudentData] = []
    @State private var detectedColumns: [String] = []
    @State private var columnMapping = ColumnMapping()
    
    // UI State
    @State private var isFilePickerPresented = false
    @State private var hasHeaderRow = true
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var isProcessing = false
    @State private var importComplete = false
    @State private var importedCount = 0
    @State private var currentStep: ImportStep = .selectFile
    
    // Coach handling
    @State private var createMissingCoaches = true
    
    enum ImportStep {
        case selectFile
        case mapColumns
        case preview
    }
    
    var selectedCount: Int {
        importedStudents.filter { $0.isSelected }.count
    }
    
    var validCount: Int {
        importedStudents.filter { $0.isSelected && !$0.hasErrors }.count
    }
    
    var errorCount: Int {
        importedStudents.filter { $0.hasErrors }.count
    }
    
    var warningCount: Int {
        importedStudents.filter { $0.hasWarnings && !$0.hasErrors }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            importHeader
            
            Divider()
            
            // Step indicator
            stepIndicator
            
            Divider()
            
            // Content based on step
            switch currentStep {
            case .selectFile:
                fileSelectionView
            case .mapColumns:
                columnMappingView
            case .preview:
                previewView
            }
            
            Divider()
            
            // Footer
            importFooter
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(AppTheme.background)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("导入错误 Import Error", isPresented: $showingImportError) {
            Button("OK") { }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("导入完成 Import Complete", isPresented: $importComplete) {
            Button("完成 Done") { dismiss() }
        } message: {
            Text("成功导入 \(importedCount) 名学生。\nSuccessfully imported \(importedCount) student(s).")
        }
    }
    
    // MARK: - Header
    private var importHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("导入学生 Import Students")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("从CSV或Excel文件导入 Import from CSV/Excel")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
    
    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            stepItem(number: 1, title: "选择文件", subtitle: "Select File", isActive: currentStep == .selectFile, isComplete: currentStep != .selectFile)
            
            Rectangle()
                .fill(currentStep != .selectFile ? AppTheme.accentColor : AppTheme.surfaceColor)
                .frame(height: 2)
                .frame(maxWidth: 60)
            
            stepItem(number: 2, title: "映射列", subtitle: "Map Columns", isActive: currentStep == .mapColumns, isComplete: currentStep == .preview)
            
            Rectangle()
                .fill(currentStep == .preview ? AppTheme.accentColor : AppTheme.surfaceColor)
                .frame(height: 2)
                .frame(maxWidth: 60)
            
            stepItem(number: 3, title: "预览确认", subtitle: "Preview", isActive: currentStep == .preview, isComplete: false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
    }
    
    private func stepItem(number: Int, title: String, subtitle: String, isActive: Bool, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isActive ? AppTheme.accentColor : (isComplete ? AppTheme.accentColor.opacity(0.3) : AppTheme.surfaceColor))
                    .frame(width: 28, height: 28)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isActive ? .white : AppTheme.textTertiary)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textTertiary)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }
    
    // MARK: - File Selection View
    private var fileSelectionView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.accentColor.opacity(0.6))
            
            Text("选择要导入的文件")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            Text("Select a file to import")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
            
            Button(action: { isFilePickerPresented = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                    Text("选择文件 Choose File")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // Expected format info
            VStack(alignment: .leading, spacing: 12) {
                Text("期望的CSV格式 Expected Format:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    formatRow(chinese: "姓名", english: "Name", required: true)
                    formatRow(chinese: "联系方式", english: "Phone", required: false)
                    formatRow(chinese: "金额", english: "Amount", required: false)
                    formatRow(chinese: "课程类别", english: "Class Type", required: false)
                    formatRow(chinese: "销售", english: "Coach", required: false)
                }
                .padding(12)
                .background(AppTheme.surfaceColor)
                .cornerRadius(8)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(24)
    }
    
    private func formatRow(chinese: String, english: String, required: Bool) -> some View {
        HStack {
            Text(chinese)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
            Text("(\(english))")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
            Spacer()
            if required {
                Text("必填 Required")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.red)
            } else {
                Text("可选 Optional")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }
    
    // MARK: - Column Mapping View
    private var columnMappingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header row toggle
                Toggle(isOn: $hasHeaderRow) {
                    HStack {
                        Text("首行为标题行")
                            .font(.system(size: 12, weight: .medium))
                        Text("First row is header")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .toggleStyle(.checkbox)
                .onChange(of: hasHeaderRow) { _ in
                    reprocessData()
                }
                
                Divider()
                
                Text("列映射 Column Mapping")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                // Column mappings
                VStack(spacing: 12) {
                    columnMappingRow(label: "姓名 Name", icon: "person.fill", required: true, selection: Binding(
                        get: { columnMapping.nameIndex },
                        set: { columnMapping.nameIndex = $0; reprocessData() }
                    ))
                    
                    columnMappingRow(label: "联系方式 Phone", icon: "phone.fill", required: false, selection: Binding(
                        get: { columnMapping.phoneIndex ?? -1 },
                        set: { columnMapping.phoneIndex = $0 == -1 ? nil : $0; reprocessData() }
                    ), allowNone: true)
                    
                    columnMappingRow(label: "金额 Amount", icon: "yensign.circle.fill", required: false, selection: Binding(
                        get: { columnMapping.amountIndex ?? -1 },
                        set: { columnMapping.amountIndex = $0 == -1 ? nil : $0; reprocessData() }
                    ), allowNone: true)
                    
                    columnMappingRow(label: "课程类别 Class Type", icon: "list.bullet", required: false, selection: Binding(
                        get: { columnMapping.typeIndex ?? -1 },
                        set: { columnMapping.typeIndex = $0 == -1 ? nil : $0; reprocessData() }
                    ), allowNone: true)
                    
                    columnMappingRow(label: "销售 Coach", icon: "person.badge.plus", required: false, selection: Binding(
                        get: { columnMapping.coachIndex ?? -1 },
                        set: { columnMapping.coachIndex = $0 == -1 ? nil : $0; reprocessData() }
                    ), allowNone: true)
                }
                
                Divider()
                
                // Coach handling option
                Toggle(isOn: $createMissingCoaches) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动创建不存在的销售")
                            .font(.system(size: 12, weight: .medium))
                        Text("Auto-create missing coaches")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .toggleStyle(.checkbox)
                
                // Preview of first few rows
                if !rawRows.isEmpty {
                    Divider()
                    
                    Text("数据预览 Data Preview (前5行 First 5 rows)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rawRows.prefix(6).enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 8) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                                        Text(cell.isEmpty ? "-" : cell)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(idx == 0 && hasHeaderRow ? AppTheme.accentColor : AppTheme.textPrimary)
                                            .frame(minWidth: 80, alignment: .leading)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(idx == 0 && hasHeaderRow ? AppTheme.accentColor.opacity(0.1) : (idx % 2 == 0 ? AppTheme.surfaceColor.opacity(0.5) : Color.clear))
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(AppTheme.surfaceColor.opacity(0.3))
                    .cornerRadius(8)
                }
            }
            .padding(20)
        }
    }
    
    private func columnMappingRow(label: String, icon: String, required: Bool, selection: Binding<Int>, allowNone: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.accentColor)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
            
            if required {
                Text("*")
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Picker("", selection: selection) {
                if allowNone {
                    Text("-- 无 None --").tag(-1)
                }
                ForEach(0..<detectedColumns.count, id: \.self) { idx in
                    Text(detectedColumns[idx]).tag(idx)
                }
            }
            .frame(width: 180)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Preview View
    private var previewView: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack(spacing: 16) {
                summaryBadge(count: importedStudents.count, label: "总计 Total", color: .blue)
                summaryBadge(count: selectedCount, label: "已选 Selected", color: AppTheme.accentColor)
                summaryBadge(count: validCount, label: "有效 Valid", color: .green)
                if warningCount > 0 {
                    summaryBadge(count: warningCount, label: "警告 Warnings", color: .orange)
                }
                if errorCount > 0 {
                    summaryBadge(count: errorCount, label: "错误 Errors", color: .red)
                }
                
                Spacer()
                
                Button("全选 Select All") {
                    for i in importedStudents.indices {
                        importedStudents[i].isSelected = true
                    }
                }
                .font(.system(size: 10))
                
                Button("取消全选 Deselect") {
                    for i in importedStudents.indices {
                        importedStudents[i].isSelected = false
                    }
                }
                .font(.system(size: 10))
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            
            // Student list
            List {
                ForEach($importedStudents) { $student in
                    EnhancedStudentImportRow(student: $student)
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func summaryBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Footer
    private var importFooter: some View {
        HStack {
            // Back button
            if currentStep != .selectFile {
                Button(action: goBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回 Back")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accentColor)
            }
            
            if currentStep == .selectFile {
                Button(action: { isFilePickerPresented = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("选择文件 Choose File")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accentColor)
            }
            
            Spacer()
            
            Button("取消 Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            // Next/Import button
            if currentStep == .preview {
                Button(action: performImport) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("导入 \(validCount) 名学生")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(validCount > 0 ? AppTheme.accentColor : AppTheme.textTertiary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(validCount == 0 || isProcessing)
            } else if currentStep == .mapColumns {
                Button(action: goToPreview) {
                    HStack(spacing: 4) {
                        Text("下一步 Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
    
    // MARK: - Navigation
    private func goBack() {
        withAnimation {
            switch currentStep {
            case .mapColumns:
                currentStep = .selectFile
            case .preview:
                currentStep = .mapColumns
            default:
                break
            }
        }
    }
    
    private func goToPreview() {
        reprocessData()
        withAnimation {
            currentStep = .preview
        }
    }
    
    // MARK: - File Import Handler
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                importError = "无法访问文件 Unable to access file"
                showingImportError = true
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let rows = try EnhancedCSVParser.parse(from: url)
                processCSVRows(rows)
            } catch {
                importError = error.localizedDescription
                showingImportError = true
            }
            
        case .failure(let error):
            importError = error.localizedDescription
            showingImportError = true
        }
    }
    
    // MARK: - Process CSV Rows
    private func processCSVRows(_ rows: [[String]]) {
        guard !rows.isEmpty else {
            importError = "文件为空 File is empty"
            showingImportError = true
            return
        }
        
        rawRows = rows
        
        // Detect columns from first row
        let firstRow = rows[0]
        detectedColumns = firstRow.enumerated().map { idx, value in
            if hasHeaderRow && !value.isEmpty {
                return value
            } else {
                return "列 \(idx + 1)"
            }
        }
        
        // Auto-detect column mappings based on Chinese headers
        columnMapping = ColumnMapping.autoDetect(from: firstRow)
        
        // Move to column mapping step
        withAnimation {
            currentStep = .mapColumns
        }
        
        // Process data
        reprocessData()
    }
    
    private func reprocessData() {
        guard !rawRows.isEmpty else { return }
        
        let startIndex = hasHeaderRow ? 1 : 0
        
        // Get existing coach names for validation
        let existingCoaches = [dataManager.coach.name]
        
        importedStudents = rawRows.dropFirst(startIndex).compactMap { row -> ImportedStudentData? in
            guard columnMapping.nameIndex < row.count else { return nil }
            
            let name = row[columnMapping.nameIndex].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            
            // Extract phone
            var phone: String? = nil
            if let idx = columnMapping.phoneIndex, idx < row.count {
                let value = row[idx].trimmingCharacters(in: .whitespaces)
                phone = value.isEmpty ? nil : value
            }
            
            // Extract and parse amount
            var amountRaw: String? = nil
            var amount: Double? = nil
            var amountValidation: ImportValidationStatus = .valid
            if let idx = columnMapping.amountIndex, idx < row.count {
                let value = row[idx].trimmingCharacters(in: .whitespaces)
                amountRaw = value.isEmpty ? nil : value
                let (validation, parsedAmount) = StudentImportValidation.validateAndParseAmount(amountRaw)
                amountValidation = validation
                amount = parsedAmount
            }
            
            // Extract contract type
            var contractType: String? = nil
            if let idx = columnMapping.typeIndex, idx < row.count {
                let value = row[idx].trimmingCharacters(in: .whitespaces)
                contractType = value.isEmpty ? nil : value
            }
            
            // Extract coach
            var coach: String? = nil
            if let idx = columnMapping.coachIndex, idx < row.count {
                let value = row[idx].trimmingCharacters(in: .whitespaces)
                coach = value.isEmpty ? nil : value
            }
            
            // Validate all fields
            let nameValidation = StudentImportValidation.validateName(name)
            let phoneValidation = StudentImportValidation.validateChinesePhone(phone)
            let coachValidation = StudentImportValidation.validateCoach(coach, existingCoaches: existingCoaches)
            
            return ImportedStudentData(
                studentName: name,
                parentPhone: phone,
                contractAmount: amount,
                contractAmountRaw: amountRaw,
                contractType: contractType,
                enrollingCoach: coach,
                nameValidation: nameValidation,
                phoneValidation: phoneValidation,
                amountValidation: amountValidation,
                coachValidation: coachValidation
            )
        }
    }
    
    // MARK: - Perform Import
    private func performImport() {
        isProcessing = true
        
        let studentsToImport = importedStudents.filter { $0.isSelected && !$0.hasErrors }
        var successCount = 0
        
        for importRow in studentsToImport {
            // Create student
            let student = Student(
                name: importRow.studentName,
                avatarColor: AvatarColor.allCases.randomElement() ?? .blue
            )
            
            dataManager.addStudent(student)
            
            // Create contract if amount is provided
            if let amount = importRow.contractAmount, amount > 0 {
                // Estimate sessions based on typical pricing (can be adjusted)
                let estimatedSessions = max(1, Int(amount / 200)) // Assume ~200 per session
                
                let contract = Contract(
                    studentId: student.id,
                    contractNumber: 1,
                    totalSessions: estimatedSessions,
                    attendedSessions: 0,
                    startDate: Date(),
                    expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()),
                    totalAmount: amount,
                    amountPaid: amount,
                    isSigned: true,
                    signedDate: Date(),
                    notes: [
                        importRow.parentPhone.map { "电话: \($0)" },
                        importRow.contractType.map { "课程: \($0)" },
                        importRow.enrollingCoach.map { "销售: \($0)" }
                    ].compactMap { $0 }.joined(separator: " | ")
                )
                
                dataManager.addContract(contract)
            }
            
            successCount += 1
        }
        
        isProcessing = false
        importedCount = successCount
        importComplete = true
    }
}

// MARK: - Enhanced Student Import Row View
struct EnhancedStudentImportRow: View {
    @Binding var student: ImportedStudentData
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Toggle("", isOn: $student.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            
            // Status indicator
            Circle()
                .fill(student.hasErrors ? Color.red : (student.hasWarnings ? Color.orange : Color.green))
                .frame(width: 8, height: 8)
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(student.studentName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(student.isSelected ? AppTheme.textPrimary : AppTheme.textTertiary)
                    
                    validationIcon(student.nameValidation)
                }
            }
            .frame(minWidth: 100, alignment: .leading)
            
            // Phone
            HStack(spacing: 4) {
                if let phone = student.parentPhone {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(phone)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                } else {
                    Text("-")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                validationIcon(student.phoneValidation)
            }
            .frame(minWidth: 120, alignment: .leading)
            
            // Amount
            HStack(spacing: 4) {
                if let amount = student.contractAmount {
                    Text("¥\(amount, specifier: "%.0f")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                } else if let raw = student.contractAmountRaw {
                    Text(raw)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                } else {
                    Text("-")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                validationIcon(student.amountValidation)
            }
            .frame(minWidth: 80, alignment: .leading)
            
            // Contract type
            if let type = student.contractType {
                Text(type)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(4)
            }
            
            Spacer()
            
            // Coach
            HStack(spacing: 4) {
                if let coach = student.enrollingCoach {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 9))
                    Text(coach)
                        .font(.system(size: 10))
                }
                validationIcon(student.coachValidation)
            }
            .foregroundColor(AppTheme.textTertiary)
            .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .opacity(student.isSelected ? 1 : 0.5)
    }
    
    @ViewBuilder
    private func validationIcon(_ status: ImportValidationStatus) -> some View {
        if case .valid = status {
            EmptyView()
        } else {
            Image(systemName: status.icon)
                .font(.system(size: 10))
                .foregroundColor(status.color)
                .help(status.message ?? "")
        }
    }
}

// MARK: - Preview
#Preview {
    StudentImportViewMac()
        .environmentObject(DataManager.shared)
        .frame(width: 900, height: 700)
}
#endif
