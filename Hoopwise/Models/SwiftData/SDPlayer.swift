import Foundation
import SwiftData

@Model
final class SDPlayer {
    @Attribute(.unique) var id: UUID
    var studentId: UUID
    var heightCm: Double?
    var weightKg: Double?
    var wingspanCm: Double?
    var handednessRaw: String
    var position: String?
    var jerseyNumber: Int?
    
    // Parent info stored as JSON
    var parentInfoData: Data?
    var secondaryParentInfoData: Data?
    
    // Contract info stored as JSON
    var contractInfoData: Data?
    
    // Skills stored as JSON
    var skillsData: Data?
    
    var coachNotes: String?
    var medicalNotes: String?
    var profileImageData: Data?
    var createdAt: Date
    var updatedAt: Date
    
    // Relationship
    var student: SDStudent?
    
    init(
        id: UUID = UUID(),
        studentId: UUID,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        wingspanCm: Double? = nil,
        handedness: Handedness = .right,
        position: String? = nil,
        jerseyNumber: Int? = nil,
        parentInfo: ParentInfo = ParentInfo(),
        secondaryParentInfo: ParentInfo? = nil,
        contractInfo: ContractInfo = ContractInfo(),
        skills: SkillsEvaluation = SkillsEvaluation(),
        coachNotes: String? = nil,
        medicalNotes: String? = nil,
        profileImageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studentId = studentId
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.wingspanCm = wingspanCm
        self.handednessRaw = handedness.rawValue
        self.position = position
        self.jerseyNumber = jerseyNumber
        self.parentInfoData = try? JSONEncoder().encode(parentInfo)
        self.secondaryParentInfoData = secondaryParentInfo != nil ? try? JSONEncoder().encode(secondaryParentInfo) : nil
        self.contractInfoData = try? JSONEncoder().encode(contractInfo)
        self.skillsData = try? JSONEncoder().encode(skills)
        self.coachNotes = coachNotes
        self.medicalNotes = medicalNotes
        self.profileImageData = profileImageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Computed properties
    var handedness: Handedness {
        get { Handedness(rawValue: handednessRaw) ?? .right }
        set { handednessRaw = newValue.rawValue }
    }
    
    // Swift 6: Use nonisolated helper functions to avoid actor-isolated Codable conformance issues
    nonisolated func getParentInfo() -> ParentInfo {
        guard let data = parentInfoData else { return ParentInfo() }
        return (try? JSONDecoder().decode(ParentInfo.self, from: data)) ?? ParentInfo()
    }
    
    nonisolated func setParentInfo(_ newValue: ParentInfo) {
        parentInfoData = try? JSONEncoder().encode(newValue)
    }
    
    nonisolated func getSecondaryParentInfo() -> ParentInfo? {
        guard let data = secondaryParentInfoData else { return nil }
        return try? JSONDecoder().decode(ParentInfo.self, from: data)
    }
    
    nonisolated func setSecondaryParentInfo(_ newValue: ParentInfo?) {
        secondaryParentInfoData = newValue != nil ? try? JSONEncoder().encode(newValue) : nil
    }
    
    nonisolated func getContractInfo() -> ContractInfo {
        guard let data = contractInfoData else { return ContractInfo() }
        return (try? JSONDecoder().decode(ContractInfo.self, from: data)) ?? ContractInfo()
    }
    
    nonisolated func setContractInfo(_ newValue: ContractInfo) {
        contractInfoData = try? JSONEncoder().encode(newValue)
    }
    
    nonisolated func getSkills() -> SkillsEvaluation {
        guard let data = skillsData else { return SkillsEvaluation() }
        return (try? JSONDecoder().decode(SkillsEvaluation.self, from: data)) ?? SkillsEvaluation()
    }
    
    nonisolated func setSkills(_ newValue: SkillsEvaluation) {
        skillsData = try? JSONEncoder().encode(newValue)
    }
    
    var heightFormatted: String? {
        guard let h = heightCm else { return nil }
        return "\(Int(h / 30.48))'\(Int((h.truncatingRemainder(dividingBy: 30.48)) / 2.54))\" (\(Int(h))cm)"
    }
    
    var weightFormatted: String? {
        guard let w = weightKg else { return nil }
        return "\(Int(w * 2.205))lbs (\(Int(w))kg)"
    }
    
    /// Convert to legacy Player struct
    func toStruct() -> Player {
        Player(
            id: id,
            studentId: studentId,
            heightCm: heightCm,
            weightKg: weightKg,
            wingspanCm: wingspanCm,
            handedness: handedness,
            position: position,
            jerseyNumber: jerseyNumber,
            parentInfo: getParentInfo(),
            secondaryParentInfo: getSecondaryParentInfo(),
            contractInfo: getContractInfo(),
            skills: getSkills(),
            coachNotes: coachNotes,
            medicalNotes: medicalNotes,
            profileImageData: profileImageData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Create from legacy Player struct
    static func from(_ player: Player) -> SDPlayer {
        let sdPlayer = SDPlayer(
            id: player.id,
            studentId: player.studentId,
            heightCm: player.heightCm,
            weightKg: player.weightKg,
            wingspanCm: player.wingspanCm,
            handedness: player.handedness,
            position: player.position,
            jerseyNumber: player.jerseyNumber,
            parentInfo: player.parentInfo,
            secondaryParentInfo: player.secondaryParentInfo,
            contractInfo: player.contractInfo,
            skills: player.skills,
            coachNotes: player.coachNotes,
            medicalNotes: player.medicalNotes,
            profileImageData: player.profileImageData,
            createdAt: player.createdAt,
            updatedAt: player.updatedAt
        )
        return sdPlayer
    }
}
