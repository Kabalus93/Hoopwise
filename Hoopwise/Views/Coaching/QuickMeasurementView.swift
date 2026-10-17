import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Measurement mode enum for Quick Measure
enum QuickMeasureMode: String, CaseIterable {
    case physical = "Physical"
    case speed = "Speed"
    case shooting = "Shooting"

    var icon: String {
        switch self {
        case .physical: return "figure.stand"
        case .speed: return "figure.run"
        case .shooting: return "basketball"
        }
    }

    var color: String {
        switch self {
        case .physical: return "#5B8DEF"
        case .speed: return "#6BCB77"
        case .shooting: return "#FFB347"
        }
    }

    var localizedName: String { rawValue }

    var localizedNameChinese: String {
        switch self {
        case .physical: return "身体"
        case .speed: return "速度"
        case .shooting: return "投篮"
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

                    // Category selector - 3 tabs (Physical, Speed, Shooting)
                    modePicker

                    measurementInputs

                    if !summary.measurements.isEmpty {
                        recentMeasurements
                    }

                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
                        .disabled(!hasAnyValue)
                }
            }
            .sheet(item: $selectedTypeForHistory) { type in
                MeasurementHistoryView(student: student, type: type)
            }
        }
    }
    
    // MARK: - Student Header (Compact)
    private var studentHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 14) {
            StudentAvatarView(student: student, size: 56)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(student.primaryDisplayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                
                if let age = student.age {
                    Text(isChinese ? "\(age) 岁" : "\(age) years old")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.tertiary)
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
    
    // MARK: - Measurement Inputs (cleaner design)
    private var measurementInputs: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese

        return VStack(alignment: .leading, spacing: 14) {
            // Category header
            HStack {
                Image(systemName: selectedMode.icon)
                    .foregroundColor(Color(hex: selectedMode.color))
                Text(isChinese ? selectedMode.localizedNameChinese : selectedMode.localizedName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            ForEach(types(for: selectedMode), id: \.self) { type in
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

    /// Curated list of measurement types per mode. Physical is intentionally
    /// trimmed to height + weight (wingspan / standing reach are rarely used).
    private func types(for mode: QuickMeasureMode) -> [MeasurementType] {
        switch mode {
        case .physical: return [.height, .weight]
        case .speed: return MeasurementCategory.athletic.types
        case .shooting: return MeasurementCategory.shooting.types
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

        HapticFeedback.notification(.success)
        dismiss()
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
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Last value button
                if let last = lastValue {
                    Button(action: onHistoryTap) {
                        HStack(spacing: 4) {
                            Text(last.formattedValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Show last value with improvement - consistent with profile
                if let last = lastValue {
                    Button(action: onHistoryTap) {
                        HStack(spacing: 6) {
                            Text(last.formattedValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            // Show improvement if available - matches profile
                            if let improvement = improvement {
                                Text(improvement >= 0 ? "+\(Int(improvement))%" : "\(Int(improvement))%")
                                    .font(.caption2)
                                    .foregroundColor(improvementColor(improvement))
                            }
                            
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                
                if let description = type.testDescription {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
