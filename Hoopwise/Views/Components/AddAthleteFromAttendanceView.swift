import SwiftUI

// MARK: - Add Athlete From Attendance View
/// A view for enrolling new students into a program from the session attendance page
/// Contract sessions will start counting from the enrollment session
struct AddAthleteFromAttendanceView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    let session: SessionEvent
    let program: Program?
    let onEnroll: (UUID) -> Void
    
    @State private var searchText = ""
    @State private var selectedStudentId: UUID?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    // Students not already enrolled in the program
    var availableStudents: [Student] {
        guard let program = program else { return [] }
        let enrolledIds = Set(program.enrolledStudentIds)
        return dataManager.students
            .filter { !enrolledIds.contains($0.id) }
            .filter { student in
                if searchText.isEmpty { return true }
                return student.name.localizedCaseInsensitiveContains(searchText) ||
                       (student.chineseName ?? "").localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name < $1.name }
    }
    
    var programColor: Color {
        guard let program = program else { return .purple }
        return Color(hex: program.colorHex)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Info banner
                infoBanner
                
                // Search bar
                searchBar
                
                // Student list
                if availableStudents.isEmpty {
                    emptyState
                } else {
                    studentList
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "添加学员" : "Add Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "添加" : "Add") {
                        if let studentId = selectedStudentId {
                            onEnroll(studentId)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(programColor.accessibleText)
                    .disabled(selectedStudentId == nil)
                }
            }
        }
    }
    
    private var infoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(programColor.accessibleText)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? "从此课程开始计费" : "Sessions Count From Here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(isChinese ? "学员的合约课时将从本节课开始计算" : "The student's contract sessions will count starting from this session")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(programColor.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textTertiary)
            TextField(isChinese ? "搜索学员..." : "Search athletes...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var studentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(availableStudents) { student in
                    studentRow(student)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }
    
    private func studentRow(_ student: Student) -> some View {
        let isSelected = selectedStudentId == student.id
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedStudentId = nil
                } else {
                    selectedStudentId = student.id
                }
            }
            HapticFeedback.impact(.light)
        }) {
            HStack(spacing: 12) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? programColor : AppTheme.textTertiary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(programColor)
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Avatar
                StudentAvatarView(student: student, size: 44)
                
                // Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    HStack(spacing: 8) {
                        if let chinese = student.chineseName, !chinese.isEmpty, chinese != student.name {
                            Text(chinese)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        
                        // Show contract info if available
                        if let contract = dataManager.currentContract(for: student.id) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 9))
                                if contract.isPayAsYouGo {
                                    Text(isChinese ? "按次付费" : "Pay-as-you-go")
                                } else if let remaining = contract.remainingSessions {
                                    Text(isChinese ? "\(remaining)节剩余" : "\(remaining) left")
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(isSelected ? programColor.opacity(0.1) : AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? programColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(searchText.isEmpty
                 ? (isChinese ? "所有学员都已加入此项目" : "All students are already enrolled")
                 : (isChinese ? "没有找到匹配的学员" : "No matching students found"))
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    AddAthleteFromAttendanceView(
        session: SessionEvent(programId: nil, sessionType: .training, title: "Test", date: Date(), startTime: Date(), endTime: Date()),
        program: nil,
        onEnroll: { _ in }
    )
    .environmentObject(DataManager.shared)
}
