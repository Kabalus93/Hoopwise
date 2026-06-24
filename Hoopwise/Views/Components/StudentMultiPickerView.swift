import SwiftUI

// MARK: - Student Multi-Picker View
/// A view for selecting multiple students with search and visual feedback
struct StudentMultiPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIds: Set<UUID>
    let students: [Student]
    var accentColor: Color = .purple
    
    @State private var searchText = ""
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var filteredStudents: [Student] {
        if searchText.isEmpty {
            return students.sorted { $0.name < $1.name }
        }
        return students.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.chineseName ?? "").localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
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
                .padding(.top, 8)
                
                // Selection count
                HStack {
                    Text(isChinese ? "已选择 \(selectedIds.count) 名学员" : "\(selectedIds.count) athletes selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    if !selectedIds.isEmpty {
                        Button(isChinese ? "清除" : "Clear") {
                            selectedIds.removeAll()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // Student list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredStudents) { student in
                            studentRow(student)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "选择学员" : "Select Athletes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func studentRow(_ student: Student) -> some View {
        let isSelected = selectedIds.contains(student.id)
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedIds.remove(student.id)
                } else {
                    selectedIds.insert(student.id)
                }
            }
            HapticFeedback.impact(.light)
        }) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : AppTheme.textTertiary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Avatar
                Circle()
                    .fill(Color.avatarColor(student.avatarColor))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(student.initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if let chinese = student.chineseName, !chinese.isEmpty, chinese != student.name {
                        Text(chinese)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(isSelected ? accentColor.opacity(0.1) : AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StudentMultiPickerView(
        selectedIds: .constant([]),
        students: []
    )
}
