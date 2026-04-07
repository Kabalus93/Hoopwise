import Foundation

// MARK: - Supabase DTOs
// These structs match the Supabase table schema (snake_case)
// and handle conversion to/from the app's Swift models

// MARK: - Student DTO
struct SupabaseStudent: Codable {
    let id: UUID
    var organizationId: UUID?  // Required for multi-org filtering
    var name: String
    var chineseName: String?
    var avatarColor: String
    var attendanceStatus: String
    var categoryId: UUID?
    var coachId: UUID?
    var programId: UUID?
    var birthdate: Date?
    var birthMonth: Int?      // Month component (1-12) for month/year input
    var birthYear: Int?       // Year component for month/year input
    var schoolGrade: String?  // School grade for age estimation (e.g., "K1", "P3", "H2")
    var profileImageUrl: String?
    var createdByCoachId: UUID?
    var parentalTouchpointsJson: String?
    var lastParentContact: Date?
    var mediaAssetsJson: String?
    var personalBestsJson: String?
    var performanceGrade: String?
    var gradeHistoryJson: String?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, name, chineseName, avatarColor, attendanceStatus
        case categoryId, coachId, programId, birthdate, birthMonth, birthYear, schoolGrade
        case profileImageUrl, createdByCoachId, parentalTouchpointsJson, lastParentContact
        case mediaAssetsJson, personalBestsJson, performanceGrade, gradeHistoryJson, createdAt, updatedAt
    }
    
    init(from student: Student, organizationId: UUID? = nil) {
        self.id = student.id
        // Use explicitly provided organizationId first (from persisted SDStudent),
        // then fall back to current auth context
        self.organizationId = organizationId ?? AuthManager.shared.currentOrganization?.id
        self.name = student.name
        self.chineseName = student.chineseName
        self.avatarColor = student.avatarColor.rawValue
        self.attendanceStatus = student.attendanceStatus.rawValue
        self.categoryId = student.categoryId
        self.coachId = student.coachId
        self.programId = student.programId
        self.birthdate = student.birthdate
        self.birthMonth = student.birthMonth
        self.birthYear = student.birthYear
        self.schoolGrade = student.schoolGrade?.rawValue
        self.profileImageUrl = student.profileImageUrl
        self.createdByCoachId = student.createdByCoachId
        if !student.parentalTouchpoints.isEmpty,
           let data = try? JSONEncoder().encode(student.parentalTouchpoints),
           let jsonString = String(data: data, encoding: .utf8) {
            self.parentalTouchpointsJson = jsonString
        } else {
            self.parentalTouchpointsJson = nil
        }
        self.lastParentContact = student.lastParentContact
        // Encode mediaAssets to JSON
        if let data = try? JSONEncoder().encode(student.mediaAssets),
           let jsonString = String(data: data, encoding: .utf8) {
            self.mediaAssetsJson = jsonString
        } else {
            self.mediaAssetsJson = nil
        }
        // Encode personalBests to JSON
        if !student.personalBests.isEmpty,
           let data = try? JSONEncoder().encode(student.personalBests),
           let jsonString = String(data: data, encoding: .utf8) {
            self.personalBestsJson = jsonString
        } else {
            self.personalBestsJson = nil
        }
        self.performanceGrade = student.performanceGrade?.rawValue
        // Encode gradeHistory to JSON
        if !student.gradeHistory.isEmpty,
           let data = try? JSONEncoder().encode(student.gradeHistory),
           let jsonString = String(data: data, encoding: .utf8) {
            self.gradeHistoryJson = jsonString
        } else {
            self.gradeHistoryJson = nil
        }
        self.createdAt = student.createdAt
        self.updatedAt = student.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(name, forKey: .name)
        try container.encode(chineseName, forKey: .chineseName)
        try container.encode(avatarColor, forKey: .avatarColor)
        try container.encode(attendanceStatus, forKey: .attendanceStatus)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(coachId, forKey: .coachId)
        try container.encode(programId, forKey: .programId)
        try container.encode(birthdate, forKey: .birthdate)
        try container.encode(birthMonth, forKey: .birthMonth)
        try container.encode(birthYear, forKey: .birthYear)
        try container.encode(schoolGrade, forKey: .schoolGrade)
        try container.encode(profileImageUrl, forKey: .profileImageUrl)
        try container.encode(createdByCoachId, forKey: .createdByCoachId)
        try container.encode(parentalTouchpointsJson, forKey: .parentalTouchpointsJson)
        try container.encode(lastParentContact, forKey: .lastParentContact)
        try container.encode(mediaAssetsJson, forKey: .mediaAssetsJson)
        try container.encode(personalBestsJson, forKey: .personalBestsJson)
        try container.encode(performanceGrade, forKey: .performanceGrade)
        try container.encode(gradeHistoryJson, forKey: .gradeHistoryJson)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toStudent() -> Student {
        var touchpoints: [ParentalTouchpoint] = []
        if let jsonString = parentalTouchpointsJson,
           let data = jsonString.data(using: .utf8) {
            touchpoints = (try? JSONDecoder().decode([ParentalTouchpoint].self, from: data)) ?? []
        }
        
        var mediaAssets = MediaAssetStatus()
        if let jsonString = mediaAssetsJson,
           let data = jsonString.data(using: .utf8) {
            mediaAssets = (try? JSONDecoder().decode(MediaAssetStatus.self, from: data)) ?? MediaAssetStatus()
        }
        
        var personalBests: [String: Double] = [:]
        if let jsonString = personalBestsJson,
           let data = jsonString.data(using: .utf8) {
            personalBests = (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        
        var gradeHistory: [GradeHistoryEntry] = []
        if let jsonString = gradeHistoryJson,
           let data = jsonString.data(using: .utf8) {
            gradeHistory = (try? JSONDecoder().decode([GradeHistoryEntry].self, from: data)) ?? []
        }
        
        return Student(
            id: id,
            name: name,
            chineseName: chineseName,
            avatarColor: AvatarColor(rawValue: avatarColor) ?? .blue,
            attendanceStatus: AttendanceStatus(rawValue: attendanceStatus) ?? .present,
            categoryId: categoryId,
            coachId: coachId,
            programId: programId,
            birthdate: birthdate,
            birthMonth: birthMonth,
            birthYear: birthYear,
            schoolGrade: schoolGrade.flatMap { SchoolGrade(rawValue: $0) },
            profileImageUrl: profileImageUrl,
            createdByCoachId: createdByCoachId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            parentalTouchpoints: touchpoints,
            lastParentContact: lastParentContact,
            mediaAssets: mediaAssets,
            personalBests: personalBests,
            performanceGrade: performanceGrade.flatMap { PerformanceGrade(rawValue: $0) },
            gradeHistory: gradeHistory
        )
    }
}

// MARK: - Player DTO
struct SupabasePlayer: Codable {
    let id: UUID
    var organizationId: UUID?  // Required for multi-org filtering
    var studentId: UUID
    var heightCm: Double?
    var weightKg: Double?
    var wingspanCm: Double?
    var handedness: String
    var position: String?
    var jerseyNumber: Int?
    var parentInfo: ParentInfo
    var secondaryParentInfo: ParentInfo?
    var contractInfo: ContractInfo
    var skills: SkillsEvaluation
    var coachNotes: String?
    var medicalNotes: String?
    var headerImageUrl: String?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, studentId, heightCm, weightKg, wingspanCm, handedness
        case position, jerseyNumber, parentInfo, secondaryParentInfo
        case contractInfo, skills, coachNotes, medicalNotes, headerImageUrl, createdAt, updatedAt
    }
    
    init(from player: Player) {
        self.id = player.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.studentId = player.studentId
        self.heightCm = player.heightCm
        self.weightKg = player.weightKg
        self.wingspanCm = player.wingspanCm
        self.handedness = player.handedness.rawValue
        self.position = player.position
        self.jerseyNumber = player.jerseyNumber
        self.parentInfo = player.parentInfo
        self.secondaryParentInfo = player.secondaryParentInfo
        self.contractInfo = player.contractInfo
        self.skills = player.skills
        self.coachNotes = player.coachNotes
        self.medicalNotes = player.medicalNotes
        self.headerImageUrl = player.headerImageURL
        self.createdAt = player.createdAt
        self.updatedAt = player.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(studentId, forKey: .studentId)
        try container.encode(heightCm, forKey: .heightCm)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(wingspanCm, forKey: .wingspanCm)
        try container.encode(handedness, forKey: .handedness)
        try container.encode(position, forKey: .position)
        try container.encode(jerseyNumber, forKey: .jerseyNumber)
        try container.encode(parentInfo, forKey: .parentInfo)
        try container.encode(secondaryParentInfo, forKey: .secondaryParentInfo)
        try container.encode(contractInfo, forKey: .contractInfo)
        try container.encode(skills, forKey: .skills)
        try container.encode(coachNotes, forKey: .coachNotes)
        try container.encode(medicalNotes, forKey: .medicalNotes)
        try container.encode(headerImageUrl, forKey: .headerImageUrl)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toPlayer() -> Player {
        Player(
            id: id,
            studentId: studentId,
            heightCm: heightCm,
            weightKg: weightKg,
            wingspanCm: wingspanCm,
            handedness: Handedness(rawValue: handedness) ?? .right,
            position: position,
            jerseyNumber: jerseyNumber,
            parentInfo: parentInfo,
            secondaryParentInfo: secondaryParentInfo,
            contractInfo: contractInfo,
            skills: skills,
            coachNotes: coachNotes,
            medicalNotes: medicalNotes,
            headerImageURL: headerImageUrl,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Contract DTO
struct SupabaseContract: Codable {
    let id: UUID
    var organizationId: UUID?  // Required for multi-org filtering
    var studentId: UUID
    var contractNumber: Int
    var contractType: String?
    var enrollmentDate: Date?  // When student enrolled
    var totalSessions: Int
    var attendedSessions: Int
    var attendedSessionIdsJson: String?  // Session event IDs attended as JSON
    var weeklyAttendanceJson: String?
    var startDate: Date?
    var expiryDate: Date?
    var pricePerSession: Double
    var totalAmount: Double
    var amountPaid: Double
    var isSigned: Bool
    var signedDate: Date?
    var jerseyGiven: Bool
    var jerseyGivenDate: Date?
    var ballGiven: Bool
    var ballGivenDate: Date?
    var jerseyNumber: Int?
    var jerseySize: String?
    var notes: String?
    var createdByCoachId: UUID?
    var manualStatus: String?
    var programAssignmentsJson: String?
    var historicalSessionsConsumed: Int
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, studentId, contractNumber, contractType, enrollmentDate
        case totalSessions, attendedSessions, attendedSessionIdsJson, historicalSessionsConsumed
        case weeklyAttendanceJson, startDate, expiryDate, pricePerSession, totalAmount, amountPaid
        case isSigned, signedDate, jerseyGiven, jerseyGivenDate, ballGiven, ballGivenDate
        case jerseyNumber, jerseySize, notes, createdByCoachId, manualStatus, programAssignmentsJson
        case createdAt, updatedAt
    }
    
    // Custom decoder to handle missing columns (backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        organizationId = try container.decodeIfPresent(UUID.self, forKey: .organizationId)
        studentId = try container.decode(UUID.self, forKey: .studentId)
        contractNumber = try container.decode(Int.self, forKey: .contractNumber)
        contractType = try container.decodeIfPresent(String.self, forKey: .contractType)
        enrollmentDate = try container.decodeIfPresent(Date.self, forKey: .enrollmentDate)
        totalSessions = try container.decode(Int.self, forKey: .totalSessions)
        attendedSessions = try container.decode(Int.self, forKey: .attendedSessions)
        attendedSessionIdsJson = try container.decodeIfPresent(String.self, forKey: .attendedSessionIdsJson)
        weeklyAttendanceJson = try container.decodeIfPresent(String.self, forKey: .weeklyAttendanceJson)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        pricePerSession = try container.decode(Double.self, forKey: .pricePerSession)
        totalAmount = try container.decode(Double.self, forKey: .totalAmount)
        amountPaid = try container.decode(Double.self, forKey: .amountPaid)
        isSigned = try container.decode(Bool.self, forKey: .isSigned)
        signedDate = try container.decodeIfPresent(Date.self, forKey: .signedDate)
        jerseyGiven = try container.decode(Bool.self, forKey: .jerseyGiven)
        jerseyGivenDate = try container.decodeIfPresent(Date.self, forKey: .jerseyGivenDate)
        ballGiven = try container.decode(Bool.self, forKey: .ballGiven)
        ballGivenDate = try container.decodeIfPresent(Date.self, forKey: .ballGivenDate)
        jerseyNumber = try container.decodeIfPresent(Int.self, forKey: .jerseyNumber)
        jerseySize = try container.decodeIfPresent(String.self, forKey: .jerseySize)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdByCoachId = try container.decodeIfPresent(UUID.self, forKey: .createdByCoachId)
        manualStatus = try container.decodeIfPresent(String.self, forKey: .manualStatus)
        programAssignmentsJson = try container.decodeIfPresent(String.self, forKey: .programAssignmentsJson)
        historicalSessionsConsumed = try container.decodeIfPresent(Int.self, forKey: .historicalSessionsConsumed) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    init(from contract: Contract) {
        self.id = contract.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.studentId = contract.studentId
        self.contractNumber = contract.contractNumber
        self.contractType = contract.contractType.rawValue
        self.enrollmentDate = contract.enrollmentDate
        self.totalSessions = contract.totalSessions
        self.attendedSessions = contract.attendedSessions
        // Encode attended session IDs as JSON string
        if !contract.attendedSessionIds.isEmpty,
           let data = try? JSONEncoder().encode(contract.attendedSessionIds),
           let jsonString = String(data: data, encoding: .utf8) {
            self.attendedSessionIdsJson = jsonString
        } else {
            self.attendedSessionIdsJson = nil
        }
        // Encode weekly attendance as JSON string (legacy)
        if let data = try? JSONEncoder().encode(contract.weeklyAttendance),
           let jsonString = String(data: data, encoding: .utf8) {
            self.weeklyAttendanceJson = jsonString
        } else {
            self.weeklyAttendanceJson = nil
        }
        self.startDate = contract.startDate
        self.expiryDate = contract.expiryDate
        self.pricePerSession = contract.pricePerSession
        self.totalAmount = contract.totalAmount
        self.amountPaid = contract.amountPaid
        self.isSigned = contract.isSigned
        self.signedDate = contract.signedDate
        self.jerseyGiven = contract.jerseyGiven
        self.jerseyGivenDate = contract.jerseyGivenDate
        self.ballGiven = contract.ballGiven
        self.ballGivenDate = contract.ballGivenDate
        self.jerseyNumber = contract.jerseyNumber
        self.jerseySize = contract.jerseySize
        self.notes = contract.notes
        self.createdByCoachId = contract.createdByCoachId
        self.manualStatus = contract.manualStatus?.rawValue
        // Encode program assignments as JSON string
        if !contract.programAssignments.isEmpty,
           let data = try? JSONEncoder().encode(contract.programAssignments),
           let jsonString = String(data: data, encoding: .utf8) {
            self.programAssignmentsJson = jsonString
        } else {
            self.programAssignmentsJson = nil
        }
        self.historicalSessionsConsumed = contract.historicalSessionsConsumed
        self.createdAt = contract.createdAt
        self.updatedAt = contract.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(studentId, forKey: .studentId)
        try container.encode(contractNumber, forKey: .contractNumber)
        try container.encode(contractType, forKey: .contractType)
        try container.encode(enrollmentDate, forKey: .enrollmentDate)
        try container.encode(totalSessions, forKey: .totalSessions)
        try container.encode(attendedSessions, forKey: .attendedSessions)
        try container.encode(attendedSessionIdsJson, forKey: .attendedSessionIdsJson)
        try container.encode(weeklyAttendanceJson, forKey: .weeklyAttendanceJson)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(expiryDate, forKey: .expiryDate)
        try container.encode(pricePerSession, forKey: .pricePerSession)
        try container.encode(totalAmount, forKey: .totalAmount)
        try container.encode(amountPaid, forKey: .amountPaid)
        try container.encode(isSigned, forKey: .isSigned)
        try container.encode(signedDate, forKey: .signedDate)
        try container.encode(jerseyGiven, forKey: .jerseyGiven)
        try container.encode(jerseyGivenDate, forKey: .jerseyGivenDate)
        try container.encode(ballGiven, forKey: .ballGiven)
        try container.encode(ballGivenDate, forKey: .ballGivenDate)
        try container.encode(jerseyNumber, forKey: .jerseyNumber)
        try container.encode(jerseySize, forKey: .jerseySize)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdByCoachId, forKey: .createdByCoachId)
        try container.encode(manualStatus, forKey: .manualStatus)
        try container.encode(programAssignmentsJson, forKey: .programAssignmentsJson)
        try container.encode(historicalSessionsConsumed, forKey: .historicalSessionsConsumed)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toContract() -> Contract {
        // Decode weekly attendance from JSON string (legacy)
        var weeklyAttendance: [WeeklyAttendanceRecord] = []
        if let jsonString = weeklyAttendanceJson,
           let data = jsonString.data(using: .utf8) {
            weeklyAttendance = (try? JSONDecoder().decode([WeeklyAttendanceRecord].self, from: data)) ?? []
        }
        
        // Decode program assignments from JSON string
        var programAssignments: [UUID] = []
        if let jsonString = programAssignmentsJson,
           let data = jsonString.data(using: .utf8) {
            programAssignments = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        
        // Decode attended session IDs from JSON string
        var attendedSessionIds: [UUID] = []
        if let jsonString = attendedSessionIdsJson,
           let data = jsonString.data(using: .utf8) {
            attendedSessionIds = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        
        return Contract(
            id: id,
            studentId: studentId,
            contractNumber: contractNumber,
            contractType: contractType.flatMap { ContractType(rawValue: $0) },
            totalSessions: totalSessions,
            attendedSessions: attendedSessions,
            weeklyAttendance: weeklyAttendance,
            startDate: startDate,
            expiryDate: expiryDate,
            pricePerSession: pricePerSession,
            totalAmount: totalAmount,
            amountPaid: amountPaid,
            isSigned: isSigned,
            signedDate: signedDate,
            jerseyGiven: jerseyGiven,
            jerseyGivenDate: jerseyGivenDate,
            ballGiven: ballGiven,
            ballGivenDate: ballGivenDate,
            jerseyNumber: jerseyNumber,
            jerseySize: jerseySize,
            notes: notes,
            createdByCoachId: createdByCoachId,
            manualStatus: manualStatus.flatMap { ContractStatus(rawValue: $0) },
            programAssignments: programAssignments,
            historicalSessionsConsumed: historicalSessionsConsumed,
            attendedSessionIds: attendedSessionIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Program DTO
struct SupabaseProgram: Codable {
    let id: UUID
    var organizationId: UUID?  // Required for multi-org filtering
    var name: String
    var ageGroup: String
    var durationWeeks: Int
    var programDescription: String?
    var objectives: [String]
    var enrolledStudentIds: [UUID]
    var coachId: UUID?
    var createdByCoachId: UUID?  // Coach who created this program (for access control)
    var status: String
    var colorHex: String
    var mascot: String
    var startDate: Date?
    var endDate: Date?
    var stars: Int?  // Quality/tier rating (1-4), optional for backward compatibility
    var skillTargetsJson: String?  // ProgramSkillTargets stored as JSON string
    var recurringDaysJson: String?  // [Weekday] stored as JSON string
    var defaultSessionTime: Date?
    var defaultSessionDurationMinutes: Int
    var locationId: UUID?
    var locationName: String?
    var usesPhases: Bool
    var createdAt: Date
    var updatedAt: Date

    // Custom coding keys for description field
    enum CodingKeys: String, CodingKey {
        case id, organizationId, name, ageGroup, durationWeeks
        case programDescription = "description"
        case objectives, enrolledStudentIds, coachId, createdByCoachId, status, colorHex, mascot
        case startDate, endDate, stars, skillTargetsJson, recurringDaysJson
        case defaultSessionTime, defaultSessionDurationMinutes, locationId, locationName
        case usesPhases, createdAt, updatedAt
    }
    
    // Custom decoder to handle missing usesPhases column (backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        organizationId = try container.decodeIfPresent(UUID.self, forKey: .organizationId)
        name = try container.decode(String.self, forKey: .name)
        ageGroup = try container.decode(String.self, forKey: .ageGroup)
        durationWeeks = try container.decode(Int.self, forKey: .durationWeeks)
        programDescription = try container.decodeIfPresent(String.self, forKey: .programDescription)
        objectives = try container.decodeIfPresent([String].self, forKey: .objectives) ?? []
        enrolledStudentIds = try container.decodeIfPresent([UUID].self, forKey: .enrolledStudentIds) ?? []
        coachId = try container.decodeIfPresent(UUID.self, forKey: .coachId)
        createdByCoachId = try container.decodeIfPresent(UUID.self, forKey: .createdByCoachId)
        status = try container.decode(String.self, forKey: .status)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        mascot = try container.decode(String.self, forKey: .mascot)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        stars = try container.decodeIfPresent(Int.self, forKey: .stars)
        skillTargetsJson = try container.decodeIfPresent(String.self, forKey: .skillTargetsJson)
        recurringDaysJson = try container.decodeIfPresent(String.self, forKey: .recurringDaysJson)
        defaultSessionTime = try container.decodeIfPresent(Date.self, forKey: .defaultSessionTime)
        defaultSessionDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultSessionDurationMinutes) ?? 90
        locationId = try container.decodeIfPresent(UUID.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        usesPhases = try container.decodeIfPresent(Bool.self, forKey: .usesPhases) ?? true  // Default to true for backward compatibility
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    init(from program: Program) {
        self.id = program.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.name = program.name
        self.ageGroup = program.ageGroup.rawValue
        self.durationWeeks = program.durationWeeks
        self.programDescription = program.description
        self.objectives = program.objectives
        self.enrolledStudentIds = program.enrolledStudentIds
        self.coachId = program.coachId
        self.createdByCoachId = program.createdByCoachId
        self.status = program.status.rawValue
        self.colorHex = program.colorHex
        self.mascot = program.mascot.rawValue
        self.startDate = program.startDate
        self.endDate = program.endDate
        self.stars = program.stars.rawValue
        // Encode skill targets as JSON string
        if let targets = program.skillTargets,
           let data = try? JSONEncoder().encode(targets),
           let jsonString = String(data: data, encoding: .utf8) {
            self.skillTargetsJson = jsonString
        } else {
            self.skillTargetsJson = nil
        }
        // Encode recurring days as JSON string
        if !program.recurringDays.isEmpty,
           let data = try? JSONEncoder().encode(program.recurringDays.map { $0.rawValue }),
           let jsonString = String(data: data, encoding: .utf8) {
            self.recurringDaysJson = jsonString
        } else {
            self.recurringDaysJson = nil
        }
        self.defaultSessionTime = program.defaultSessionTime
        self.defaultSessionDurationMinutes = program.defaultSessionDurationMinutes
        self.locationId = program.locationId
        self.locationName = program.locationName
        self.usesPhases = program.usesPhases
        self.createdAt = program.createdAt
        self.updatedAt = program.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(name, forKey: .name)
        try container.encode(ageGroup, forKey: .ageGroup)
        try container.encode(durationWeeks, forKey: .durationWeeks)
        try container.encode(programDescription, forKey: .programDescription)
        try container.encode(objectives, forKey: .objectives)
        try container.encode(enrolledStudentIds, forKey: .enrolledStudentIds)
        try container.encode(coachId, forKey: .coachId)
        try container.encode(createdByCoachId, forKey: .createdByCoachId)
        try container.encode(status, forKey: .status)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(mascot, forKey: .mascot)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(stars, forKey: .stars)
        try container.encode(skillTargetsJson, forKey: .skillTargetsJson)
        try container.encode(recurringDaysJson, forKey: .recurringDaysJson)
        try container.encode(defaultSessionTime, forKey: .defaultSessionTime)
        try container.encode(defaultSessionDurationMinutes, forKey: .defaultSessionDurationMinutes)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(locationName, forKey: .locationName)
        try container.encode(usesPhases, forKey: .usesPhases)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toProgram() -> Program {
        // Decode skill targets from JSON string
        var skillTargets: ProgramSkillTargets? = nil
        if let jsonString = skillTargetsJson,
           let data = jsonString.data(using: .utf8) {
            skillTargets = try? JSONDecoder().decode(ProgramSkillTargets.self, from: data)
        }
        
        // Decode recurring days from JSON string
        var recurringDays: [Weekday] = []
        if let jsonString = recurringDaysJson,
           let data = jsonString.data(using: .utf8),
           let rawValues = try? JSONDecoder().decode([Int].self, from: data) {
            recurringDays = rawValues.compactMap { Weekday(rawValue: $0) }
        }
        
        var program = Program(
            id: id,
            name: name,
            ageGroup: AgeGroup(rawValue: ageGroup) ?? .u12,
            durationWeeks: durationWeeks,
            description: programDescription,
            objectives: objectives,
            enrolledStudentIds: enrolledStudentIds,
            coachId: coachId,
            createdByCoachId: createdByCoachId,
            status: ProgramStatus(rawValue: status) ?? .active,
            colorHex: colorHex,
            mascot: ProgramMascot(rawValue: mascot) ?? .tiger,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            stars: ProgramStars(rawValue: stars ?? 1) ?? .one,
            recurringDays: recurringDays,
            defaultSessionTime: defaultSessionTime,
            defaultSessionDurationMinutes: defaultSessionDurationMinutes,
            locationId: locationId,
            locationName: locationName,
            usesPhases: usesPhases
        )
        program.skillTargets = skillTargets
        return program
    }
}

// MARK: - Session Event DTO
struct SupabaseSessionEvent: Codable {
    let id: UUID
    var organizationId: UUID?
    var programId: UUID?
    var microCycleId: UUID?
    var title: String
    var sessionType: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var location: String?
    var status: String
    var curriculum: SessionCurriculum
    var attendeeIds: [UUID]
    var actualAttendeeIds: [UUID]
    var excusedAbsences: [UUID]
    var attendancePhotoPath: String?
    var notes: String?
    var coachNotes: String?
    var developmentFocus: [String]  // TrainingFocus raw values
    var manOfTheMatchId: UUID?  // Required field in Supabase schema
    var drillsCompleted: [UUID]  // Required field in Supabase schema
    var rating: Int?  // Required field in Supabase schema
    var createdByCoachId: UUID?  // Coach who created this session
    var assignedCoachIds: [UUID]  // Coaches assigned to co-coach this session
    var games: [SessionGame]
    var headerImageURL: String?
    var boardNotesJson: String?   // [BoardNote] serialized as JSON for cross-device sync
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, programId, microCycleId, title, sessionType, date
        case startTime, endTime, location, status, curriculum
        case attendeeIds, actualAttendeeIds, excusedAbsences, attendancePhotoPath, notes, coachNotes
        case developmentFocus, manOfTheMatchId, drillsCompleted, rating, createdByCoachId, assignedCoachIds, games, headerImageURL
        case boardNotesJson, createdAt, updatedAt
    }
    
    // Custom decode to handle null games array from Supabase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        organizationId = try container.decodeIfPresent(UUID.self, forKey: .organizationId)
        programId = try container.decodeIfPresent(UUID.self, forKey: .programId)
        microCycleId = try container.decodeIfPresent(UUID.self, forKey: .microCycleId)
        title = try container.decode(String.self, forKey: .title)
        sessionType = try container.decode(String.self, forKey: .sessionType)
        date = try container.decode(Date.self, forKey: .date)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        status = try container.decode(String.self, forKey: .status)
        curriculum = try container.decodeIfPresent(SessionCurriculum.self, forKey: .curriculum) ?? SessionCurriculum()
        attendeeIds = try container.decodeIfPresent([UUID].self, forKey: .attendeeIds) ?? []
        actualAttendeeIds = try container.decodeIfPresent([UUID].self, forKey: .actualAttendeeIds) ?? []
        excusedAbsences = try container.decodeIfPresent([UUID].self, forKey: .excusedAbsences) ?? []
        attendancePhotoPath = try container.decodeIfPresent(String.self, forKey: .attendancePhotoPath)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        coachNotes = try container.decodeIfPresent(String.self, forKey: .coachNotes)
        developmentFocus = try container.decodeIfPresent([String].self, forKey: .developmentFocus) ?? []
        manOfTheMatchId = try container.decodeIfPresent(UUID.self, forKey: .manOfTheMatchId)
        drillsCompleted = try container.decodeIfPresent([UUID].self, forKey: .drillsCompleted) ?? []
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        createdByCoachId = try container.decodeIfPresent(UUID.self, forKey: .createdByCoachId)
        assignedCoachIds = try container.decodeIfPresent([UUID].self, forKey: .assignedCoachIds) ?? []
        games = try container.decodeIfPresent([SessionGame].self, forKey: .games) ?? []
        headerImageURL = try container.decodeIfPresent(String.self, forKey: .headerImageURL)
        boardNotesJson = try container.decodeIfPresent(String.self, forKey: .boardNotesJson)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    init(from session: SessionEvent, organizationId: UUID? = nil) {
        self.id = session.id
        self.organizationId = organizationId ?? AuthManager.shared.currentOrganization?.id
        self.programId = session.programId
        self.microCycleId = session.microCycleId
        self.title = session.title
        self.sessionType = session.sessionType.rawValue
        self.date = session.date
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.location = session.location
        self.status = session.status.rawValue
        self.curriculum = session.curriculum
        self.attendeeIds = session.attendeeIds
        self.actualAttendeeIds = session.actualAttendeeIds
        self.excusedAbsences = session.excusedAbsences
        self.attendancePhotoPath = session.attendancePhotoPath
        self.notes = session.notes
        self.coachNotes = session.coachNotes
        self.developmentFocus = session.developmentFocus.map { $0.rawValue }
        self.manOfTheMatchId = session.manOfTheMatchId
        self.drillsCompleted = session.drillsCompleted
        self.rating = session.rating
        self.createdByCoachId = session.createdByCoachId
        self.assignedCoachIds = session.assignedCoachIds
        self.games = session.games
        self.headerImageURL = session.headerImageURL
        // boardNotesJson is managed separately by BoardNotesStore — not sourced from SessionEvent
        self.boardNotesJson = nil
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(programId, forKey: .programId)
        try container.encode(microCycleId, forKey: .microCycleId)
        try container.encode(title, forKey: .title)
        try container.encode(sessionType, forKey: .sessionType)
        try container.encode(date, forKey: .date)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(location, forKey: .location)
        try container.encode(status, forKey: .status)
        try container.encode(curriculum, forKey: .curriculum)
        try container.encode(attendeeIds, forKey: .attendeeIds)
        try container.encode(actualAttendeeIds, forKey: .actualAttendeeIds)
        try container.encode(excusedAbsences, forKey: .excusedAbsences)
        try container.encode(attendancePhotoPath, forKey: .attendancePhotoPath)
        try container.encode(notes, forKey: .notes)
        try container.encode(coachNotes, forKey: .coachNotes)
        try container.encode(developmentFocus, forKey: .developmentFocus)
        try container.encode(manOfTheMatchId, forKey: .manOfTheMatchId)
        try container.encode(drillsCompleted, forKey: .drillsCompleted)
        try container.encode(rating, forKey: .rating)
        try container.encode(createdByCoachId, forKey: .createdByCoachId)
        try container.encode(assignedCoachIds, forKey: .assignedCoachIds)
        try container.encode(games, forKey: .games)
        // headerImageURL not in Supabase schema - skip encoding
        // boardNotesJson is managed separately by BoardNotesStore — skip encoding here to avoid overwriting
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toSessionEvent() -> SessionEvent {
        SessionEvent(
            id: id,
            microCycleId: microCycleId,
            programId: programId,
            sessionType: SessionType(rawValue: sessionType) ?? .training,
            title: title,
            date: date,
            startTime: startTime,
            endTime: endTime,
            location: location,
            status: SessionEventStatus(rawValue: status) ?? .scheduled,
            curriculum: curriculum,
            attendeeIds: attendeeIds,
            actualAttendeeIds: actualAttendeeIds,
            excusedAbsences: excusedAbsences,
            attendancePhotoPath: attendancePhotoPath,
            notes: notes,
            coachNotes: coachNotes,
            developmentFocus: developmentFocus.compactMap { TrainingFocus(rawValue: $0) },
            manOfTheMatchId: manOfTheMatchId,
            drillsCompleted: drillsCompleted,
            rating: rating,
            createdByCoachId: createdByCoachId,
            assignedCoachIds: assignedCoachIds,
            games: games,
            headerImageURL: headerImageURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Measurement DTO
struct SupabaseMeasurement: Codable {
    let id: UUID
    var studentId: UUID
    var sessionId: UUID?
    var measurementType: String
    var value: Double
    var notes: String?
    var recordedAt: Date
    var recordedBy: String?
    
    enum CodingKeys: String, CodingKey {
        case id, studentId, sessionId, measurementType, value, notes, recordedAt, recordedBy
    }
    
    init(from measurement: PlayerMeasurement) {
        self.id = measurement.id
        self.studentId = measurement.studentId
        self.sessionId = measurement.sessionId
        self.measurementType = measurement.type.rawValue
        self.value = measurement.value
        self.notes = measurement.notes
        self.recordedAt = measurement.recordedAt
        self.recordedBy = measurement.recordedBy
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(studentId, forKey: .studentId)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(measurementType, forKey: .measurementType)
        try container.encode(value, forKey: .value)
        try container.encode(notes, forKey: .notes)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(recordedBy, forKey: .recordedBy)
    }
    
    func toMeasurement() -> PlayerMeasurement {
        PlayerMeasurement(
            id: id,
            studentId: studentId,
            type: MeasurementType(rawValue: measurementType) ?? .height,
            value: value,
            sessionId: sessionId,
            notes: notes,
            recordedAt: recordedAt,
            recordedBy: recordedBy
        )
    }
}

// MARK: - Drill DTO
struct SupabaseDrill: Codable {
    let id: UUID
    var name: String
    var drillDescription: String
    var category: String
    var difficulty: String
    var durationMinutes: Int
    var equipmentNeeded: [String]
    var instructions: [String]
    var keyPoints: [String]
    var variations: [String]
    var minPlayers: Int
    var maxPlayers: Int?
    var videoUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case drillDescription = "description"
        case category, difficulty, durationMinutes, equipmentNeeded
        case instructions, keyPoints, variations, minPlayers, maxPlayers
        case videoUrl, tags, isFavorite
        case createdAt, updatedAt
    }
    
    init(from drill: DrillItem) {
        self.id = drill.id
        self.name = drill.name
        self.drillDescription = drill.description
        self.category = drill.category.rawValue
        self.difficulty = drill.difficulty.rawValue
        self.durationMinutes = drill.durationMinutes
        self.equipmentNeeded = drill.equipmentNeeded
        self.instructions = drill.instructions
        self.keyPoints = drill.keyPoints
        self.variations = drill.variations
        self.minPlayers = drill.minPlayers
        self.maxPlayers = drill.maxPlayers
        self.videoUrl = drill.videoUrl
        self.tags = drill.tags
        self.isFavorite = drill.isFavorite
        self.createdAt = drill.createdAt
        self.updatedAt = drill.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(drillDescription, forKey: .drillDescription)
        try container.encode(category, forKey: .category)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(equipmentNeeded, forKey: .equipmentNeeded)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(keyPoints, forKey: .keyPoints)
        try container.encode(variations, forKey: .variations)
        try container.encode(minPlayers, forKey: .minPlayers)
        try container.encode(maxPlayers, forKey: .maxPlayers) // Always encode, even if nil
        try container.encode(videoUrl, forKey: .videoUrl) // Always encode, even if nil
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toDrill() -> DrillItem {
        DrillItem(
            id: id,
            name: name,
            category: DrillCategory(rawValue: category) ?? .warmup,
            difficulty: DifficultyLevel(rawValue: difficulty) ?? .beginner,
            durationMinutes: durationMinutes,
            description: drillDescription,
            instructions: instructions,
            keyPoints: keyPoints,
            equipmentNeeded: equipmentNeeded,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            variations: variations,
            videoUrl: videoUrl,
            tags: tags,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Staff Coach DTO
struct SupabaseStaffCoach: Codable {
    let id: UUID
    var organizationId: UUID?  // Required for multi-org filtering
    var name: String
    var chineseName: String?
    var email: String?
    var phone: String?
    var role: String
    var accessLevel: String
    var specializations: [String]
    var ageGroups: [String]
    var avatarColor: String
    var isActive: Bool
    var hireDate: Date?
    var notes: String?
    var profileImageUrl: String?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, name, chineseName, email, phone, role, accessLevel, specializations, ageGroups, avatarColor, isActive, hireDate, notes, profileImageUrl, createdAt, updatedAt
    }
    
    init(from coach: StaffCoach) {
        self.id = coach.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.name = coach.name
        self.chineseName = coach.chineseName
        self.email = coach.email
        self.phone = coach.phone
        self.role = coach.role.rawValue
        self.accessLevel = coach.accessLevel.rawValue
        self.specializations = coach.specializations
        self.ageGroups = coach.ageGroups.map { $0.rawValue }
        self.avatarColor = coach.avatarColor.rawValue
        self.isActive = coach.isActive
        self.hireDate = coach.hireDate
        self.notes = coach.notes
        self.profileImageUrl = coach.profileImageUrl
        self.createdAt = coach.createdAt
        self.updatedAt = coach.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(name, forKey: .name)
        try container.encode(chineseName, forKey: .chineseName)
        try container.encode(email, forKey: .email)
        try container.encode(phone, forKey: .phone)
        try container.encode(role, forKey: .role)
        try container.encode(accessLevel, forKey: .accessLevel)
        try container.encode(specializations, forKey: .specializations)
        try container.encode(ageGroups, forKey: .ageGroups)
        try container.encode(avatarColor, forKey: .avatarColor)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(hireDate, forKey: .hireDate)
        try container.encode(notes, forKey: .notes)
        try container.encode(profileImageUrl, forKey: .profileImageUrl)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toStaffCoach() -> StaffCoach {
        StaffCoach(
            id: id,
            organizationId: organizationId,
            name: name,
            chineseName: chineseName,
            email: email,
            phone: phone,
            role: CoachRole(rawValue: role) ?? .assistant,
            accessLevel: AccessLevel(rawValue: accessLevel) ?? .coachingStaff,
            specializations: specializations,
            ageGroups: ageGroups.compactMap { AgeGroup(rawValue: $0) },
            avatarColor: AvatarColor(rawValue: avatarColor) ?? .blue,
            isActive: isActive,
            hireDate: hireDate,
            notes: notes,
            profileImageUrl: profileImageUrl,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Location DTO
struct SupabaseLocation: Codable {
    let id: UUID
    var name: String
    var address: String?
    var city: String?
    var courtCount: Int
    var courtType: String
    var amenities: [String]
    var capacity: Int?  // Maps to 'capacity' column in Supabase
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(from location: Location) {
        self.id = location.id
        self.name = location.name
        self.address = location.address
        self.city = location.city
        self.courtCount = location.courtCount
        self.courtType = location.courtType.rawValue
        self.amenities = location.amenities
        self.capacity = location.maxCapacity
        self.isActive = location.isActive
        self.createdAt = location.createdAt
        self.updatedAt = location.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(city, forKey: .city)
        try container.encode(courtCount, forKey: .courtCount)
        try container.encode(courtType, forKey: .courtType)
        try container.encode(amenities, forKey: .amenities)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, address, city, courtCount, courtType, amenities, capacity, isActive, createdAt, updatedAt
    }
    
    func toLocation() -> Location {
        Location(
            id: id,
            name: name,
            address: address,
            city: city,
            courtCount: courtCount,
            courtType: CourtType(rawValue: courtType) ?? .indoor,
            amenities: amenities,
            maxCapacity: capacity,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Play DTO
struct SupabasePlay: Codable {
    let id: UUID
    var name: String
    var category: String
    var formation: String
    var playDescription: String
    var keyTeachingPoints: [String]
    var steps: [PlayStepDTO]
    var variations: [String]
    var bestUsedAgainst: String?
    var difficulty: String
    var diagramUrl: String?
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    struct PlayStepDTO: Codable {
        let id: UUID
        var stepNumber: Int
        var description: String
        var keyPoint: String?
    }
    
    init(from play: Play) {
        self.id = play.id
        self.name = play.name
        self.category = play.category.rawValue
        self.formation = play.formation
        self.playDescription = play.description
        self.keyTeachingPoints = play.keyTeachingPoints
        self.steps = play.steps.map { PlayStepDTO(id: $0.id, stepNumber: $0.stepNumber, description: $0.description, keyPoint: $0.keyPoint) }
        self.variations = play.variations
        self.bestUsedAgainst = play.bestUsedAgainst
        self.difficulty = play.difficulty.rawValue
        self.diagramUrl = play.diagramUrl
        self.tags = play.tags
        self.isFavorite = play.isFavorite
        self.createdAt = play.createdAt
        self.updatedAt = play.updatedAt
    }
    
    func toPlay() -> Play {
        Play(
            id: id,
            name: name,
            category: PlayCategory(rawValue: category) ?? .setPlays,
            formation: formation,
            description: playDescription,
            keyTeachingPoints: keyTeachingPoints,
            steps: steps.map { PlayStep(id: $0.id, stepNumber: $0.stepNumber, description: $0.description, keyPoint: $0.keyPoint) },
            variations: variations,
            bestUsedAgainst: bestUsedAgainst,
            difficulty: DifficultyLevel(rawValue: difficulty) ?? .intermediate,
            diagramUrl: diagramUrl,
            tags: tags,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Team DTO
struct SupabaseTeam: Codable {
    let id: UUID
    var name: String
    var shortName: String
    var colorHex: String
    var secondaryColorHex: String
    var logoSystemImage: String
    var mascotTypeRaw: String?
    var playerIds: [UUID]
    var coachName: String?
    var homeVenue: String?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, shortName, colorHex, secondaryColorHex, logoSystemImage
        case mascotTypeRaw, playerIds, coachName, homeVenue, createdAt, updatedAt
    }
    
    init(from team: Team) {
        self.id = team.id
        self.name = team.name
        self.shortName = team.shortName
        self.colorHex = team.colorHex
        self.secondaryColorHex = team.secondaryColorHex
        self.logoSystemImage = team.logoSystemImage
        self.mascotTypeRaw = team.mascotTypeRaw
        self.playerIds = team.playerIds
        self.coachName = team.coachName
        self.homeVenue = team.homeVenue
        self.createdAt = team.createdAt
        self.updatedAt = team.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(shortName, forKey: .shortName)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(secondaryColorHex, forKey: .secondaryColorHex)
        try container.encode(logoSystemImage, forKey: .logoSystemImage)
        try container.encode(mascotTypeRaw, forKey: .mascotTypeRaw)
        try container.encode(playerIds, forKey: .playerIds)
        try container.encode(coachName, forKey: .coachName)
        try container.encode(homeVenue, forKey: .homeVenue)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toTeam() -> Team {
        Team(
            id: id,
            name: name,
            shortName: shortName,
            colorHex: colorHex,
            secondaryColorHex: secondaryColorHex,
            logoSystemImage: logoSystemImage,
            mascotType: mascotTypeRaw.flatMap { TeamMascotType(rawValue: $0) },
            playerIds: playerIds,
            coachName: coachName,
            homeVenue: homeVenue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Game DTO
struct SupabaseGame: Codable {
    let id: UUID
    var homeTeamId: UUID
    var awayTeamId: UUID
    var homeScore: Int
    var awayScore: Int
    var date: Date
    var venue: String?
    var status: String
    var quarter: Int?
    var timeRemaining: String?
    var notes: String?
    var playerStats: [PlayerGameStats]
    var scoringPlays: [ScoringPlay]
    var quarterScores: [QuarterScore]
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, homeTeamId, awayTeamId, homeScore, awayScore, date, venue, status
        case quarter, timeRemaining, notes, playerStats, scoringPlays, quarterScores
        case createdAt, updatedAt
    }
    
    init(from game: Game) {
        self.id = game.id
        self.homeTeamId = game.homeTeamId
        self.awayTeamId = game.awayTeamId
        self.homeScore = game.homeScore
        self.awayScore = game.awayScore
        self.date = game.date
        self.venue = game.venue
        self.status = game.status.rawValue
        self.quarter = game.quarter
        self.timeRemaining = game.timeRemaining
        self.notes = game.notes
        self.playerStats = game.playerStats
        self.scoringPlays = game.scoringPlays
        self.quarterScores = game.quarterScores
        self.createdAt = game.createdAt
        self.updatedAt = game.updatedAt
    }
    
    // Custom encode to always include all keys (fixes PGRST102)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(homeTeamId, forKey: .homeTeamId)
        try container.encode(awayTeamId, forKey: .awayTeamId)
        try container.encode(homeScore, forKey: .homeScore)
        try container.encode(awayScore, forKey: .awayScore)
        try container.encode(date, forKey: .date)
        try container.encode(venue, forKey: .venue)
        try container.encode(status, forKey: .status)
        try container.encode(quarter, forKey: .quarter)
        try container.encode(timeRemaining, forKey: .timeRemaining)
        try container.encode(notes, forKey: .notes)
        try container.encode(playerStats, forKey: .playerStats)
        try container.encode(scoringPlays, forKey: .scoringPlays)
        try container.encode(quarterScores, forKey: .quarterScores)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toGame() -> Game {
        Game(
            id: id,
            homeTeamId: homeTeamId,
            awayTeamId: awayTeamId,
            homeScore: homeScore,
            awayScore: awayScore,
            date: date,
            venue: venue,
            status: GameStatus(rawValue: status) ?? .scheduled,
            quarter: quarter,
            timeRemaining: timeRemaining,
            notes: notes,
            playerStats: playerStats,
            scoringPlays: scoringPlays,
            quarterScores: quarterScores,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Micro Cycle DTO
struct SupabaseMicroCycle: Codable {
    let id: UUID
    var organizationId: UUID?
    var programId: UUID
    var phaseNumber: Int
    var title: String
    var focus: [String]
    var durationWeeks: Int
    var intensity: String  // Required field in Supabase schema
    var microCycleDescription: String?
    var objectives: [String]
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, programId, phaseNumber, title, focus, durationWeeks, intensity
        case microCycleDescription = "description"
        case objectives, startDate, endDate, createdAt, updatedAt
    }
    
    init(from microCycle: MicroCycle) {
        self.id = microCycle.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.programId = microCycle.programId
        self.phaseNumber = microCycle.phaseNumber
        self.title = microCycle.title
        self.focus = microCycle.focus.map { $0.rawValue }
        self.durationWeeks = microCycle.durationWeeks
        // Map intensity value (1-10) to text description for Supabase
        self.intensity = microCycle.intensity <= 3 ? "low" : microCycle.intensity <= 6 ? "moderate" : "high"
        self.microCycleDescription = microCycle.description
        self.objectives = microCycle.objectives
        self.startDate = microCycle.startDate
        self.endDate = microCycle.endDate
        self.createdAt = microCycle.createdAt
        self.updatedAt = microCycle.updatedAt
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(programId, forKey: .programId)
        try container.encode(phaseNumber, forKey: .phaseNumber)
        try container.encode(title, forKey: .title)
        try container.encode(focus, forKey: .focus)
        try container.encode(durationWeeks, forKey: .durationWeeks)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(microCycleDescription, forKey: .microCycleDescription)
        try container.encode(objectives, forKey: .objectives)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toMicroCycle() -> MicroCycle {
        // Convert text intensity back to numeric value
        let intensityValue: Int = {
            switch intensity.lowercased() {
            case "low": return 3
            case "moderate": return 5
            case "high": return 8
            default: return 5
            }
        }()
        
        return MicroCycle(
            id: id,
            programId: programId,
            phaseNumber: phaseNumber,
            title: title,
            focus: focus.compactMap { TrainingFocus(rawValue: $0) },
            durationWeeks: durationWeeks,
            description: microCycleDescription,
            objectives: objectives,
            startDate: startDate,
            endDate: endDate,
            intensity: intensityValue,
            volume: 5,  // Default value since not in cloud schema
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Team Standing DTO
struct SupabaseTeamStanding: Codable {
    let id: UUID
    var teamId: UUID
    var wins: Int
    var losses: Int
    var pointsFor: Int
    var pointsAgainst: Int
    var streak: Int
    var lastFiveResults: [Bool]
    var createdAt: Date
    var updatedAt: Date
    
    init(from standing: TeamStanding) {
        self.id = standing.id
        self.teamId = standing.teamId
        self.wins = standing.wins
        self.losses = standing.losses
        self.pointsFor = standing.pointsFor
        self.pointsAgainst = standing.pointsAgainst
        self.streak = standing.streak
        self.lastFiveResults = standing.lastFiveResults
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func toTeamStanding() -> TeamStanding {
        TeamStanding(
            id: id,
            teamId: teamId,
            wins: wins,
            losses: losses,
            pointsFor: pointsFor,
            pointsAgainst: pointsAgainst,
            streak: streak,
            lastFiveResults: lastFiveResults
        )
    }
}

// MARK: - Age Category DTO
struct SupabaseAgeCategory: Codable {
    let id: UUID
    var organizationId: UUID?
    var name: String
    var shortName: String
    var minAge: Int
    var maxAge: Int
    var colorHex: String
    var ballSize: String
    var rimHeight: String
    var description: String?
    var isActive: Bool
    var customIconBase64: String?  // Base64 encoded image data
    var mascotNameOverride: String?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, organizationId, name, shortName, minAge, maxAge, colorHex
        case ballSize, rimHeight, description, isActive
        case customIconBase64, mascotNameOverride, createdAt, updatedAt
    }
    
    init(from category: CustomAgeCategory) {
        self.id = category.id
        self.organizationId = AuthManager.shared.currentOrganization?.id
        self.name = category.name
        self.shortName = category.shortName
        self.minAge = category.minAge
        self.maxAge = category.maxAge
        self.colorHex = category.colorHex
        self.ballSize = category.ballSize.rawValue
        self.rimHeight = category.rimHeight.rawValue
        self.description = category.description
        self.isActive = category.isActive
        // Encode custom icon data as Base64 string for storage
        if let iconData = category.customIconData {
            self.customIconBase64 = iconData.base64EncodedString()
        } else {
            self.customIconBase64 = nil
        }
        self.mascotNameOverride = category.mascotNameOverride
        self.createdAt = category.createdAt
        self.updatedAt = category.updatedAt
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(organizationId, forKey: .organizationId)
        try container.encode(name, forKey: .name)
        try container.encode(shortName, forKey: .shortName)
        try container.encode(minAge, forKey: .minAge)
        try container.encode(maxAge, forKey: .maxAge)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(ballSize, forKey: .ballSize)
        try container.encode(rimHeight, forKey: .rimHeight)
        try container.encode(description, forKey: .description)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(customIconBase64, forKey: .customIconBase64)
        try container.encode(mascotNameOverride, forKey: .mascotNameOverride)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toAgeCategory() -> CustomAgeCategory {
        // Decode Base64 icon data
        var iconData: Data? = nil
        if let base64String = customIconBase64 {
            iconData = Data(base64Encoded: base64String)
        }
        
        return CustomAgeCategory(
            id: id,
            name: name,
            shortName: shortName,
            minAge: minAge,
            maxAge: maxAge,
            colorHex: colorHex,
            ballSize: BallSize(rawValue: ballSize) ?? .size5,
            rimHeight: RimHeight(rawValue: rimHeight) ?? .feet10,
            description: description,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            customIconData: iconData,
            mascotNameOverride: mascotNameOverride
        )
    }
}
