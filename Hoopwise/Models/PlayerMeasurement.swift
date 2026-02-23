import Foundation

// MARK: - Measurement Types
enum MeasurementType: String, Codable, CaseIterable {
    case height = "Height"
    case weight = "Weight"
    case wingspan = "Wingspan"
    case standingReach = "Standing Reach"
    case sprintTime = "Sprint Time"
    case shuttleRun = "Shuttle Run"
    case verticalJump = "Vertical Jump"
    case laneAgility = "Lane Agility"
    case shootingPercent = "Shooting %"
    case freeThrowPercent = "Free Throw %"
    case threePointPercent = "3-Point %"
    
    var icon: String {
        switch self {
        case .height: return "ruler"
        case .weight: return "scalemass"
        case .wingspan: return "arrow.left.and.right"
        case .standingReach: return "arrow.up"
        case .sprintTime: return "stopwatch"
        case .shuttleRun: return "figure.run"
        case .verticalJump: return "arrow.up.circle"
        case .laneAgility: return "arrow.triangle.swap"
        case .shootingPercent: return "basketball"
        case .freeThrowPercent: return "sportscourt"
        case .threePointPercent: return "target"
        }
    }
    
    var unit: String {
        switch self {
        case .height, .wingspan, .standingReach, .verticalJump: return "cm"
        case .weight: return "kg"
        case .sprintTime, .shuttleRun, .laneAgility: return "sec"
        case .shootingPercent, .freeThrowPercent, .threePointPercent: return "%"
        }
    }
    
    var category: MeasurementCategory {
        switch self {
        case .height, .weight, .wingspan, .standingReach:
            return .physical
        case .sprintTime, .shuttleRun, .verticalJump, .laneAgility:
            return .athletic
        case .shootingPercent, .freeThrowPercent, .threePointPercent:
            return .shooting
        }
    }
    
    /// Whether lower values are better (like sprint time)
    var lowerIsBetter: Bool {
        switch self {
        case .sprintTime, .shuttleRun, .laneAgility: return true
        default: return false
        }
    }
    
    var localizedName: String {
        return rawValue
    }
    
    var localizedNameChinese: String {
        switch self {
        case .height: return "身高"
        case .weight: return "体重"
        case .wingspan: return "臂展"
        case .standingReach: return "站立触高"
        case .sprintTime: return "冲刺时间"
        case .shuttleRun: return "折返跑"
        case .verticalJump: return "垂直跳"
        case .laneAgility: return "灵活性"
        case .shootingPercent: return "投篮命中率"
        case .freeThrowPercent: return "罚球命中率"
        case .threePointPercent: return "三分命中率"
        }
    }
    
    var shortLabel: String {
        return String(rawValue.prefix(6))
    }
    
    var shortLabelChinese: String {
        switch self {
        case .height: return "身高"
        case .weight: return "体重"
        case .wingspan: return "臂展"
        case .standingReach: return "触高"
        case .sprintTime: return "冲刺"
        case .shuttleRun: return "折返"
        case .verticalJump: return "垂跳"
        case .laneAgility: return "灵活"
        case .shootingPercent: return "投篮"
        case .freeThrowPercent: return "罚球"
        case .threePointPercent: return "三分"
        }
    }
    
    /// Default distance/parameters for timed tests
    var testDescription: String? {
        switch self {
        case .sprintTime: return "40m sprint"
        case .shuttleRun: return "5-10-5 shuttle"
        case .laneAgility: return "Lane agility drill"
        case .shootingPercent: return "10 shots in 60 sec"
        case .freeThrowPercent: return "10 free throws"
        case .threePointPercent: return "10 three-pointers"
        default: return nil
        }
    }
}

enum MeasurementCategory: String, Codable, CaseIterable {
    case physical = "Physical"
    case athletic = "Athletic"
    case shooting = "Shooting"
    
    var icon: String {
        switch self {
        case .physical: return "figure.stand"
        case .athletic: return "figure.run"
        case .shooting: return "basketball"
        }
    }
    
    var color: String {
        switch self {
        case .physical: return "#5B8DEF"
        case .athletic: return "#6BCB77"
        case .shooting: return "#FFB347"
        }
    }
    
    var types: [MeasurementType] {
        MeasurementType.allCases.filter { $0.category == self }
    }
}

// MARK: - Player Measurement
struct PlayerMeasurement: Identifiable, Codable, Hashable {
    let id: UUID
    var studentId: UUID
    var type: MeasurementType
    var value: Double
    var sessionId: UUID?        // Which session this was recorded in
    var notes: String?
    var recordedAt: Date
    var recordedBy: String?     // Coach name
    
    init(id: UUID = UUID(), studentId: UUID, type: MeasurementType, value: Double,
         sessionId: UUID? = nil, notes: String? = nil,
         recordedAt: Date = Date(), recordedBy: String? = nil) {
        self.id = id
        self.studentId = studentId
        self.type = type
        self.value = value
        self.sessionId = sessionId
        self.notes = notes
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
    }
    
    var formattedValue: String {
        switch type {
        case .height, .wingspan, .standingReach, .verticalJump:
            return "\(Int(value)) \(type.unit)"
        case .weight:
            return String(format: "%.1f \(type.unit)", value)
        case .sprintTime, .shuttleRun, .laneAgility:
            return String(format: "%.2f \(type.unit)", value)
        case .shootingPercent, .freeThrowPercent, .threePointPercent:
            return "\(Int(value))\(type.unit)"
        }
    }
}

// MARK: - Measurement Summary
/// Aggregates measurements for a student
struct MeasurementSummary {
    let studentId: UUID
    let measurements: [PlayerMeasurement]
    
    init(studentId: UUID, measurements: [PlayerMeasurement]) {
        self.studentId = studentId
        self.measurements = measurements.filter { $0.studentId == studentId }
    }
    
    /// Get latest measurement of a specific type
    func latest(for type: MeasurementType) -> PlayerMeasurement? {
        measurements
            .filter { $0.type == type }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first
    }
    
    /// Get all measurements of a specific type, sorted by date
    func history(for type: MeasurementType) -> [PlayerMeasurement] {
        measurements
            .filter { $0.type == type }
            .sorted { $0.recordedAt < $1.recordedAt }
    }
    
    /// Calculate improvement between first and last measurement
    func improvement(for type: MeasurementType) -> Double? {
        let history = history(for: type)
        guard history.count >= 2,
              let first = history.first,
              let last = history.last else { return nil }
        
        let diff = last.value - first.value
        return type.lowerIsBetter ? -diff : diff
    }
    
    /// Get improvement percentage
    func improvementPercent(for type: MeasurementType) -> Double? {
        let history = history(for: type)
        guard history.count >= 2,
              let first = history.first,
              first.value != 0 else { return nil }
        
        guard let improvement = improvement(for: type) else { return nil }
        return (improvement / first.value) * 100
    }
    
    /// Latest measurements by category
    func latestByCategory(_ category: MeasurementCategory) -> [PlayerMeasurement] {
        category.types.compactMap { latest(for: $0) }
    }
    
    /// Quick stats for display
    var latestHeight: String? { latest(for: .height)?.formattedValue }
    var latestWeight: String? { latest(for: .weight)?.formattedValue }
    var latestWingspan: String? { latest(for: .wingspan)?.formattedValue }
    var latestSprintTime: String? { latest(for: .sprintTime)?.formattedValue }
    var latestVerticalJump: String? { latest(for: .verticalJump)?.formattedValue }
    var latestShootingPercent: String? { latest(for: .shootingPercent)?.formattedValue }
}
