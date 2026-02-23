import Foundation

/// Generates rich sample data for guest/demo mode (screenshot-ready)
/// All IDs use 00000000- prefix so clearSampleDataIfNeeded() can remove them cleanly
class SampleDataGenerator {
    static let shared = SampleDataGenerator()
    
    private init() {}
    
    // MARK: - Deterministic UUIDs (00000000- prefix for easy cleanup)
    
    // Coach
    static let coachId       = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    // Staff Coaches
    static let staffCoach1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    static let staffCoach2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    static let staffCoach3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    
    // Students
    static let student1Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let student2Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let student3Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let student4Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    static let student5Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
    static let student6Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
    static let student7Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
    static let student8Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
    static let student9Id  = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!
    static let student10Id = UUID(uuidString: "00000000-0000-0000-0000-000000000110")!
    
    // Programs
    static let program1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let program2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    static let program3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    
    // Phases (MicroCycles)
    static let phase1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    static let phase2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    static let phase3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
    static let phase4Id = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!
    
    // Sessions
    static let session1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    static let session2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
    static let session3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
    static let session4Id = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
    static let session5Id = UUID(uuidString: "00000000-0000-0000-0000-000000000405")!
    static let session6Id = UUID(uuidString: "00000000-0000-0000-0000-000000000406")!
    static let session7Id = UUID(uuidString: "00000000-0000-0000-0000-000000000407")!
    static let session8Id = UUID(uuidString: "00000000-0000-0000-0000-000000000408")!
    
    // Contracts
    static let contract1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    static let contract2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
    static let contract3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
    static let contract4Id = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
    static let contract5Id = UUID(uuidString: "00000000-0000-0000-0000-000000000505")!
    
    // Players
    static let player1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    static let player2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
    static let player3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
    static let player4Id = UUID(uuidString: "00000000-0000-0000-0000-000000000604")!
    static let player5Id = UUID(uuidString: "00000000-0000-0000-0000-000000000605")!
    
    private let cal = Calendar.current
    
    // MARK: - Generate Sample Coach (main profile)
    func generateSampleCoach() -> Coach {
        Coach(
            id: Self.coachId,
            name: "Marcus Rivera",
            email: "marcus@sampleacademy.com",
            phone: "+1 555-0100",
            introduction: "Head coach at Sample Academy with 12 years of experience developing youth basketball talent. Focused on fundamentals, character building, and competitive excellence.",
            yearsOfExperience: 12,
            certifications: ["FIBA Level 3", "USA Basketball Gold License", "First Aid & CPR"],
            specializations: ["Youth Development", "Shooting Mechanics", "Team Defense", "Player Evaluation"],
            achievements: ["Regional U14 Champions 2024", "Coach of the Year 2023", "50+ athletes placed in high school programs"]
        )
    }
    
    // MARK: - Staff Coaches
    func generateStaffCoaches() -> [StaffCoach] {
        [
            StaffCoach(
                id: Self.staffCoach1Id,
                name: "Marcus Rivera",
                email: "marcus@sampleacademy.com",
                phone: "+1 555-0100",
                role: .head,
                accessLevel: .admin,
                specializations: ["Offense", "Player Development", "Game Strategy"],
                ageGroups: [.u12, .u14, .u16],
                avatarColor: .purple,
                isActive: true,
                hireDate: cal.date(byAdding: .year, value: -5, to: Date())
            ),
            StaffCoach(
                id: Self.staffCoach2Id,
                name: "Aisha Thompson",
                email: "aisha@sampleacademy.com",
                phone: "+1 555-0101",
                role: .assistant,
                accessLevel: .coachingStaff,
                specializations: ["Defense", "Conditioning", "Guard Development"],
                ageGroups: [.u10, .u12],
                avatarColor: .teal,
                isActive: true,
                hireDate: cal.date(byAdding: .year, value: -3, to: Date())
            ),
            StaffCoach(
                id: Self.staffCoach3Id,
                name: "David Park",
                email: "david@sampleacademy.com",
                role: .assistant,
                accessLevel: .coachingStaff,
                specializations: ["Shooting", "Big Man Development"],
                ageGroups: [.u14, .u16],
                avatarColor: .blue,
                isActive: true,
                hireDate: cal.date(byAdding: .year, value: -1, to: Date())
            )
        ]
    }
    
