import SwiftUI
import Combine
#if os(iOS)
import UIKit
import AVFoundation
#endif

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
    /// Adding a new athlete: the same screen as editing one (October 2026,
    /// Luther), over a fresh record that is only written on Save.
    let isNew: Bool

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
    @State private var showingProfileCamera = false
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

    /// Add a new athlete.
    init() {
        self.init(student: Student(name: "", avatarColor: AvatarColor.allCases.randomElement() ?? .blue),
                  player: nil, isNew: true)
    }

    init(student: Student, player: Player?) {
        self.init(student: student, player: player, isNew: false)
    }

    private init(student: Student, player: Player?, isNew: Bool) {
        self.student = student
        self.player = player
        self.isNew = isNew

        // Basic Info
        _name = State(initialValue: student.name)
        _chineseName = State(initialValue: student.chineseName ?? "")
        _selectedSchoolGrade = State(initialValue: student.currentSchoolGrade())
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
                    .disabled(isUploadingImage || !canSave)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, sourceType: imagePickerSource)
            }
            .fullScreenCover(isPresented: $showingProfileCamera) {
                ProfilePhotoCamera { image in
                    if let image { selectedImage = image }
                    showingProfileCamera = false
                }
            }
            .confirmationDialog(
                LocalizationManager.shared.currentLanguage == .chinese ? "添加照片" : "Add Photo",
                isPresented: $showingPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "拍照" : "Take Photo") {
                        showingProfileCamera = true
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

            // School Grade — one field-shaped row and one menu, not three
            // grids of fifteen chips (October 2026, Luther: the grids made a
            // page that fits on one screen scroll).
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "年级" : "School Grade")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Menu {
                    gradeMenuSection(isChinese ? "幼儿园" : "Kindergarten", SchoolGrade.kindergartenGrades)
                    gradeMenuSection(isChinese ? "小学" : "Primary School", SchoolGrade.primaryGrades)
                    gradeMenuSection(isChinese ? "中学" : "Secondary School", SchoolGrade.highschoolGrades)
                    if selectedSchoolGrade != nil {
                        Divider()
                        Button(role: .destructive) {
                            selectedSchoolGrade = nil
                        } label: {
                            Label(isChinese ? "清除年级" : "Clear grade", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    HStack {
                        if let grade = selectedSchoolGrade {
                            Text(grade.displayName)
                                .foregroundStyle(.primary)
                            Text(isChinese ? "约 \(grade.estimatedAge) 岁" : "~\(grade.estimatedAge) yrs")
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(isChinese ? "未设置" : "Not set")
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 16))
                    // A Menu tints its label with the accent; the hierarchical
                    // styles here must resolve against primary, like the text
                    // fields above, or the row reads as a blue button.
                    .foregroundStyle(Color.primary)
                    .padding(14)
                    .background(.quaternary)
                    .cornerRadius(12)
                }
                .tint(Color.primary)
                .sensoryFeedback(.selection, trigger: selectedSchoolGrade)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    @ViewBuilder
    private func gradeMenuSection(_ title: String, _ grades: [SchoolGrade]) -> some View {
        Section(title) {
            ForEach(grades, id: \.self) { grade in
                Button {
                    selectedSchoolGrade = grade
                } label: {
                    if selectedSchoolGrade == grade {
                        Label(grade.displayName, systemImage: "checkmark")
                    } else {
                        Text(grade.displayName)
                    }
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
    
    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        // A new athlete may be entered by Chinese name alone; pinyin is derived.
        return isNew ? hasName || !chineseName.trimmingCharacters(in: .whitespaces).isEmpty : !name.isEmpty
    }

    private func saveStudent() {
        if isNew { createStudent(); return }
        // Update Student
        var updatedStudent = student
        updatedStudent.name = name.trimmingCharacters(in: .whitespaces)
        updatedStudent.chineseName = chineseName.isEmpty ? nil : chineseName.trimmingCharacters(in: .whitespaces)
        // Grade + its September birthdate anchor, written together so the
        // grade keeps promoting itself each school year.
        updatedStudent.setSchoolGrade(selectedSchoolGrade)
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
    
    private func createStudent() {
        // The name field holds pinyin; hanzi typed there, or a Chinese name
        // alone, becomes pinyin (the convention the import also follows).
        var finalName = name.trimmingCharacters(in: .whitespaces)
        let finalChineseName = chineseName.trimmingCharacters(in: .whitespaces)
        if finalName.isEmpty && !finalChineseName.isEmpty {
            finalName = PinyinConverter.toPinyin(finalChineseName)
        } else if !finalChineseName.isEmpty && PinyinConverter.isPurelyChinese(finalName) {
            finalName = PinyinConverter.toPinyin(finalName)
        }

        var newStudent = student
        newStudent.name = finalName
        newStudent.chineseName = finalChineseName.isEmpty ? nil : finalChineseName
        newStudent.setSchoolGrade(selectedSchoolGrade)
        newStudent.createdByCoachId = dataManager.loggedInCoachId
        #if os(iOS)
        if let imageData = localImageData {
            newStudent.profileImageData = imageData
            newStudent.thumbnailImageData = makeProfileThumbnailData(from: imageData)
        }
        #endif

        var newPlayer = Player(id: UUID(), studentId: newStudent.id, handedness: .right)
        if !parentName.isEmpty || !parentPhone.isEmpty || !parentEmail.isEmpty || !parentWechat.isEmpty {
            newPlayer.parentInfo = ParentInfo(
                name: parentName,
                relationship: parentRelationship,
                phone: parentPhone,
                email: parentEmail.isEmpty ? nil : parentEmail,
                wechatId: parentWechat.isEmpty ? nil : parentWechat
            )
        }
        newPlayer.headerImageURL = headerImageURL

        dataManager.addStudent(newStudent, player: newPlayer)
        dataManager.setExcludedFromExport(studentId: newStudent.id, excludeFromExport)
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
    EditStudentView()
        .environmentObject(DataManager.shared)
}
