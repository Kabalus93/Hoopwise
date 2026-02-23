import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Measurement mode enum for Quick Measure
enum QuickMeasureMode: String, CaseIterable {
    case physical = "Physical"
    case athletic = "Athletic"
    case shooting = "Shooting"
    case skills = "Skills"
    
    var icon: String {
        switch self {
        case .physical: return "figure.stand"
        case .athletic: return "figure.run"
        case .shooting: return "basketball"
        case .skills: return "star.fill"
        }
    }
    
    var color: String {
        switch self {
        case .physical: return "#5B8DEF"
        case .athletic: return "#6BCB77"
        case .shooting: return "#FFB347"
        case .skills: return "#9B59B6"
        }
    }
    
    var localizedName: String {
        switch self {
        case .physical: return rawValue
        case .athletic: return rawValue
        case .shooting: return rawValue
        case .skills: return rawValue
        }
    }
    
    var localizedNameChinese: String {
        switch self {
        case .physical: return "身体"
        case .athletic: return "运动"
        case .shooting: return "投篮"
        case .skills: return "技能"
        }
    }
}

/// Quick measurement system for recording student metrics during sessions
struct QuickMeasurementView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let student: Student
    let sessionId: UUID?
    
    @State private var selectedMode: QuickMeasureMode = .physical
    @State private var measurementValues: [MeasurementType: String] = [:]
    @State private var showingHistory = false
    @State private var selectedTypeForHistory: MeasurementType?
    
    // Skills editing state
    @State private var editedSkills: SkillsEvaluation = SkillsEvaluation()
    @State private var skillsModified = false
    
    var player: Player? {
        dataManager.player(for: student.id)
    }
    
    var summary: MeasurementSummary {
        dataManager.measurementSummary(for: student.id)
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Student header - compact
                    studentHeader
                    
                    // Category selector - 4 tabs including Skills
                    modePicker
                    
                    // Content based on selected mode
                    if selectedMode == .skills {
                        skillsSection
                    } else {
                        measurementInputs
                    }
                    
                    // Recent measurements (only show for non-skills modes)
                    if selectedMode != .skills && !summary.measurements.isEmpty {
                        recentMeasurements
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "快速测量" : "Quick Measure")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { saveAll() }
                        .fontWeight(.semibold)
                        .disabled(!hasAnyValue && !skillsModified)
                }
            }
            .sheet(item: $selectedTypeForHistory) { type in
                MeasurementHistoryView(student: student, type: type)
            }
            .onAppear {
                if let p = player {
                    editedSkills = p.skills
                }
            }
        }
    }
    
    // MARK: - Student Header (Compact)
    private var studentHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 14) {
            StudentAvatarView(student: student, size: 56)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(student.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let age = student.age {
                    Text(isChinese ? "\(age) 岁" : "\(age) years old")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                // Quick stats row
                if let player = player {
                    HStack(spacing: 10) {
                        if let height = player.heightFormatted {
                            HStack(spacing: 3) {
                                Image(systemName: "ruler")
                                    .font(.system(size: 10))
                                Text(height)
                            }
                        }
                        if let weight = player.weightFormatted {
                            HStack(spacing: 3) {
                                Image(systemName: "scalemass")
                                    .font(.system(size: 10))
                                Text(weight)
                            }
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Category Picker (4 tabs)
    private var modePicker: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 6) {
            ForEach(QuickMeasureMode.allCases, id: \.self) { mode in
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode 
                    }
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(isChinese ? mode.localizedNameChinese : mode.localizedName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedMode == mode ? Color(hex: mode.color) : AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedMode == mode ? Color.clear : Color(hex: mode.color).opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(selectedMode == mode ? .white : Color(hex: mode.color))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Skills Evaluation Section (with sliders)
    private var skillsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(Color(hex: "#9B59B6"))
                Text(isChinese ? "技能评估" : "Skills Evaluation")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                
                // Overall rating
                Text(String(format: "%.1f", editedSkills.overallRating))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(skillRatingColor(editedSkills.overallRating))
                Text("/ 10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Skill sliders (6 skills matching radar)
            VStack(spacing: 16) {
                skillSlider(label: isChinese ? "得分" : "Scoring", value: $editedSkills.scoring, color: .orange, icon: "scope")
                skillSlider(label: isChinese ? "组织" : "Playmaking", value: $editedSkills.playmaking, color: .blue, icon: "arrow.triangle.branch")
                skillSlider(label: isChinese ? "篮板" : "Rebounding", value: $editedSkills.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                skillSlider(label: isChinese ? "防守" : "Defense", value: $editedSkills.defense, color: .red, icon: "shield.fill")
                skillSlider(label: isChinese ? "运动能力" : "Athleticism", value: $editedSkills.athleticism, color: .green, icon: "figure.run")
                skillSlider(label: isChinese ? "软实力" : "Intangibles", value: $editedSkills.intangibles, color: .teal, icon: "star.fill")
            }
            
            // Last evaluated info
            if let lastDate = player?.skills.lastEvaluatedDate {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(isChinese ? "最近评估: \(lastDate.formatted(date: .abbreviated, time: .omitted))" : "Last evaluated: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(hex: "#9B59B6").opacity(0.1))
        .cornerRadius(14)
    }
    
    private func skillSlider(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 28)
            }
            
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { 
                    value.wrappedValue = Int($0)
                    skillsModified = true
                }
            ), in: 1...10, step: 1)
            .tint(color)
        }
    }
    
    private func skillRatingColor(_ rating: Double) -> Color {
        switch rating {
        case 8...10: return .green
        case 6..<8: return .blue
        case 4..<6: return .orange
        default: return .red
        }
    }
    
    // MARK: - Measurement Inputs (cleaner design)
    private var measurementInputs: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let category = measurementCategory(for: selectedMode)
        
        return VStack(alignment: .leading, spacing: 14) {
            // Category header
            HStack {
                Image(systemName: selectedMode.icon)
                    .foregroundColor(Color(hex: selectedMode.color))
                Text(isChinese ? selectedMode.localizedNameChinese : selectedMode.localizedName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            ForEach(category.types, id: \.self) { type in
                CleanMeasurementRow(
                    type: type,
                    value: binding(for: type),
                    lastValue: summary.latest(for: type),
                    onHistoryTap: { selectedTypeForHistory = type }
                )
            }
        }
        .padding(16)
        .background(Color(hex: selectedMode.color).opacity(0.1))
        .cornerRadius(14)
    }
    
    private func measurementCategory(for mode: QuickMeasureMode) -> MeasurementCategory {
        switch mode {
        case .physical: return .physical
        case .athletic: return .athletic
        case .shooting: return .shooting
        case .skills: return .physical // Not used for skills
        }
    }
    
    // MARK: - Latest Measurements
    private var recentMeasurements: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isChinese ? "最近测量" : "Recent Measurements")
                    .font(.headline)
                Spacer()
                Button(isChinese ? "查看全部" : "View All") {
                    showingHistory = true
                }
                .font(.caption)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(MeasurementType.allCases.prefix(6), id: \.self) { type in
                    if let measurement = summary.latest(for: type) {
                        MeasurementStatCard(
                            type: type,
                            measurement: measurement,
                            improvement: summary.improvementPercent(for: type)
                        )
                        .onTapGesture {
                            selectedTypeForHistory = type
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func binding(for type: MeasurementType) -> Binding<String> {
        Binding(
            get: { measurementValues[type] ?? "" },
            set: { measurementValues[type] = $0 }
        )
    }
    
    private var hasAnyValue: Bool {
        measurementValues.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    
    private func saveAll() {
        // Save measurements
        var newMeasurements: [PlayerMeasurement] = []
        
        for (type, valueString) in measurementValues {
            guard let value = Double(valueString.trimmingCharacters(in: .whitespaces)),
                  value > 0 else { continue }
            
            let measurement = PlayerMeasurement(
                studentId: student.id,
                type: type,
                value: value,
                sessionId: sessionId
            )
            newMeasurements.append(measurement)
        }
        
        if !newMeasurements.isEmpty {
            dataManager.addMeasurements(newMeasurements)
        }
        
        // Save skills if modified
        if skillsModified {
            saveSkills()
        }
        
        HapticFeedback.notification(.success)
        dismiss()
    }
    
    private func saveSkills() {
        // Get or create player for this student
        if var existingPlayer = player {
            existingPlayer.skills = editedSkills
            existingPlayer.skills.lastEvaluatedDate = Date()
            existingPlayer.updatedAt = Date()
            dataManager.updatePlayer(existingPlayer)
        } else {
            // Create new player with skills
            var newPlayer = Player(studentId: student.id)
            newPlayer.skills = editedSkills
            newPlayer.skills.lastEvaluatedDate = Date()
            dataManager.addPlayer(newPlayer)
        }
    }
}

// MARK: - Clean Measurement Row (Polished Design)
struct CleanMeasurementRow: View {
    let type: MeasurementType
    @Binding var value: String
    let lastValue: PlayerMeasurement?
    let onHistoryTap: () -> Void
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 10) {
            // Header row with icon, label, and last value
            HStack {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: type.category.color))
                    .frame(width: 24)
                
                Text(isChinese ? type.localizedNameChinese : type.localizedName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                // Last value button
                if let last = lastValue {
                    Button(action: onHistoryTap) {
                        HStack(spacing: 4) {
                            Text(last.formattedValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Input row
            HStack(spacing: 10) {
                TextField(isChinese ? "输入数值" : "Enter value", text: $value)
                    .font(.system(size: 15))
                    #if os(iOS)
                    .keyboardType(keyboardType)
                    #endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(8)
                
                Text(type.unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 36)
            }
        }
        .padding(.vertical, 4)
    }
    
    #if os(iOS)
    private var keyboardType: UIKeyboardType {
        switch type {
        case .shootingPercent, .freeThrowPercent, .threePointPercent:
            return .numberPad
        default:
            return .decimalPad
        }
    }
    #endif
}

// MARK: - Measurement Input Row (consistent with profile styling)
struct MeasurementInputRow: View {
    let type: MeasurementType
    @Binding var value: String
    let lastValue: PlayerMeasurement?
    let improvement: Double?
    let onHistoryTap: () -> Void
    
    init(type: MeasurementType, value: Binding<String>, lastValue: PlayerMeasurement?, improvement: Double? = nil, onHistoryTap: @escaping () -> Void) {
        self.type = type
        self._value = value
        self.lastValue = lastValue
        self.improvement = improvement
        self.onHistoryTap = onHistoryTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(Color(hex: type.category.color))
                    .frame(width: 24)
                
                Text(type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                // Show last value with improvement - consistent with profile
                if let last = lastValue {
                    Button(action: onHistoryTap) {
                        HStack(spacing: 6) {
                            Text(last.formattedValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.textPrimary)
                            
                            // Show improvement if available - matches profile
                            if let improvement = improvement {
                                Text(improvement >= 0 ? "+\(Int(improvement))%" : "\(Int(improvement))%")
                                    .font(.caption2)
                                    .foregroundColor(improvementColor(improvement))
                            }
                            
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack {
                TextField("Enter value", text: $value)
                    #if os(iOS)
                    .keyboardType(keyboardType)
                    #endif
                    .textFieldStyle(.roundedBorder)
                
                Text(type.unit)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 40)
                
                if let description = type.testDescription {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private func improvementColor(_ improvement: Double) -> Color {
        if type.lowerIsBetter {
            return improvement <= 0 ? .green : .red
        }
        return improvement >= 0 ? .green : .red
    }
    
    #if os(iOS)
    private var keyboardType: UIKeyboardType {
        switch type {
        case .shootingPercent, .freeThrowPercent, .threePointPercent:
            return .numberPad
        default:
            return .decimalPad
        }
    }
    #endif
}

// MARK: - Measurement Stat Card
struct MeasurementStatCard: View {
    let type: MeasurementType
    let measurement: PlayerMeasurement
    let improvement: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(Color(hex: type.category.color))
                Text(type.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(measurement.formattedValue)
                .font(.title3)
                .fontWeight(.bold)
            
            HStack(spacing: 4) {
                if let improvement = improvement {
                    Image(systemName: improvement >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(String(format: "%.1f%%", abs(improvement)))
                        .font(.caption2)
                }
                
                Spacer()
                
                Text(measurement.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(improvementColor)
        }
        .padding(12)
        .background(Color.systemGray6)
        .cornerRadius(10)
    }
    
    private var improvementColor: Color {
        guard let improvement = improvement else { return .secondary }
        if type.lowerIsBetter {
            return improvement <= 0 ? .green : .red
        }
        return improvement >= 0 ? .green : .red
    }
}

// MARK: - Measurement History View
struct MeasurementHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let student: Student
    let type: MeasurementType
    
    var history: [PlayerMeasurement] {
        dataManager.measurementSummary(for: student.id).history(for: type)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Chart section
                if history.count >= 2 {
                    Section("Progress") {
                        MeasurementChartView(measurements: history, type: type)
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                    }
                }
                
                // History list
                Section("History") {
                    if history.isEmpty {
                        Text("No measurements recorded")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(history.reversed()) { measurement in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(measurement.formattedValue)
                                        .font(.headline)
                                    Text(measurement.recordedAt.formatted(date: .long, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let notes = measurement.notes {
                                    Image(systemName: "note.text")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(type.rawValue) History")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Simple Chart View
struct MeasurementChartView: View {
    let measurements: [PlayerMeasurement]
    let type: MeasurementType
    
    var body: some View {
        GeometryReader { geometry in
            let values = measurements.map { $0.value }
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = maxVal - minVal
            let padding: CGFloat = 20
            
            ZStack {
                // Background grid
                Path { path in
                    for i in 0...4 {
                        let y = padding + (geometry.size.height - 2 * padding) * CGFloat(i) / 4
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - padding, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                
                // Line chart
                Path { path in
                    for (index, measurement) in measurements.enumerated() {
                        let x = padding + (geometry.size.width - 2 * padding) * CGFloat(index) / CGFloat(max(measurements.count - 1, 1))
                        let normalizedY = range > 0 ? (measurement.value - minVal) / range : 0.5
                        let y = geometry.size.height - padding - (geometry.size.height - 2 * padding) * CGFloat(normalizedY)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color(hex: type.category.color), lineWidth: 2)
                
                // Data points
                ForEach(Array(measurements.enumerated()), id: \.element.id) { index, measurement in
                    let x = padding + (geometry.size.width - 2 * padding) * CGFloat(index) / CGFloat(max(measurements.count - 1, 1))
                    let normalizedY = range > 0 ? (measurement.value - minVal) / range : 0.5
                    let y = geometry.size.height - padding - (geometry.size.height - 2 * padding) * CGFloat(normalizedY)
                    
                    Circle()
                        .fill(Color(hex: type.category.color))
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
        .padding()
        .background(Color.systemBackground)
    }
}

// MARK: - MeasurementType Identifiable
extension MeasurementType: Identifiable {
    var id: String { rawValue }
}

#Preview {
    QuickMeasurementView(
        student: Student.samples[0],
        sessionId: nil
    )
    .environmentObject(DataManager.shared)
}