    // MARK: - Students
    func generateStudents() -> [Student] {
        let colors: [AvatarColor] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo]
        return [
            Student(id: Self.student1Id, name: "Jaylen Carter", avatarColor: colors[0],
                    schoolGrade: .highschool1, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student2Id, name: "Sofia Martinez", avatarColor: colors[1],
                    schoolGrade: .primary6, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student3Id, name: "Ethan Brooks", avatarColor: colors[2],
                    schoolGrade: .highschool2, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student4Id, name: "Mia Johnson", avatarColor: colors[3],
                    schoolGrade: .primary5, createdByCoachId: Self.staffCoach2Id),
            Student(id: Self.student5Id, name: "Noah Williams", avatarColor: colors[4],
                    schoolGrade: .highschool1, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student6Id, name: "Ava Chen", avatarColor: colors[5],
                    schoolGrade: .primary4, createdByCoachId: Self.staffCoach2Id),
            Student(id: Self.student7Id, name: "Liam Davis", avatarColor: colors[6],
                    schoolGrade: .highschool3, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student8Id, name: "Emma Wilson", avatarColor: colors[7],
                    schoolGrade: .primary5, createdByCoachId: Self.staffCoach2Id),
            Student(id: Self.student9Id, name: "Lucas Brown", avatarColor: colors[0],
                    schoolGrade: .primary6, createdByCoachId: Self.staffCoach1Id),
            Student(id: Self.student10Id, name: "Olivia Taylor", avatarColor: colors[1],
                    schoolGrade: .highschool1, createdByCoachId: Self.staffCoach1Id),
        ]
    }
    
    // MARK: - Programs
    func generatePrograms() -> [Program] {
        let today = Date()
        let programStart = cal.date(byAdding: .month, value: -2, to: today)!
        let programEnd = cal.date(byAdding: .month, value: 2, to: today)!
        
        let u12Students = [Self.student2Id, Self.student4Id, Self.student6Id, Self.student8Id, Self.student9Id]
        let u14Students = [Self.student1Id, Self.student3Id, Self.student5Id, Self.student7Id, Self.student10Id]
        let privateStudents = [Self.student1Id, Self.student3Id]
        
        return [
            Program(
                id: Self.program1Id,
                name: "Saturday Skills",
                programType: .group,
                ageGroup: .u12,
                durationWeeks: 16,
                description: "Foundational skills program for young athletes. Focus on ball handling, shooting form, and teamwork.",
                objectives: ["Master basic dribbling moves", "Develop proper shooting mechanics", "Learn team defense concepts"],
                enrolledStudentIds: u12Students,
                coachId: Self.staffCoach2Id,
                createdByCoachId: Self.staffCoach1Id,
                status: .active,
                mascot: .eagle,
                startDate: programStart,
                endDate: programEnd,
                stars: .two,
                recurringDays: [.saturday],
                defaultSessionDurationMinutes: 90,
                locationName: "Main Gym"
            ),
            Program(
                id: Self.program2Id,
                name: "Elite Development",
                programType: .group,
                ageGroup: .u14,
                durationWeeks: 20,
                description: "Advanced program for competitive players preparing for high school tryouts.",
                objectives: ["Advanced offensive moves", "Defensive positioning & rotations", "Game IQ & decision making"],
                enrolledStudentIds: u14Students,
                coachId: Self.staffCoach1Id,
                createdByCoachId: Self.staffCoach1Id,
                status: .active,
                mascot: .dragon,
                startDate: programStart,
                endDate: programEnd,
                stars: .three,
                recurringDays: [.tuesday, .thursday],
                defaultSessionDurationMinutes: 120,
                locationName: "Court B"
            ),
            Program(
                id: Self.program3Id,
                name: "1-on-1 Shooting Lab",
                programType: .privateSessions,
                ageGroup: .u14,
                durationWeeks: 8,
                description: "Private shooting sessions focused on mechanics, footwork, and game-speed reps.",
                objectives: ["Fix shooting form", "Develop off-dribble shooting", "Increase 3-point range"],
                enrolledStudentIds: privateStudents,
                coachId: Self.staffCoach1Id,
                createdByCoachId: Self.staffCoach1Id,
                status: .active,
                mascot: .falcon,
                startDate: programStart,
                endDate: programEnd,
                stars: .four,
                recurringDays: [.wednesday],
                defaultSessionDurationMinutes: 60,
                locationName: "Shooting Bay",
                usesPhases: false
            )
        ]
    }
    
    // MARK: - Phases (MicroCycles)
    func generatePhases() -> [MicroCycle] {
        let today = Date()
        let weekAgo = cal.date(byAdding: .weekOfYear, value: -6, to: today)!
        
        return [
            // Program 1 phases
            MicroCycle(
                id: Self.phase1Id,
                programId: Self.program1Id,
                phaseNumber: 1,
                title: "Foundation",
                focus: [.ballHandling, .passing],
                durationWeeks: 4,
                description: "Building fundamental ball skills and court awareness",
                objectives: ["Crossover dribble", "Chest & bounce pass", "Triple threat position"],
                startDate: weekAgo,
                endDate: cal.date(byAdding: .weekOfYear, value: 4, to: weekAgo),
                intensity: 4,
                volume: 6
            ),
            MicroCycle(
                id: Self.phase2Id,
                programId: Self.program1Id,
                phaseNumber: 2,
                title: "Shooting Form",
                focus: [.shooting],
                durationWeeks: 4,
                description: "Developing proper shooting mechanics from close range to mid-range",
                objectives: ["BEEF technique", "Layup footwork", "Free throw routine"],
                startDate: cal.date(byAdding: .weekOfYear, value: 4, to: weekAgo),
                endDate: cal.date(byAdding: .weekOfYear, value: 8, to: weekAgo),
                intensity: 5,
                volume: 7
            ),
            // Program 2 phases
            MicroCycle(
                id: Self.phase3Id,
                programId: Self.program2Id,
                phaseNumber: 1,
                title: "Offensive Toolkit",
                focus: [.shooting, .ballHandling],
                durationWeeks: 5,
                description: "Expanding offensive repertoire with advanced moves",
                objectives: ["Step-back jumper", "Euro step", "Pick & roll reads"],
                startDate: weekAgo,
                endDate: cal.date(byAdding: .weekOfYear, value: 5, to: weekAgo),
                intensity: 7,
                volume: 8
            ),
            MicroCycle(
                id: Self.phase4Id,
                programId: Self.program2Id,
                phaseNumber: 2,
                title: "Defensive Intensity",
                focus: [.defense, .conditioning],
                durationWeeks: 5,
                description: "Building defensive habits and competitive conditioning",
                objectives: ["On-ball pressure", "Help-side rotations", "Closeout technique"],
                startDate: cal.date(byAdding: .weekOfYear, value: 5, to: weekAgo),
                endDate: cal.date(byAdding: .weekOfYear, value: 10, to: weekAgo),
                intensity: 8,
                volume: 7
            )
        ]
    }
    
    // MARK: - Sessions
    func generateSessions() -> [SessionEvent] {
        let today = Date()
        let u12Students = [Self.student2Id, Self.student4Id, Self.student6Id, Self.student8Id, Self.student9Id]
        let u14Students = [Self.student1Id, Self.student3Id, Self.student5Id, Self.student7Id, Self.student10Id]
        let privateStudents = [Self.student1Id, Self.student3Id]
        
        func makeTime(daysOffset: Int, hour: Int, minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: daysOffset, to: today)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        
        return [
            // Past completed sessions (Program 1 - U12)
            SessionEvent(
                id: Self.session1Id,
                microCycleId: Self.phase1Id,
                programId: Self.program1Id,
                title: "Ball Handling Basics",
                date: makeTime(daysOffset: -14, hour: 10, minute: 0),
                startTime: makeTime(daysOffset: -14, hour: 10, minute: 0),
                endTime: makeTime(daysOffset: -14, hour: 11, minute: 30),
                location: "Main Gym",
                status: .completed,
                attendeeIds: u12Students,
                actualAttendeeIds: Array(u12Students.prefix(4)),
                coachNotes: "Great energy today. Sofia and Ava showed real improvement on crossover drills.",
                developmentFocus: [.ballHandling],
                rating: 4,
                createdByCoachId: Self.staffCoach2Id
            ),
            SessionEvent(
                id: Self.session2Id,
                microCycleId: Self.phase1Id,
                programId: Self.program1Id,
                title: "Passing & Court Vision",
                date: makeTime(daysOffset: -7, hour: 10, minute: 0),
                startTime: makeTime(daysOffset: -7, hour: 10, minute: 0),
                endTime: makeTime(daysOffset: -7, hour: 11, minute: 30),
                location: "Main Gym",
                status: .completed,
                attendeeIds: u12Students,
                actualAttendeeIds: u12Students,
                coachNotes: "Full attendance! Passing drills went well. Need to work on bounce passes next week.",
                developmentFocus: [.passing],
                rating: 5,
                createdByCoachId: Self.staffCoach2Id
            ),
            // Upcoming session (Program 1)
            SessionEvent(
                id: Self.session3Id,
                microCycleId: Self.phase2Id,
                programId: Self.program1Id,
                title: "Shooting Form Intro",
                date: makeTime(daysOffset: 3, hour: 10, minute: 0),
                startTime: makeTime(daysOffset: 3, hour: 10, minute: 0),
                endTime: makeTime(daysOffset: 3, hour: 11, minute: 30),
                location: "Main Gym",
                status: .scheduled,
                attendeeIds: u12Students,
                notes: "Introduce BEEF shooting technique. Start with form shooting close to basket.",
                developmentFocus: [.shooting],
                createdByCoachId: Self.staffCoach2Id
            ),
            // Past completed sessions (Program 2 - U14)
            SessionEvent(
                id: Self.session4Id,
                microCycleId: Self.phase3Id,
                programId: Self.program2Id,
                title: "Pick & Roll Reads",
                date: makeTime(daysOffset: -10, hour: 18, minute: 0),
                startTime: makeTime(daysOffset: -10, hour: 18, minute: 0),
                endTime: makeTime(daysOffset: -10, hour: 20, minute: 0),
                location: "Court B",
                status: .completed,
                attendeeIds: u14Students,
                actualAttendeeIds: Array(u14Students.prefix(4)),
                excusedAbsences: [Self.student10Id],
                coachNotes: "Jaylen is reading the defense well. Ethan needs to work on his roll timing.",
                developmentFocus: [.ballHandling, .teamPlay],
                manOfTheMatchId: Self.student1Id,
                rating: 4,
                createdByCoachId: Self.staffCoach1Id
            ),
            SessionEvent(
                id: Self.session5Id,
                microCycleId: Self.phase3Id,
                programId: Self.program2Id,
                title: "Step-Back & Euro Step",
                date: makeTime(daysOffset: -8, hour: 18, minute: 0),
                startTime: makeTime(daysOffset: -8, hour: 18, minute: 0),
                endTime: makeTime(daysOffset: -8, hour: 20, minute: 0),
                location: "Court B",
                status: .completed,
                attendeeIds: u14Students,
                actualAttendeeIds: u14Students,
                coachNotes: "Best session yet. All 5 athletes locked in. Noah's euro step is looking smooth.",
                developmentFocus: [.shooting, .ballHandling],
                manOfTheMatchId: Self.student5Id,
                rating: 5,
                createdByCoachId: Self.staffCoach1Id
            ),
            // Upcoming sessions (Program 2)
            SessionEvent(
                id: Self.session6Id,
                microCycleId: Self.phase3Id,
                programId: Self.program2Id,
                title: "Scrimmage & Film Review",
                date: makeTime(daysOffset: 1, hour: 18, minute: 0),
                startTime: makeTime(daysOffset: 1, hour: 18, minute: 0),
                endTime: makeTime(daysOffset: 1, hour: 20, minute: 0),
                location: "Court B",
                status: .scheduled,
                attendeeIds: u14Students,
                notes: "5v5 scrimmage applying PnR concepts. Record for film review.",
                developmentFocus: [.teamPlay, .gamePrep],
                createdByCoachId: Self.staffCoach1Id
            ),
            // Private session (Program 3)
            SessionEvent(
                id: Self.session7Id,
                programId: Self.program3Id,
                title: "Catch & Shoot Reps",
                date: makeTime(daysOffset: -5, hour: 16, minute: 0),
                startTime: makeTime(daysOffset: -5, hour: 16, minute: 0),
                endTime: makeTime(daysOffset: -5, hour: 17, minute: 0),
                location: "Shooting Bay",
                status: .completed,
                attendeeIds: privateStudents,
                actualAttendeeIds: privateStudents,
                coachNotes: "Jaylen hit 72% from mid-range. Ethan improving but still dipping the ball on catch.",
                developmentFocus: [.shooting],
                rating: 4,
                createdByCoachId: Self.staffCoach1Id
            ),
            SessionEvent(
                id: Self.session8Id,
                programId: Self.program3Id,
                title: "Off-Dribble Pull-Up",
                date: makeTime(daysOffset: 2, hour: 16, minute: 0),
                startTime: makeTime(daysOffset: 2, hour: 16, minute: 0),
                endTime: makeTime(daysOffset: 2, hour: 17, minute: 0),
                location: "Shooting Bay",
                status: .scheduled,
                attendeeIds: privateStudents,
                notes: "Work on pull-up jumper off 1-2 dribbles. Focus on balance and follow-through.",
                developmentFocus: [.shooting, .ballHandling],
                createdByCoachId: Self.staffCoach1Id
            )
        ]
    }
    
    // MARK: - Contracts
    func generateContracts() -> [Contract] {
        let today = Date()
        let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: today)!
        let fourMonthsOut = cal.date(byAdding: .month, value: 4, to: today)!
        
        return [
            Contract(id: Self.contract1Id, studentId: Self.student1Id, contractNumber: 1,
                     totalSessions: 24, attendedSessions: 10,
                     startDate: twoMonthsAgo, expiryDate: fourMonthsOut,
                     pricePerSession: 50, totalAmount: 1200, amountPaid: 1200, isSigned: true),
            Contract(id: Self.contract2Id, studentId: Self.student2Id, contractNumber: 1,
                     totalSessions: 24, attendedSessions: 8,
                     startDate: twoMonthsAgo, expiryDate: fourMonthsOut,
                     pricePerSession: 40, totalAmount: 960, amountPaid: 960, isSigned: true),
            Contract(id: Self.contract3Id, studentId: Self.student3Id, contractNumber: 1,
                     totalSessions: 24, attendedSessions: 12,
                     startDate: twoMonthsAgo, expiryDate: fourMonthsOut,
                     pricePerSession: 50, totalAmount: 1200, amountPaid: 600, isSigned: true),
            Contract(id: Self.contract4Id, studentId: Self.student5Id, contractNumber: 1,
                     totalSessions: 16, attendedSessions: 6,
                     startDate: twoMonthsAgo, expiryDate: fourMonthsOut,
                     pricePerSession: 45, totalAmount: 720, amountPaid: 720, isSigned: true),
            Contract(id: Self.contract5Id, studentId: Self.student7Id, contractNumber: 1,
                     totalSessions: 24, attendedSessions: 14,
                     startDate: cal.date(byAdding: .month, value: -4, to: today),
                     expiryDate: cal.date(byAdding: .month, value: 2, to: today),
                     pricePerSession: 50, totalAmount: 1200, amountPaid: 1200, isSigned: true),
        ]
    }
    
    // MARK: - Players (physical profiles)
    func generatePlayers() -> [Player] {
        [
            Player(id: Self.player1Id, studentId: Self.student1Id, heightCm: 172, weightKg: 58,
                   handedness: .right, contractInfo: ContractInfo(totalSessions: 24, completedSessions: 10)),
            Player(id: Self.player2Id, studentId: Self.student2Id, heightCm: 148, weightKg: 38,
                   handedness: .right, contractInfo: ContractInfo(totalSessions: 24, completedSessions: 8)),
            Player(id: Self.player3Id, studentId: Self.student3Id, heightCm: 175, weightKg: 62,
                   handedness: .left, contractInfo: ContractInfo(totalSessions: 24, completedSessions: 12)),
            Player(id: Self.player4Id, studentId: Self.student5Id, heightCm: 168, weightKg: 55,
                   handedness: .right, contractInfo: ContractInfo(totalSessions: 16, completedSessions: 6)),
            Player(id: Self.player5Id, studentId: Self.student7Id, heightCm: 180, weightKg: 68,
                   handedness: .right, contractInfo: ContractInfo(totalSessions: 24, completedSessions: 14)),
        ]
    }
}
