import SwiftUI
import Combine
#if os(iOS)
import UIKit
import AVFoundation
#endif

struct AddStudentView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    // Edit mode support
    let studentToEdit: Student?
    let playerToEdit: Player?
    var isEditMode: Bool { studentToEdit != nil }
    
    // Basic Info
    @State private var name: String
    @State private var chineseName: String
    @State private var avatarColor: AvatarColor
    
    // Age Input - supports two modes: Date of Birth or School Grade
    @State private var ageInputMode: AgeInputMode
    @State private var selectedBirthMonth: Int
    @State private var selectedBirthYear: Int
    @State private var selectedBirthDay: Int?
    @State private var showDayPicker = false
    @State private var selectedSchoolGrade: SchoolGrade?
    
    enum AgeInputMode: String, CaseIterable {
        case dateOfBirth = "dob"
        case schoolGrade = "grade"
        
        var displayName: String {
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            switch self {
            case .dateOfBirth: return isChinese ? "出生日期" : "Date of Birth"
            case .schoolGrade: return isChinese ? "年级" : "School Grade"
            }
        }
    }
    @State private var selectedCategoryId: UUID?
    @State private var selectedCoachId: UUID?
    @State private var selectedProgramId: UUID?
    
    // Physical Info
    @State private var heightCm: String
    @State private var weightKg: String
    @State private var handedness: Handedness
    @State private var position: String
    @State private var jerseyNumber: String
    
    // Parent Info
    @State private var parentName: String
    @State private var parentRelationship: String
    @State private var parentPhone: String
    @State private var parentEmail: String
    @State private var parentWechat: String
    
    // Contract Info
    @State private var totalSessions: String
    @State private var pricePerSession: String
    @State private var contractSigned: Bool
    @State private var contractSignedDate: Date
    @State private var jerseyGiven: Bool
    @State private var jerseySize: String
    @State private var ballGiven: Bool
    
    // Photo capture
    #if os(iOS)
    @State private var capturedImage: UIImage?
    @State private var showingCameraPicker = false
    @State private var showingPhotoLibrary = false
    @State private var showingPhotoOptions = false
    #endif
    @State private var profileImageUrl: String?
    @State private var isUploadingImage = false
    @State private var uploadError: String?
    
    // Section expansion states
    @State private var showPhysicalSection = false
    @State private var showParentSection = false
    @State private var showContractSection = true

    // Sharing — Phase 2: per-student exclusion from export bundles.
    // Hydrated on appear (edit mode) from SDStudent; persisted via
    // dataManager.setExcludedFromExport on save.
    @State private var excludeFromExport: Bool = false
    
    // Contract management (for edit mode)
    @State private var existingContracts: [Contract] = []
    @State private var showingAddContractSheet = false
    @State private var editingContractItem: Contract?
    
    private let jerseySizes = ["YS", "YM", "YL", "S", "M", "L", "XL"]
    
    private var studentColor: Color {
        Color.avatarColor(avatarColor)
    }
    
    var isValid: Bool {
        // Require at least 2 characters in either English or Chinese name.
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedChinese = chineseName.trimmingCharacters(in: .whitespaces)
        return trimmedName.count >= 2 || trimmedChinese.count >= 2
    }
    
    // MARK: - Initializers
    
    /// Default init for adding new students
    init() {
        self.studentToEdit = nil
        self.playerToEdit = nil
        _name = State(initialValue: "")
        _chineseName = State(initialValue: "")
        _avatarColor = State(initialValue: AvatarColor.allCases.randomElement() ?? .blue)
        _ageInputMode = State(initialValue: .dateOfBirth)
        _selectedBirthMonth = State(initialValue: Calendar.current.component(.month, from: Date()))
        _selectedBirthYear = State(initialValue: Calendar.current.component(.year, from: Date()) - 10)
        _selectedBirthDay = State(initialValue: nil)
        _selectedSchoolGrade = State(initialValue: nil)
        _selectedCategoryId = State(initialValue: nil)
        _selectedCoachId = State(initialValue: nil)
        _selectedProgramId = State(initialValue: nil)
        _heightCm = State(initialValue: "")
        _weightKg = State(initialValue: "")
        _handedness = State(initialValue: .right)
        _position = State(initialValue: "")
        _jerseyNumber = State(initialValue: "")
        _parentName = State(initialValue: "")
        _parentRelationship = State(initialValue: "Parent")
        _parentPhone = State(initialValue: "")
        _parentEmail = State(initialValue: "")
        _parentWechat = State(initialValue: "")
        _totalSessions = State(initialValue: "24")
        _pricePerSession = State(initialValue: "200")
        _contractSigned = State(initialValue: false)
        _contractSignedDate = State(initialValue: Date())
        _jerseyGiven = State(initialValue: false)
        _jerseySize = State(initialValue: "")
        _ballGiven = State(initialValue: false)
        _profileImageUrl = State(initialValue: nil)
    }
    
    /// Init for editing existing students
    init(student: Student, player: Player?) {
        self.studentToEdit = student
        self.playerToEdit = player
        
        // Basic Info
        _name = State(initialValue: student.name)
        _chineseName = State(initialValue: student.chineseName ?? "")
        _avatarColor = State(initialValue: student.avatarColor)
        _profileImageUrl = State(initialValue: student.profileImageUrl)
        
        // Age Input
        if let grade = student.schoolGrade {
            _ageInputMode = State(initialValue: .schoolGrade)
            _selectedSchoolGrade = State(initialValue: grade)
            _selectedBirthMonth = State(initialValue: Calendar.current.component(.month, from: Date()))
            _selectedBirthYear = State(initialValue: Calendar.current.component(.year, from: Date()) - 10)
            _selectedBirthDay = State(initialValue: nil)
        } else if let birthdate = student.birthdate {
            _ageInputMode = State(initialValue: .dateOfBirth)
            _selectedBirthMonth = State(initialValue: Calendar.current.component(.month, from: birthdate))
            _selectedBirthYear = State(initialValue: Calendar.current.component(.year, from: birthdate))
            _selectedBirthDay = State(initialValue: Calendar.current.component(.day, from: birthdate))
            _selectedSchoolGrade = State(initialValue: nil)
        } else {
            _ageInputMode = State(initialValue: .dateOfBirth)
            _selectedBirthMonth = State(initialValue: student.birthMonth ?? Calendar.current.component(.month, from: Date()))
            _selectedBirthYear = State(initialValue: student.birthYear ?? Calendar.current.component(.year, from: Date()) - 10)
            _selectedBirthDay = State(initialValue: nil)
            _selectedSchoolGrade = State(initialValue: nil)
        }
        
        // Assignment
        _selectedCategoryId = State(initialValue: student.categoryId)
        _selectedCoachId = State(initialValue: student.coachId)
        _selectedProgramId = State(initialValue: student.programId)
        
        // Physical Info from Player
        _heightCm = State(initialValue: player?.heightCm != nil ? String(Int(player!.heightCm!)) : "")
        _weightKg = State(initialValue: player?.weightKg != nil ? String(Int(player!.weightKg!)) : "")
        _handedness = State(initialValue: player?.handedness ?? .right)
        _position = State(initialValue: player?.position ?? "")
        _jerseyNumber = State(initialValue: player?.jerseyNumber != nil ? String(player!.jerseyNumber!) : "")
        
        // Parent Info from Player
        _parentName = State(initialValue: player?.parentInfo.name ?? "")
        _parentRelationship = State(initialValue: player?.parentInfo.relationship ?? "Parent")
        _parentPhone = State(initialValue: player?.parentInfo.phone ?? "")
        _parentEmail = State(initialValue: player?.parentInfo.email ?? "")
        _parentWechat = State(initialValue: player?.parentInfo.wechatId ?? "")
        
        // Contract Info (defaults for edit mode - contracts managed separately)
        _totalSessions = State(initialValue: "24")
        _pricePerSession = State(initialValue: "200")
        _contractSigned = State(initialValue: false)
        _contractSignedDate = State(initialValue: Date())
        _jerseyGiven = State(initialValue: false)
        _jerseySize = State(initialValue: "")
        _ballGiven = State(initialValue: false)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Photo Section
                    profilePhotoSection
                    
                    // Basic Info
                    basicInfoSection
                    
                    // Assignment
                    assignmentSection
                    
                    // Physical Info (Expandable)
                    expandableSection(
                        title: LocalizationManager.shared.currentLanguage == .chinese ? "身体数据" : "Physical Stats",
                        icon: "ruler.fill",
                        iconColor: .blue,
                        isExpanded: $showPhysicalSection
                    ) {
                        physicalInfoSection
                    }
                    
                    // Parent Info (Expandable)
                    expandableSection(
                        title: LocalizationManager.shared.currentLanguage == .chinese ? "家长/监护人" : "Parent/Guardian",
                        icon: "person.2.fill",
                        iconColor: .teal,
                        isExpanded: $showParentSection
                    ) {
                        parentInfoSection
                    }
                    
                    // Contract Section - different for add vs edit mode
                    if isEditMode {
                        // In edit mode, show existing contracts with full management
                        existingContractsSection
                    } else {
                        // In add mode, show simple contract setup
                        expandableSection(
                            title: LocalizationManager.shared.currentLanguage == .chinese ? "合同" : "Contract",
                            icon: "doc.text.fill",
                            iconColor: .green,
                            isExpanded: $showContractSection
                        ) {
                            contractSection
                        }
                    }

                    // Sharing — exclude private students from organization exports
                    sharingSection

                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isEditMode 
                ? (LocalizationManager.shared.currentLanguage == .chinese ? "编辑学员" : "Edit Student")
                : (LocalizationManager.shared.currentLanguage == .chinese ? "添加学员" : "Add Student"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveStudent()
                    } label: {
                        if isUploadingImage {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "保存" : "Save")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || isUploadingImage)
                }
            }
            #if os(iOS)
            .confirmationDialog(LocalizationManager.shared.currentLanguage == .chinese ? "添加照片" : "Add Photo", isPresented: $showingPhotoOptions) {
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "拍照" : "Take Photo") {
                    showingCameraPicker = true
                }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "从相册选择" : "Choose from Library") {
                    showingPhotoLibrary = true
                }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingCameraPicker) {
                CameraPicker(image: $capturedImage)
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                ImagePicker(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                if newImage != nil {
                    HapticFeedback.impact(.medium)
                }
            }
            #endif
            // Contract management sheets (edit mode only)
            .onAppear {
                if isEditMode, let student = studentToEdit {
                    refreshExistingContracts(for: student.id)
                }
            }
            .onReceive(dataManager.objectWillChange) { _ in
                if isEditMode, let student = studentToEdit {
                    refreshExistingContracts(for: student.id)
                }
            }
            .sheet(isPresented: $showingAddContractSheet) {
                if let student = studentToEdit {
                    ContractEditSheet(
                        studentId: student.id,
                        contract: nil,
                        onSave: { newContract in
                            dataManager.addContract(newContract)
                        }
                    )
                }
            }
            .sheet(item: $editingContractItem) { contract in
                if let student = studentToEdit {
                    ContractEditSheet(
                        studentId: student.id,
                        contract: contract,
                        onSave: { updatedContract in
                            dataManager.updateContract(updatedContract)
                        },
                        onDelete: { contractToDelete in
                            dataManager.deleteContract(contractToDelete)
                        }
                    )
                }
            }
            .onAppear {
                // Hydrate the per-student exclude flag in edit mode.
                // (No-op in add mode — `studentToEdit` is nil.)
                if let id = studentToEdit?.id {
                    excludeFromExport = dataManager.isExcludedFromExport(studentId: id)
                }
            }
        }
    }

    // MARK: - Profile Photo Section
    private var profilePhotoSection: some View {
        VStack(spacing: 12) {
            // Photo display
            ZStack {
                #if os(iOS)
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(studentColor, lineWidth: 2))
                } else {
                    defaultAvatar
                }
                #else
                defaultAvatar
                #endif
                
                // Upload indicator
                if isUploadingImage {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 88, height: 88)
                    ProgressView()
                        .tint(.white)
                }
                
                // Camera button overlay
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingPhotoOptions = true }) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.accentColor)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .disabled(isUploadingImage)
                    }
                }
                .frame(width: 88, height: 88)
                #endif
            }
            
            // Name preview
            VStack(spacing: 2) {
                Text(name.isEmpty ? (LocalizationManager.shared.currentLanguage == .chinese ? "新学员" : "New Athlete") : name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                
                if !chineseName.isEmpty {
                    Text(chineseName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Photo actions
            #if os(iOS)
            if capturedImage != nil {
                Button(action: removePhoto) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "移除" : "Remove")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                }
                .disabled(isUploadingImage)
            }
            #endif
            
            // Error message
            if let error = uploadError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 16)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [studentColor, studentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
            
            Text(name.isEmpty ? "?" : String(name.prefix(2)).uppercased())
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(studentColor.opacity(0.4), lineWidth: 2))
    }
    
    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 16) {
            Text(isChinese ? "基本信息" : "BASIC INFORMATION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            // Name field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isChinese ? "姓名" : "Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
                TextField(isChinese ? "全名" : "Full name", text: $name)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
            }
            
            // Chinese name field
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "中文名（选填）" : "Chinese Name (Optional)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("中文名", text: $chineseName)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
            }
            
            // Age Input Section
            ageInputSection
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Age Input Section
    private var ageInputSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "年龄信息" : "Age Information")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            // Mode selector
            Picker("", selection: $ageInputMode) {
                ForEach(AgeInputMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            
            if ageInputMode == .dateOfBirth {
                dateOfBirthInput
            } else {
                schoolGradeInput
            }
        }
    }
    
    // MARK: - Date of Birth Input (Month/Year required, Day optional)
    private var dateOfBirthInput: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let months = isChinese ? 
            ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"] :
            ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = Array((currentYear - 25)...(currentYear - 2)).reversed()
        
        return VStack(spacing: 12) {
            // Month and Year row
            HStack(spacing: 12) {
                // Month picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "月份" : "Month")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Menu {
                        ForEach(1...12, id: \.self) { month in
                            Button(action: { selectedBirthMonth = month }) {
                                Text(months[month - 1])
                            }
                        }
                    } label: {
                        HStack {
                            Text(months[selectedBirthMonth - 1])
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                    }
                }
                
                // Year picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "年份" : "Year")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Menu {
                        ForEach(years, id: \.self) { year in
                            Button(action: { selectedBirthYear = year }) {
                                Text(String(year))
                            }
                        }
                    } label: {
                        HStack {
                            Text(String(selectedBirthYear))
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                    }
                }
            }
            
            // Optional Day toggle and picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isChinese ? "添加具体日期（选填）" : "Add specific day (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $showDayPicker)
                        .labelsHidden()
                        .tint(AppTheme.accentColor)
                        .onChange(of: showDayPicker) { _, newValue in
                            if !newValue {
                                selectedBirthDay = nil
                            } else if selectedBirthDay == nil {
                                selectedBirthDay = 1
                            }
                        }
                }
                
                if showDayPicker {
                    let daysInMonth = numberOfDays(in: selectedBirthMonth, year: selectedBirthYear)
                    Menu {
                        ForEach(1...daysInMonth, id: \.self) { day in
                            Button(action: { selectedBirthDay = day }) {
                                Text(String(day))
                            }
                        }
                    } label: {
                        HStack {
                            Text(isChinese ? "日期: \(selectedBirthDay ?? 1)" : "Day: \(selectedBirthDay ?? 1)")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                    }
                }
            }
            
            // Estimated age display
            estimatedAgeDisplay
        }
    }
    
    // MARK: - School Grade Input
    private var schoolGradeInput: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "选择年级" : "Select Grade")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            
            // Kindergarten
            gradeSection(
                title: isChinese ? "幼儿园" : "Kindergarten",
                grades: SchoolGrade.kindergartenGrades,
                color: .pink
            )
            
            // Primary School
            gradeSection(
                title: isChinese ? "小学" : "Primary School",
                grades: SchoolGrade.primaryGrades,
                color: .blue
            )
            
            // High School
            gradeSection(
                title: isChinese ? "中学" : "High School",
                grades: SchoolGrade.highschoolGrades,
                color: .purple
            )
            
            // Estimated age display
            if selectedSchoolGrade != nil {
                estimatedAgeDisplay
            }
        }
    }
    
    private func gradeSection(title: String, grades: [SchoolGrade], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(grades, id: \.self) { grade in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSchoolGrade = grade
                        }
                        HapticFeedback.impact(.light)
                    }) {
                        Text(grade.localizedShortName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedSchoolGrade == grade ? .white : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedSchoolGrade == grade ? color : AppTheme.surfaceColor)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var estimatedAgeDisplay: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let age: Int
        if ageInputMode == .schoolGrade, let grade = selectedSchoolGrade {
            age = grade.estimatedAge
        } else {
            let currentYear = Calendar.current.component(.year, from: Date())
            let currentMonth = Calendar.current.component(.month, from: Date())
            age = currentYear - selectedBirthYear - (currentMonth < selectedBirthMonth ? 1 : 0)
        }
        
        return HStack {
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.accentColor)
            Text(isChinese ? "预估年龄" : "Estimated Age")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(age) \(isChinese ? "岁" : "years old")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(AppTheme.accentColor.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func numberOfDays(in month: Int, year: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar.current
        if let date = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: date) {
            return range.count
        }
        return 30
    }
    
    // MARK: - Avatar Color Section
    private var avatarColorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AVATAR COLOR")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(AvatarColor.allCases, id: \.self) { color in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            avatarColor = color
                        }
                        HapticFeedback.impact(.light)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.avatarColor(color))
                                .frame(width: 50, height: 50)
                            
                            if avatarColor == color {
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Assignment Section
    private var assignmentSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 16) {
            Text(isChinese ? "分配" : "ASSIGNMENT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            // Category
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "类别" : "Category")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button(isChinese ? "无" : "None") { selectedCategoryId = nil }
                    ForEach(dataManager.ageCategories.filter { $0.isActive }) { category in
                        Button(action: { selectedCategoryId = category.id }) {
                            Label("\(category.shortName) - \(category.name)", systemImage: "circle.fill")
                        }
                    }
                } label: {
                    HStack {
                        if let categoryId = selectedCategoryId,
                           let category = dataManager.ageCategories.first(where: { $0.id == categoryId }) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)
                            Text("\(category.shortName) - \(category.name)")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text(isChinese ? "选择类别" : "Select category")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
            
            // Coach
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "教练" : "Coach")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button(isChinese ? "无" : "None") { selectedCoachId = nil }
                    ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                        Button(action: { selectedCoachId = coach.id }) {
                            Label(coach.name, systemImage: coach.role.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let coachId = selectedCoachId,
                           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 12))
                                .foregroundColor(coach.role.color)
                            Text(coach.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text(isChinese ? "选择教练" : "Select coach")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
            
            // Program
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "课程" : "Program")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button(isChinese ? "无" : "None") { selectedProgramId = nil }
                    ForEach(dataManager.programs.filter { $0.isActive }) { program in
                        Button(action: { selectedProgramId = program.id }) {
                            Label(program.name, systemImage: program.mascot.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let programId = selectedProgramId,
                           let program = dataManager.programs.first(where: { $0.id == programId }) {
                            Image(systemName: program.mascot.icon)
                                .font(.system(size: 12))
                                .foregroundColor(program.mascotColor)
                            Text(program.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text(isChinese ? "选择课程" : "Select program")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Physical Info Section
    private var physicalInfoSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Height
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "身高 (cm)" : "Height (cm)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(isChinese ? "例如 165" : "e.g. 165", text: $heightCm)
                        .keyboardTypeCompat(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
                
                // Weight
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "体重 (kg)" : "Weight (kg)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(isChinese ? "例如 55" : "e.g. 55", text: $weightKg)
                        .keyboardTypeCompat(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
            }
            
            HStack(spacing: 12) {
                // Position
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "位置" : "Position")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(isChinese ? "例如 控球后卫" : "e.g. Point Guard", text: $position)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
                
                // Jersey Number
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "球衣号" : "Jersey #")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(isChinese ? "例如 23" : "e.g. 23", text: $jerseyNumber)
                        .keyboardTypeCompat(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
            }
            
            // Handedness
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "惯用手" : "Handedness")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(Handedness.allCases, id: \.self) { hand in
                        Button(action: { handedness = hand }) {
                            HStack(spacing: 6) {
                                Image(systemName: hand == .left ? "hand.point.left.fill" : (hand == .right ? "hand.point.right.fill" : "hands.clap.fill"))
                                    .font(.system(size: 12))
                                Text(hand.displayName)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(handedness == hand ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(handedness == hand ? AppTheme.accentColor : AppTheme.surfaceColor)
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Parent Info Section
    private var parentInfoSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let relationships = isChinese ? 
            ["家长", "监护人", "母亲", "父亲", "其他"] :
            ["Parent", "Guardian", "Mother", "Father", "Other"]
        return VStack(spacing: 16) {
            // Parent Name
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "家长/监护人姓名" : "Parent/Guardian Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "全名" : "Full name", text: $parentName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // Relationship
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "关系" : "Relationship")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(relationships, id: \.self) { rel in
                            Button(action: { parentRelationship = rel }) {
                                Text(rel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(parentRelationship == rel ? .white : AppTheme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(parentRelationship == rel ? AppTheme.accentColor : AppTheme.surfaceColor)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            
            // Phone
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "电话号码" : "Phone Number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "电话号码" : "Phone number", text: $parentPhone)
                    .keyboardTypeCompat(.phonePad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // Email
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "邮箱" : "Email")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "邮箱地址" : "Email address", text: $parentEmail)
                    .keyboardTypeCompat(.emailAddress)
                    .autocapitalizationCompat(.never)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // WeChat
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "微信号" : "WeChat ID")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "微信号" : "WeChat ID", text: $parentWechat)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Contract Section
    /// New-student contract picker. Kept deliberately minimal — full editing
    /// happens in AddEditContractSheet from the student detail screen.
    private var contractSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(isChinese
                     ? "添加合同可在保存学员后从档案页进行。这里只设置初始价格作为参考。"
                     : "Add a contract from the student's profile after saving. The price below is just a hint for later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text(isChinese ? "默认单价" : "Default price")
                    .font(.subheadline)
                Spacer()
                TextField("0", text: $pricePerSession)
                    .keyboardTypeCompat(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(dataManager.appSettings.currency.symbol)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - Sharing Section (Phase 2 of export/import)
    /// Toggle to mark a student as private — excluded from organization
    /// share bundles. Default off. Modeled after iOS Settings privacy rows.
    private var sharingSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(isChinese ? "共享" : "Sharing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 8)

            Toggle(isOn: $excludeFromExport) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "保持此学员为私密" : "Keep this athlete private")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(isChinese
                         ? "不会包含在组织数据导出中"
                         : "Won't be included in organization data exports")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.purple)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: - Expandable Section Helper
    private func expandableSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.wrappedValue.toggle() } }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.15))
                        .cornerRadius(8)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            if isExpanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 16)
                
                content()
                    .padding(16)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Existing Contracts Section (Edit Mode Only)
    private var existingContractsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .frame(width: 28, height: 28)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                
                Text(isChinese ? "合同管理" : "Contracts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: { showingAddContractSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text(isChinese ? "添加" : "Add")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            if existingContracts.isEmpty {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.secondary)
                    Text(isChinese ? "暂无合同" : "No contracts yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(existingContracts.sorted(by: { $0.contractNumber > $1.contractNumber })) { contract in
                        existingContractRow(contract)
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Spacer().frame(height: 8)
        }
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private func existingContractRow(_ contract: Contract) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Button(action: { editingContractItem = contract }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Contract number badge
                    Text(contract.contractLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: contract.status.color))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    // Status
                    Text(isChinese ? contract.status.localizedNameChinese : contract.status.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Sessions progress
                HStack {
                    Text(isChinese 
                        ? "\(contract.attendedSessions)/\(contract.totalSessions) 节课"
                        : "\(contract.attendedSessions)/\(contract.totalSessions) sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if let expiry = contract.expiryDate {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(contract.isExpired ? .red : .secondary)
                    }
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(contract.attendedSessions) / CGFloat(max(contract.totalSessions, 1)), height: 6)
                    }
                }
                .frame(height: 6)
                
                // Payment info
                HStack(spacing: 12) {
                    Text("¥\(Int(contract.amountPaid))/¥\(Int(contract.totalAmount))")
                        .font(.system(size: 12))
                        .foregroundColor(contract.isFullyPaid ? .green : .orange)
                    
                    if contract.jerseyGiven {
                        Image(systemName: "tshirt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    if contract.ballGiven {
                        Image(systemName: "basketball.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
            }
            .padding(12)
            .background(.quaternary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private func refreshExistingContracts(for studentId: UUID) {
        existingContracts = dataManager.contracts.filter { $0.studentId == studentId }
    }
    
    // MARK: - Actions
    #if os(iOS)
    private func removePhoto() {
        withAnimation {
            capturedImage = nil
        }
    }
    #endif
    
    private func saveStudent() {
        // Use existing ID if editing, otherwise generate new
        let studentId = studentToEdit?.id ?? UUID()
        
        // Auto-fill English name with Pinyin if only Chinese name is provided
        var finalName = name.trimmingCharacters(in: .whitespaces)
        let finalChineseName = chineseName.trimmingCharacters(in: .whitespaces)
        
        if finalName.isEmpty && !finalChineseName.isEmpty {
            // Convert Chinese name to Pinyin for the English name field
            finalName = PinyinConverter.toPinyin(finalChineseName)
        } else if !finalChineseName.isEmpty && PinyinConverter.isPurelyChinese(finalName) {
            // If the "name" field also contains Chinese, convert it to Pinyin
            finalName = PinyinConverter.toPinyin(finalName)
        }
        
        // Save image locally if captured
        #if os(iOS)
        if let image = capturedImage, let imageData = image.jpegData(compressionQuality: 0.8) {
            saveImageLocally(imageData, studentId: studentId)
        }
        #endif
        
        // Calculate birthdate based on age input mode
        let calculatedBirthdate: Date?
        let birthMonthValue: Int?
        let birthYearValue: Int?
        let schoolGradeValue: SchoolGrade?
        
        if ageInputMode == .schoolGrade, let grade = selectedSchoolGrade {
            calculatedBirthdate = grade.estimatedBirthdate
            birthMonthValue = nil
            birthYearValue = nil
            schoolGradeValue = grade
        } else {
            // Create birthdate from month/year (and optional day)
            var components = DateComponents()
            components.year = selectedBirthYear
            components.month = selectedBirthMonth
            components.day = selectedBirthDay ?? 1
            calculatedBirthdate = Calendar.current.date(from: components)
            birthMonthValue = selectedBirthMonth
            birthYearValue = selectedBirthYear
            schoolGradeValue = nil
        }
        
        let parentInfo = ParentInfo(
            name: parentName,
            relationship: parentRelationship,
            phone: parentPhone,
            email: parentEmail.isEmpty ? nil : parentEmail,
            wechatId: parentWechat.isEmpty ? nil : parentWechat
        )
        
        if isEditMode, let existingStudent = studentToEdit {
            // UPDATE existing student
            var updatedStudent = existingStudent
            updatedStudent.name = finalName
            updatedStudent.chineseName = finalChineseName.isEmpty ? nil : finalChineseName
            updatedStudent.avatarColor = avatarColor
            updatedStudent.categoryId = selectedCategoryId
            updatedStudent.coachId = selectedCoachId
            updatedStudent.programId = selectedProgramId
            updatedStudent.birthdate = calculatedBirthdate
            updatedStudent.birthMonth = birthMonthValue
            updatedStudent.birthYear = birthYearValue
            updatedStudent.schoolGrade = schoolGradeValue
            updatedStudent.profileImageUrl = profileImageUrl
            updatedStudent.updatedAt = Date()
            
            dataManager.updateStudent(updatedStudent)
            
            // Update or create player
            if var existingPlayer = playerToEdit {
                existingPlayer.heightCm = Double(heightCm)
                existingPlayer.weightKg = Double(weightKg)
                existingPlayer.handedness = handedness
                existingPlayer.position = position.isEmpty ? nil : position
                existingPlayer.jerseyNumber = Int(jerseyNumber)
                existingPlayer.parentInfo = parentInfo
                existingPlayer.updatedAt = Date()
                dataManager.updatePlayer(existingPlayer)
            } else {
                // Create new player for existing student
                let newPlayer = Player(
                    studentId: studentId,
                    heightCm: Double(heightCm),
                    weightKg: Double(weightKg),
                    handedness: handedness,
                    position: position.isEmpty ? nil : position,
                    jerseyNumber: Int(jerseyNumber),
                    parentInfo: parentInfo,
                    contractInfo: ContractInfo()
                )
                dataManager.addPlayer(newPlayer)
            }
        } else {
            // CREATE new student
            let student = Student(
                id: studentId,
                name: finalName,
                chineseName: finalChineseName.isEmpty ? nil : finalChineseName,
                avatarColor: avatarColor,
                categoryId: selectedCategoryId,
                coachId: selectedCoachId,
                programId: selectedProgramId,
                birthdate: calculatedBirthdate,
                birthMonth: birthMonthValue,
                birthYear: birthYearValue,
                schoolGrade: schoolGradeValue,
                profileImageUrl: profileImageUrl,
                createdByCoachId: dataManager.loggedInCoachId
            )
            
            // Legacy contract info for Player
            let sessions = Int(totalSessions) ?? 24
            let price = Double(pricePerSession) ?? 200
            let total = Double(sessions) * price
            
            let contractInfo = ContractInfo(
                totalSessions: sessions,
                pricePerSession: price,
                totalPaid: contractSigned ? total : 0
            )
            
            let player = Player(
                studentId: student.id,
                heightCm: Double(heightCm),
                weightKg: Double(weightKg),
                handedness: handedness,
                position: position.isEmpty ? nil : position,
                jerseyNumber: Int(jerseyNumber),
                parentInfo: parentInfo,
                contractInfo: contractInfo
            )
            
            // No automatic contract creation. Contracts are added explicitly
            // from the student's profile via AddEditContractSheet so the kind
            // (PAYG / Bundle / Group) is an intentional choice.
            _ = sessions
            _ = price
            _ = total
            _ = contractSigned
            _ = contractSignedDate
            _ = jerseyGiven
            _ = ballGiven
            _ = jerseySize
            _ = jerseyNumber

            dataManager.addStudent(student, player: player)
        }

        // Persist the exclude-from-export flag on the SDStudent. Done after
        // add/update so the SDStudent definitely exists in the context.
        dataManager.setExcludedFromExport(studentId: studentId, excludeFromExport)

        // Upload image to cloud in background after saving
        #if os(iOS)
        if let image = capturedImage {
            uploadImageInBackground(image, studentId: studentId)
        }
        #endif

        dismiss()
    }
    
    #if os(iOS)
    private func saveImageLocally(_ imageData: Data, studentId: UUID) {
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let imagesDir = documentsDir.appendingPathComponent("StudentImages", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        
        let fileUrl = imagesDir.appendingPathComponent("\(studentId.uuidString).jpg")
        try? imageData.write(to: fileUrl)
        
        // Set local URL as profile image
        profileImageUrl = fileUrl.absoluteString
        debugLog("✅ Image saved locally: \(fileUrl.path)")
    }
    
    private func uploadImageInBackground(_ image: UIImage, studentId: UUID) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }

        if var student = dataManager.students.first(where: { $0.id == studentId }) {
            student.profileImageData = imageData
            student.thumbnailImageData = makeProfileThumbnailData(from: imageData)
            dataManager.updateStudent(student)
        }
    }
    #endif
}

// MARK: - Camera Picker (iOS only)
#if os(iOS)
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIViewController {
        // Check camera authorization status first
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return createImagePicker(withCamera: true, context: context)
        case .notDetermined:
            // Request permission - for now show photo library as fallback
            AVCaptureDevice.requestAccess(for: .video) { granted in
                // Permission will be available next time
            }
            return createImagePicker(withCamera: false, context: context)
        case .denied, .restricted:
            // Camera not available, use photo library
            return createImagePicker(withCamera: false, context: context)
        @unknown default:
            return createImagePicker(withCamera: false, context: context)
        }
    }
    
    private func createImagePicker(withCamera: Bool, context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        
        if withCamera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .rear
        } else {
            picker.sourceType = .photoLibrary
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

// MARK: - Edit Student View (Flighty Aesthetic)
struct EditStudentView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let student: Student
    let player: Player?
    
    // Basic Info
    @State private var name: String
    @State private var chineseName: String
    @State private var selectedSchoolGrade: SchoolGrade?
    @State private var selectedCategoryId: UUID?
    @State private var selectedCoachId: UUID?
    @State private var selectedProgramId: UUID?

    // Parent Info
    @State private var parentName: String
    @State private var parentRelationship: String
    @State private var parentPhone: String
    @State private var parentEmail: String
    @State private var parentWechat: String

    // Profile Image
    @State private var showingImagePicker = false
    @State private var showingPhotoSourceDialog = false
    #if os(iOS)
    @State private var selectedImage: UIImage?
    @State private var localImageData: Data?
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    #endif
    @State private var profileImageUrl: String?
    @State private var isUploadingImage = false
    @State private var uploadError: String?
    @State private var headerImageURL: String?

    // Section expansion states
    @State private var showParentSection = false

    // Sharing — Phase 2: per-student exclusion from export bundles.
    // Hydrated in .onAppear from SDStudent; persisted via
    // dataManager.setExcludedFromExport on save.
    @State private var excludeFromExport: Bool = false

    // Contract Info
    @State private var contracts: [Contract]
    @State private var showingAddContract = false
    @State private var editingContract: Contract?
    
    private var studentColor: Color {
        Color.avatarColor(student.avatarColor)
    }

    init(student: Student, player: Player?) {
        self.student = student
        self.player = player

        // Basic Info
        _name = State(initialValue: student.name)
        _chineseName = State(initialValue: student.chineseName ?? "")
        _selectedSchoolGrade = State(initialValue: student.schoolGrade)
        _selectedCategoryId = State(initialValue: student.categoryId)
        _selectedCoachId = State(initialValue: student.coachId)
        _selectedProgramId = State(initialValue: student.programId)
        _profileImageUrl = State(initialValue: student.profileImageUrl)
        _headerImageURL = State(initialValue: player?.headerImageURL)

        #if os(iOS)
        // Restore previously saved photo so it shows on reopen.
        _localImageData = State(initialValue: student.profileImageData)
        #endif

        // Parent Info from Player (parentInfo is non-optional)
        _parentName = State(initialValue: player?.parentInfo.name ?? "")
        _parentRelationship = State(initialValue: player?.parentInfo.relationship ?? "Parent")
        _parentPhone = State(initialValue: player?.parentInfo.phone ?? "")
        _parentEmail = State(initialValue: player?.parentInfo.email ?? "")
        _parentWechat = State(initialValue: player?.parentInfo.wechatId ?? "")

        // Contracts - will be loaded from dataManager in onAppear
        _contracts = State(initialValue: [])
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Photo Section
                    profilePhotoSection

                    // Basic Info (name, chinese name, school grade)
                    basicInfoSection

                    // Note: Assignment (category / coach / program) is set
                    // automatically based on the program the student is
                    // enrolled in — managed in the Programs / Sessions
                    // surfaces, not here. Contract management lives one
                    // level up in the student profile so the editor stays
                    // focused on per-student identity + relationships.

                    // Parent Info (Expandable)
                    editableExpandableSection(
                        title: isChinese ? "家长/监护人" : "Parent/Guardian",
                        icon: "person.2.fill",
                        iconColor: .teal,
                        isExpanded: $showParentSection
                    ) {
                        parentInfoSection
                    }

                    // Sharing — exclude private students from organization exports
                    sharingSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear {
                // Load contracts for this student
                refreshContracts()
                // Hydrate the per-student exclude flag.
                excludeFromExport = dataManager.isExcludedFromExport(studentId: student.id)
            }
            .onReceive(dataManager.objectWillChange) { _ in
                // Refresh contracts when dataManager changes
                refreshContracts()
            }
            .sheet(isPresented: $showingAddContract) {
                ContractEditSheet(
                    studentId: student.id,
                    contract: nil,
                    onSave: { newContract in
                        dataManager.addContract(newContract)
                        // Contracts will auto-refresh via onReceive
                    }
                )
            }
            .sheet(item: $editingContract) { contract in
                ContractEditSheet(
                    studentId: student.id,
                    contract: contract,
                    onSave: { updatedContract in
                        dataManager.updateContract(updatedContract)
                        // Contracts will auto-refresh via onReceive
                    },
                    onDelete: { contractToDelete in
                        dataManager.deleteContract(contractToDelete)
                        // Contracts will auto-refresh via onReceive
                    }
                )
            }
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveStudent()
                    } label: {
                        if isUploadingImage {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(isChinese ? "保存" : "Save")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isUploadingImage || name.isEmpty)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, sourceType: imagePickerSource)
            }
            .confirmationDialog(
                LocalizationManager.shared.currentLanguage == .chinese ? "添加照片" : "Add Photo",
                isPresented: $showingPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "拍照" : "Take Photo") {
                        imagePickerSource = .camera
                        showingImagePicker = true
                    }
                }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "从图库选择" : "Choose from Library") {
                    imagePickerSource = .photoLibrary
                    showingImagePicker = true
                }
                Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    // Store locally first for immediate display
                    localImageData = image.jpegData(compressionQuality: 0.8)
                    uploadImage()
                }
            }
            #endif
        }
    }
    
    // MARK: - Sharing Section (Phase 2 of export/import)
    /// Toggle to mark this student as private — excluded from organization
    /// share bundles. Default off. Modeled after iOS Settings privacy rows.
    private var sharingSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(isChinese ? "共享" : "Sharing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 8)

            Toggle(isOn: $excludeFromExport) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "保持此学员为私密" : "Keep this athlete private")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(isChinese
                         ? "不会包含在组织数据导出中"
                         : "Won't be included in organization data exports")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.purple)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: - Expandable Section Helper
    private func editableExpandableSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.wrappedValue.toggle() } }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.15))
                        .cornerRadius(8)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            if isExpanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 16)
                
                content()
                    .padding(16)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Parent Info Section
    private var parentInfoSection: some View {
        VStack(spacing: 16) {
            // Parent Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Parent/Guardian Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Full name", text: $parentName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // Relationship
            VStack(alignment: .leading, spacing: 6) {
                Text("Relationship")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(["Parent", "Guardian", "Mother", "Father", "Other"], id: \.self) { rel in
                        Button(action: { parentRelationship = rel }) {
                            Text(rel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(parentRelationship == rel ? .white : AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(parentRelationship == rel ? AppTheme.accentColor : AppTheme.surfaceColor)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Phone
            VStack(alignment: .leading, spacing: 6) {
                Text("Phone Number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Phone number", text: $parentPhone)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // Email
            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Email address", text: $parentEmail)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
            
            // WeChat
            VStack(alignment: .leading, spacing: 6) {
                Text("WeChat ID")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("WeChat ID", text: $parentWechat)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Contract Edit Section
    private var contractEditSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text("Contracts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                
                Button(action: { showingAddContract = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.green)
                }
            }
            
            if contracts.isEmpty {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.secondary)
                    Text("No contracts yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(contracts.sorted(by: { $0.contractNumber > $1.contractNumber })) { contract in
                    contractRow(contract)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(14)
    }
    
    private func contractRow(_ contract: Contract) -> some View {
        Button(action: { editingContract = contract }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Contract number badge
                    Text(contract.contractLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: contract.status.color))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    // Status
                    Text(contract.status.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Sessions progress
                HStack {
                    Text("\(contract.attendedSessions)/\(contract.totalSessions) sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if let expiry = contract.expiryDate {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(contract.isExpired ? .red : .secondary)
                    }
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(contract.attendedSessions) / CGFloat(max(contract.totalSessions, 1)), height: 6)
                    }
                }
                .frame(height: 6)
                
                // Payment info
                HStack(spacing: 12) {
                    Text("¥\(Int(contract.amountPaid))/¥\(Int(contract.totalAmount))")
                        .font(.system(size: 12))
                        .foregroundColor(contract.isFullyPaid ? .green : .orange)
                    
                    if contract.jerseyGiven {
                        Image(systemName: "tshirt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    if contract.ballGiven {
                        Image(systemName: "basketball.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
            }
            .padding(12)
            .background(.quaternary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Profile Photo Section
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            // Photo display
            ZStack {
                #if os(iOS)
                if let imageData = localImageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(studentColor, lineWidth: 3))
                } else if let selectedImage = selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(studentColor, lineWidth: 3))
                } else if let imageUrl = profileImageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(studentColor, lineWidth: 3))
                        default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
                #else
                if let imageUrl = profileImageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(studentColor, lineWidth: 3))
                        default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
                #endif
                
                // Upload indicator
                if isUploadingImage {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 120, height: 120)
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
                
                // Camera button overlay
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingPhotoSourceDialog = true }) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.accentColor)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .disabled(isUploadingImage)
                    }
                }
                .frame(width: 120, height: 120)
                #endif
            }
            
            // Name display
            VStack(spacing: 4) {
                Text(name.isEmpty ? (LocalizationManager.shared.currentLanguage == .chinese ? "新学员" : "New Athlete") : name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                if let grade = selectedSchoolGrade {
                    let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                    Text(isChinese ? "\(grade.localizedShortName) · 约 \(grade.estimatedAge) 岁" : "\(grade.shortName) · ~\(grade.estimatedAge) yrs")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Photo actions
            #if os(iOS)
            if profileImageUrl != nil || selectedImage != nil || localImageData != nil {
                Button(action: removePhoto) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Remove Photo")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
                .disabled(isUploadingImage)
            }
            #endif
            
            // Regenerate Card Background button
            Button(action: regenerateHeaderImage) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "更换卡片背景" : "Regenerate Card Background")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue.opacity(0.8))
            }
            
            // Error message
            if let error = uploadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 20)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [studentColor, studentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
            
            Text(name.isEmpty ? "?" : String(name.prefix(2)).uppercased())
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(studentColor.opacity(0.5), lineWidth: 3))
    }
    
    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 16) {
            Text(isChinese ? "基本信息" : "BASIC INFORMATION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)

            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "姓名" : "Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "全名" : "Full name", text: $name)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                    // Auto-fill the English name with the Pinyin of the
                    // Chinese name when the user fully clears it. We never
                    // want to land a Chinese student in the roster with an
                    // empty Latin name (it breaks alphabetic sorting and
                    // makes them invisible in some lists).
                    .onChange(of: name) { oldValue, newValue in
                        guard !oldValue.isEmpty, newValue.isEmpty else { return }
                        let trimmed = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        name = PinyinConverter.toPinyin(trimmed)
                    }
            }

            // Chinese name field
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "中文名 (可选)" : "Chinese Name (Optional)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("中文名", text: $chineseName)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
            }

            // School Grade
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isChinese ? "年级" : "School Grade")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let grade = selectedSchoolGrade {
                        Text(isChinese ? "约 \(grade.estimatedAge) 岁" : "~ \(grade.estimatedAge) yrs")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }

                gradeSection(
                    title: isChinese ? "幼儿园" : "Kindergarten",
                    grades: SchoolGrade.kindergartenGrades,
                    color: .pink
                )

                gradeSection(
                    title: isChinese ? "小学" : "Primary School",
                    grades: SchoolGrade.primaryGrades,
                    color: .blue
                )

                gradeSection(
                    title: isChinese ? "中学" : "High School",
                    grades: SchoolGrade.highschoolGrades,
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    private func gradeSection(title: String, grades: [SchoolGrade], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(grades, id: \.self) { grade in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSchoolGrade = grade
                        }
                        HapticFeedback.impact(.light)
                    }) {
                        Text(grade.localizedShortName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedSchoolGrade == grade ? .white : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedSchoolGrade == grade ? color : AppTheme.surfaceColor)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Assignment Section
    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ASSIGNMENT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            // Category
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button("None") { selectedCategoryId = nil }
                    ForEach(dataManager.ageCategories.filter { $0.isActive }) { category in
                        Button(action: { selectedCategoryId = category.id }) {
                            Label("\(category.shortName) - \(category.name)", systemImage: "circle.fill")
                        }
                    }
                } label: {
                    HStack {
                        if let categoryId = selectedCategoryId,
                           let category = dataManager.ageCategories.first(where: { $0.id == categoryId }) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)
                            Text("\(category.shortName) - \(category.name)")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text("Select category")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
            
            // Coach
            VStack(alignment: .leading, spacing: 8) {
                Text("Coach")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button("None") { selectedCoachId = nil }
                    ForEach(dataManager.staffCoaches.filter { $0.isActive }) { coach in
                        Button(action: { selectedCoachId = coach.id }) {
                            Label(coach.name, systemImage: coach.role.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let coachId = selectedCoachId,
                           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 12))
                                .foregroundColor(coach.role.color)
                            Text(coach.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text("Select coach")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
            
            // Program
            VStack(alignment: .leading, spacing: 8) {
                Text("Program")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Menu {
                    Button("None") { selectedProgramId = nil }
                    ForEach(dataManager.programs.filter { $0.isActive }) { program in
                        Button(action: { selectedProgramId = program.id }) {
                            Label(program.name, systemImage: program.mascot.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let programId = selectedProgramId,
                           let program = dataManager.programs.first(where: { $0.id == programId }) {
                            Image(systemName: program.mascot.icon)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: program.colorHex))
                            Text(program.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        } else {
                            Text("Select program")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Actions
    private func refreshContracts() {
        let studentId = student.id
        let allContracts = dataManager.contracts
        let filtered = allContracts.filter { $0.studentId == studentId }
        debugLog("🔄 refreshContracts: Total contracts in dataManager: \(allContracts.count)")
        debugLog("🔄 refreshContracts: Contracts for student \(studentId): \(filtered.count)")
        for c in filtered {
            debugLog("   - Contract ID: \(c.id), number: \(c.contractNumber), sessions: \(c.totalSessions)")
        }
        contracts = filtered
    }
    
    private func saveStudent() {
        // Update Student
        var updatedStudent = student
        updatedStudent.name = name.trimmingCharacters(in: .whitespaces)
        updatedStudent.chineseName = chineseName.isEmpty ? nil : chineseName.trimmingCharacters(in: .whitespaces)
        updatedStudent.schoolGrade = selectedSchoolGrade
        if let grade = selectedSchoolGrade {
            // Keep birthdate roughly in sync with grade so age-based features still work.
            updatedStudent.birthdate = grade.estimatedBirthdate
        }
        updatedStudent.categoryId = selectedCategoryId
        updatedStudent.coachId = selectedCoachId
        updatedStudent.programId = selectedProgramId
        updatedStudent.profileImageUrl = profileImageUrl
        #if os(iOS)
        if let imageData = localImageData {
            updatedStudent.profileImageData = imageData
            updatedStudent.thumbnailImageData = makeProfileThumbnailData(from: imageData)
        } else {
            updatedStudent.profileImageData = nil
            updatedStudent.thumbnailImageData = nil
        }
        #endif
        updatedStudent.updatedAt = Date()

        dataManager.updateStudent(updatedStudent)

        // Persist the exclude-from-export flag on the SDStudent.
        dataManager.setExcludedFromExport(studentId: student.id, excludeFromExport)

        // Update Player with parent info + header image (other player fields are managed elsewhere).
        if !parentName.isEmpty || !parentPhone.isEmpty || !parentEmail.isEmpty || headerImageURL != nil || player != nil {
            var updatedPlayer = player ?? Player(
                id: UUID(),
                studentId: student.id,
                handedness: .right
            )

            if !parentName.isEmpty || !parentPhone.isEmpty || !parentEmail.isEmpty {
                updatedPlayer.parentInfo = ParentInfo(
                    name: parentName,
                    relationship: parentRelationship,
                    phone: parentPhone,
                    email: parentEmail.isEmpty ? nil : parentEmail,
                    wechatId: parentWechat.isEmpty ? nil : parentWechat
                )
            }

            if let newHeaderURL = headerImageURL {
                updatedPlayer.headerImageURL = newHeaderURL
            }
            updatedPlayer.updatedAt = Date()

            dataManager.updatePlayer(updatedPlayer)
        }

        dismiss()
    }
    
    private func regenerateHeaderImage() {
        headerImageURL = StudentProfileHeaderView.randomBasketballURL()
    }
    
    #if os(iOS)
    private func uploadImage() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else { return }

        isUploadingImage = true
        uploadError = nil

        saveImageLocally(imageData)

        // Stage in local state; saveStudent() persists alongside other edits.
        localImageData = imageData

        isUploadingImage = false
    }
    
    private func saveImageLocally(_ imageData: Data) {
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let imagesDir = documentsDir.appendingPathComponent("StudentImages", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        
        let fileUrl = imagesDir.appendingPathComponent("\(student.id.uuidString).jpg")
        try? imageData.write(to: fileUrl)
        debugLog("✅ Image saved locally: \(fileUrl.path)")
    }
    
private func removePhoto() {
        withAnimation {
            selectedImage = nil
            localImageData = nil
            profileImageUrl = nil
        }

        deleteLocalImage()
        // Actual persistence happens on Save.
    }
    
    private func deleteLocalImage() {
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let fileUrl = documentsDir.appendingPathComponent("StudentImages/\(student.id.uuidString).jpg")
        try? fileManager.removeItem(at: fileUrl)
        debugLog("✅ Local image deleted")
    }
    #endif
}

// MARK: - Image Picker (iOS only)
#if os(iOS)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    /// Source can be `.photoLibrary` (default) or `.camera`. Callers should
    /// fall back to library if `.camera` isn't available on the device.
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        // Defensive: simulators / iPads without a camera will crash on .camera.
        if sourceType == .camera, UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .front
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

// MARK: - Contract Edit Sheet (Simplified)
struct ContractEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    let studentId: UUID
    let contract: Contract?
    let onSave: (Contract) -> Void
    var onDelete: ((Contract) -> Void)?
    
    // Simplified fields
    @State private var selectedContractType: ContractType
    @State private var enrollmentDate: Date
    @State private var notes: String
    @State private var showDeleteConfirmation = false
    
    // Attendance expansion
    @State private var isAttendanceExpanded = false
    @State private var attendanceFilterDate: Date? = nil
    
    private var isNewContract: Bool { contract == nil }
    
    init(studentId: UUID, contract: Contract?, onSave: @escaping (Contract) -> Void, onDelete: ((Contract) -> Void)? = nil) {
        self.studentId = studentId
        self.contract = contract
        self.onSave = onSave
        self.onDelete = onDelete
        
        _selectedContractType = State(initialValue: contract?.contractType ?? .privatePayPerSession)
        _enrollmentDate = State(initialValue: contract?.enrollmentDate ?? Date())
        _notes = State(initialValue: contract?.notes ?? "")
    }
    
    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }
    
    // MARK: - Contract Type Picker
    private func contractTypeButton(_ type: ContractType) -> some View {
        let isSelected = selectedContractType == type
        return Button {
            selectedContractType = type
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? type.displayNameChinese : type.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : AppTheme.textPrimary)
                    if type.isPayAsYouGo {
                        Text(isChinese ? "灵活安排，按次计费" : "Flexible, count sessions")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : AppTheme.textTertiary)
                    } else {
                        Text("\(type.totalSessions ?? 0) \(isChinese ? "节课" : "sessions")")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : AppTheme.textTertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(12)
            .background(isSelected ? Color.indigo : AppTheme.surfaceColor)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Contract Type Section (full width like Attendance)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.indigo)
                                Text(isChinese ? "合同类型" : "Contract Type")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                            
                            Picker("", selection: $selectedContractType) {
                                ForEach(ContractType.allCases, id: \.self) { type in
                                    Text(isChinese ? type.displayNameChinese : type.displayName)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.indigo)
                        }
                        .padding(16)
                        
                        // Contract summary for non-PAYG
                        if !selectedContractType.isPayAsYouGo {
                            Divider()
                                .padding(.horizontal, 16)
                            
                            HStack(spacing: 20) {
                                Label("\(selectedContractType.totalSessions ?? 0) sessions", systemImage: "number.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                                Label("\(selectedContractType.durationMonths ?? 0) months", systemImage: "calendar")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                Label("\(selectedContractType.sessionsPerWeek ?? 0)x/week", systemImage: "repeat")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.purple)
                            }
                            .padding(16)
                        }
                    }
                    .background(.regularMaterial)
                    .cornerRadius(14)
                    
                    // Session Count Display (expandable with session list)
                    if let existingContract = contract {
                        attendanceSection(existingContract)
                    }
                    
                    // Enrollment Date Section
                    sectionCard(title: isChinese ? "入学日期" : "Enrollment Date", icon: "calendar", color: .orange) {
                        DatePicker(isChinese ? "入学日期" : "Enrollment Date", selection: $enrollmentDate, displayedComponents: .date)
                            .font(.system(size: 14))
                            .environment(\.locale, isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US"))
                        
                        if !selectedContractType.isPayAsYouGo, let months = selectedContractType.durationMonths {
                            let expiryDate = Calendar.current.date(byAdding: .month, value: months, to: enrollmentDate) ?? enrollmentDate
                            HStack {
                                Text(isChinese ? "到期日期" : "Expiry Date")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatDate(expiryDate))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Notes Section
                    sectionCard(title: isChinese ? "备注" : "Notes", icon: "note.text", color: .gray) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 50)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(8)
                    }
                    
                    // Delete Button (only for existing contracts)
                    if !isNewContract, onDelete != nil {
                        Button(action: { showDeleteConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text(isChinese ? "删除合同" : "Delete Contract")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isNewContract ? (isChinese ? "新合同" : "New Contract") : (isChinese ? "编辑合同" : "Edit Contract"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { saveContract() }
                        .fontWeight(.semibold)
                }
            }
            .alert(isChinese ? "删除合同？" : "Delete Contract?", isPresented: $showDeleteConfirmation) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
                Button(isChinese ? "删除" : "Delete", role: .destructive) {
                    if let contract = contract {
                        onDelete?(contract)
                        dismiss()
                    }
                }
            } message: {
                Text(isChinese ? "此操作无法撤销。" : "This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Attendance Section (Expandable)
    private func attendanceSection(_ existingContract: Contract) -> some View {
        let attendedSessions = dataManager.attendedSessionDetails(for: studentId)
        let filteredSessions = filterAttendedSessions(attendedSessions)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header (tappable to expand)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isAttendanceExpanded.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text(isChinese ? "出勤记录" : "Attendance")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    // Session count summary
                    HStack(spacing: 12) {
                        Text("\(existingContract.sessionCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        
                        if !existingContract.isPayAsYouGo, let remaining = existingContract.remainingSessions {
                            Text("/ \(remaining) left")
                                .font(.system(size: 12))
                                .foregroundColor(remaining <= 3 ? .orange : AppTheme.textSecondary)
                        }
                    }
                    
                    Image(systemName: isAttendanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isAttendanceExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(spacing: 12) {
                    // Date filter bar (calendar only, no search)
                    HStack {
                        // Date filter picker inline
                        DatePicker(
                            isChinese ? "筛选日期" : "Filter by date",
                            selection: Binding(
                                get: { attendanceFilterDate ?? Date() },
                                set: { attendanceFilterDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .font(.system(size: 13))
                        
                        // Clear filter
                        if attendanceFilterDate != nil {
                            Button {
                                attendanceFilterDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Results count (when filtering)
                    if attendanceFilterDate != nil {
                        Text(isChinese ? "找到 \(filteredSessions.count) 条记录" : "Found \(filteredSessions.count) sessions")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                    }
                    
                    // Session list (scrollable, max height)
                    if filteredSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text(isChinese ? "暂无出勤记录" : "No sessions found")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(filteredSessions.enumerated()), id: \.element.id) { index, session in
                                    attendanceSessionRow(session, index: filteredSessions.count - index)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(14)
    }
    
    private func filterAttendedSessions(_ sessions: [SessionEvent]) -> [SessionEvent] {
        var filtered = sessions
        
        // Filter by date
        if let filterDate = attendanceFilterDate {
            filtered = filtered.filter { session in
                Calendar.current.isDate(session.date, inSameDayAs: filterDate)
            }
        }
        
        return filtered
    }
    
    private func attendanceSessionRow(_ session: SessionEvent, index: Int) -> some View {
        HStack(spacing: 10) {
            // Session number
            Text("#\(index)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.8))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Date
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    // Time
                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    // Program badge
                    if let programId = session.programId,
                       let program = dataManager.programs.first(where: { $0.id == programId }) {
                        Text(program.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(hex: program.colorHex))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: program.colorHex).opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Duration
            Text("\(session.durationMinutes)m")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary)
        .cornerRadius(8)
    }
    
    private func sectionCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            
            content()
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(14)
    }
    
    private func saveContract() {
        let contractNumber = contract?.contractNumber ?? 1
        
        // Use simplified initializer
        let updatedContract = Contract(
            id: contract?.id ?? UUID(),
            studentId: studentId,
            contractNumber: contractNumber,
            kind: selectedContractType,
            enrollmentDate: enrollmentDate,
            pricePerSession: contract?.pricePerSession ?? 0,
            bundleSize: contract?.bundleSize ?? 0,
            bundlePurchaseDate: contract?.bundlePurchaseDate,
            bundleSessionIds: contract?.bundleSessionIds ?? [],
            programId: contract?.programId,
            notes: notes.isEmpty ? nil : notes,
            createdByCoachId: contract?.createdByCoachId
        )

        onSave(updatedContract)
        dismiss()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    AddStudentView()
        .environmentObject(DataManager.shared)
}
