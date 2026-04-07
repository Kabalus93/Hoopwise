import SwiftUI

// MARK: - Session Reminder Section
/// A beautiful, award-winning inspired reminder UI for session notes
struct SessionReminderSection: View {
    @EnvironmentObject var dataManager: DataManager
    let sessionId: UUID
    let programId: UUID?
    
    @State private var showingAddReminder = false
    @State private var editingReminder: Reminder?
    
    private var sessionReminders: [Reminder] {
        dataManager.reminders(for: sessionId)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "提醒" : "REMINDERS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Spacer()
                
                // Add button
                Button(action: { showingAddReminder = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            
            // Reminders list or empty state
            VStack(spacing: 0) {
                if sessionReminders.isEmpty {
                    emptyState
                } else {
                    ForEach(sessionReminders) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            onToggle: { dataManager.toggleReminderCompletion(reminder) },
                            onTap: { editingReminder = reminder },
                            onDelete: { dataManager.deleteReminder(reminder) }
                        )
                        
                        if reminder.id != sessionReminders.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .sheet(isPresented: $showingAddReminder) {
            AddReminderSheet(
                sessionId: sessionId,
                programId: programId,
                existingReminder: nil
            )
        }
        .sheet(item: $editingReminder) { reminder in
            AddReminderSheet(
                sessionId: sessionId,
                programId: programId,
                existingReminder: reminder
            )
        }
    }
    
    private var emptyState: some View {
        Button(action: { showingAddReminder = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加提醒..." : "Add a reminder...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.6))
                
                Spacer()
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reminder Row
struct ReminderRow: View {
    @EnvironmentObject var dataManager: DataManager
    let reminder: Reminder
    let onToggle: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // Check if this reminder was shared with me
    private var isSharedWithMe: Bool {
        let currentCoachId = dataManager.loggedInCoachId ?? dataManager.coach.id
        return reminder.isSharedWith(coachId: currentCoachId)
    }
    
    // Get creator coach name
    private var creatorName: String? {
        guard isSharedWithMe else { return nil }
        return dataManager.staffCoaches.first { $0.id == reminder.creatorCoachId }?.name
    }
    
    // Get tagged student names
    private var taggedStudentNames: [String] {
        reminder.taggedStudentIds.compactMap { id in
            dataManager.students.first { $0.id == id }?.name
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Completion circle
            Button(action: {
                HapticFeedback.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onToggle()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(reminder.statusColor, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if reminder.isCompleted {
                        Circle()
                            .fill(reminder.statusColor)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Content
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(reminder.isCompleted ? .gray : .primary)
                        .strikethrough(reminder.isCompleted)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        // Due date badge
                        HStack(spacing: 4) {
                            Image(systemName: reminder.isOverdue ? "exclamationmark.circle.fill" : "calendar")
                                .font(.system(size: 10))
                            Text(reminder.relativeTimeString)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(reminder.statusColor)
                        
                        // Priority indicator (only for high)
                        if reminder.priority == .high {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                        
                        // Tagged students indicator
                        if !taggedStudentNames.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                Text(taggedStudentNames.count == 1 ? taggedStudentNames[0] : "\(taggedStudentNames.count)")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                    // Shared by indicator
                    if let creatorName = creatorName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9))
                            Text(isChinese ? "来自 \(creatorName)" : "From \(creatorName)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.purple)
                    }
                }
                
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isPressed ? Color.gray.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add/Edit Reminder Sheet
struct AddReminderSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    let sessionId: UUID
    let programId: UUID?
    let existingReminder: Reminder?
    
    @State private var title = ""
    @State private var note = ""
    @State private var dueDate = Date()
    @State private var priority: ReminderPriority = .medium
    @State private var selectedPreset: QuickReminderPreset?
    @State private var showingDatePicker = false
    
    // Tagging
    @State private var taggedStudentIds: Set<UUID> = []
    @State private var taggedCoachIds: Set<UUID> = []
    @State private var showingStudentPicker = false
    @State private var showingCoachPicker = false
    
    private var isEditing: Bool { existingReminder != nil }
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // Get tagged students
    private var taggedStudents: [Student] {
        dataManager.students.filter { taggedStudentIds.contains($0.id) }
    }
    
    // Get tagged coaches
    private var taggedCoaches: [StaffCoach] {
        dataManager.staffCoaches.filter { taggedCoachIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Title input
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(isChinese ? "提醒内容..." : "Remind me to...", text: $title, axis: .vertical)
                            .font(.system(size: 18, weight: .medium))
                            .lineLimit(3...5)
                            .padding(16)
                            #if canImport(UIKit)
                            .background(Color(UIColor.systemGray6))
                            #else
                            .background(Color(NSColor.controlBackgroundColor))
                            #endif
                            .cornerRadius(12)
                    }
                    
                    // Quick presets
                    if !isEditing {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isChinese ? "快速设置" : "QUICK SET")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 10) {
                                ForEach([QuickReminderPreset.tomorrow, .nextWeek], id: \.displayName) { preset in
                                    QuickPresetButton(
                                        preset: preset,
                                        isSelected: selectedPreset == preset,
                                        action: {
                                            selectedPreset = preset
                                            dueDate = preset.date()
                                            showingDatePicker = false
                                        }
                                    )
                                }
                                
                                QuickPresetButton(
                                    preset: .custom,
                                    isSelected: showingDatePicker,
                                    action: {
                                        selectedPreset = .custom
                                        showingDatePicker = true
                                    }
                                )
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // Date picker (shown when custom or editing)
                    if showingDatePicker || isEditing {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(isChinese ? "到期日期" : "DUE DATE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            DatePicker(
                                "",
                                selection: $dueDate,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .padding(12)
                            #if canImport(UIKit)
                            .background(Color(UIColor.systemGray6))
                            #else
                            .background(Color(NSColor.controlBackgroundColor))
                            #endif
                            .cornerRadius(12)
                        }
                    }
                    
                    // MARK: - Tagging Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "标记" : "TAG")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        
                        // Tag buttons row
                        HStack(spacing: 10) {
                            // Tag student button
                            Button(action: { showingStudentPicker = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12))
                                    Text(isChinese ? "学员" : "Student")
                                        .font(.system(size: 12, weight: .medium))
                                    if !taggedStudentIds.isEmpty {
                                        Text("\(taggedStudentIds.count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .cornerRadius(10)
                                    }
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                            
                            // Tag coach button (only show if there are staff coaches)
                            if !dataManager.staffCoaches.isEmpty {
                                Button(action: { showingCoachPicker = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.badge.shield.checkmark.fill")
                                            .font(.system(size: 12))
                                        Text(isChinese ? "教练" : "Coach")
                                            .font(.system(size: 12, weight: .medium))
                                        if !taggedCoachIds.isEmpty {
                                            Text("\(taggedCoachIds.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.purple)
                                                .cornerRadius(10)
                                        }
                                    }
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                        }
                        
                        // Show tagged items
                        if !taggedStudents.isEmpty || !taggedCoaches.isEmpty {
                            FlowLayoutTags {
                                // Tagged students
                                ForEach(taggedStudents) { student in
                                    TagChip(
                                        name: student.name,
                                        color: .blue,
                                        icon: "person.fill",
                                        onRemove: { taggedStudentIds.remove(student.id) }
                                    )
                                }
                                
                                // Tagged coaches
                                ForEach(taggedCoaches) { coach in
                                    TagChip(
                                        name: coach.name,
                                        color: .purple,
                                        icon: "person.badge.shield.checkmark.fill",
                                        onRemove: { taggedCoachIds.remove(coach.id) }
                                    )
                                }
                            }
                        }
                        
                        // Hint about coach tagging
                        if !taggedCoachIds.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text(isChinese ? "标记的教练会在他们的首页看到此提醒" : "Tagged coaches will see this reminder on their dashboard")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                        }
                    }
                    
                    // Priority selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "优先级" : "PRIORITY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 10) {
                            ForEach(ReminderPriority.allCases, id: \.self) { p in
                                PriorityButton(
                                    priority: p,
                                    isSelected: priority == p,
                                    action: { priority = p }
                                )
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Optional note
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isChinese ? "备注（可选）" : "NOTE (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        
                        TextField(isChinese ? "添加备注..." : "Add a note...", text: $note, axis: .vertical)
                            .font(.system(size: 14))
                            .lineLimit(2...4)
                            .padding(12)
                            #if canImport(UIKit)
                            .background(Color(UIColor.systemGray6))
                            #else
                            .background(Color(NSColor.controlBackgroundColor))
                            #endif
                            .cornerRadius(12)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            #if canImport(UIKit)
            .background(Color(UIColor.systemBackground))
            #else
            .background(Color(NSColor.windowBackgroundColor))
            #endif
            .navigationTitle(isEditing ? (isChinese ? "编辑提醒" : "Edit Reminder") : (isChinese ? "新提醒" : "New Reminder"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        saveReminder()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty)
                }
            }
            .onAppear {
                if let existing = existingReminder {
                    title = existing.title
                    note = existing.note ?? ""
                    dueDate = existing.dueDate
                    priority = existing.priority
                    taggedStudentIds = Set(existing.taggedStudentIds)
                    taggedCoachIds = Set(existing.taggedCoachIds)
                }
            }
            .sheet(isPresented: $showingStudentPicker) {
                ReminderStudentPicker(selectedIds: $taggedStudentIds, programId: programId)
            }
            .sheet(isPresented: $showingCoachPicker) {
                ReminderCoachPicker(selectedIds: $taggedCoachIds)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func saveReminder() {
        if let existing = existingReminder {
            var updated = existing
            updated.title = title
            updated.note = note.isEmpty ? nil : note
            updated.dueDate = dueDate
            updated.priority = priority
            updated.taggedStudentIds = Array(taggedStudentIds)
            updated.taggedCoachIds = Array(taggedCoachIds)
            updated.updatedAt = Date()
            dataManager.updateReminder(updated)
        } else {
            let reminder = Reminder(
                title: title,
                note: note.isEmpty ? nil : note,
                dueDate: dueDate,
                priority: priority,
                sessionId: sessionId,
                programId: programId,
                taggedStudentIds: Array(taggedStudentIds),
                taggedCoachIds: Array(taggedCoachIds)
            )
            dataManager.addReminder(reminder)
        }
        HapticFeedback.notification(.success)
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let name: String
    let color: Color
    let icon: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Flow Layout for Tags
struct FlowLayoutTags: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Student Picker for Reminders
struct ReminderStudentPicker: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedIds: Set<UUID>
    let programId: UUID?
    @State private var searchText = ""
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // Get students enrolled in the program (or all if no program)
    private var programStudents: [Student] {
        guard let programId = programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
            return dataManager.students
        }
        return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    private var filteredStudents: [Student] {
        if searchText.isEmpty {
            return programStudents
        }
        let search = searchText.lowercased()
        return programStudents.filter { student in
            student.name.lowercased().contains(search) ||
            (student.chineseName?.lowercased().contains(search) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredStudents.isEmpty {
                    ContentUnavailableView(
                        isChinese ? "暂无学员" : "No Students",
                        systemImage: "person.slash",
                        description: Text(isChinese ? "该项目尚未添加学员" : "No students enrolled in this program")
                    )
                } else {
                    ForEach(filteredStudents) { student in
                        studentRow(student)
                    }
                }
            }
            .searchable(text: $searchText, prompt: isChinese ? "搜索学员..." : "Search students...")
            .navigationTitle(isChinese ? "标记学员" : "Tag Students")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func studentRow(_ student: Student) -> some View {
        Button {
            if selectedIds.contains(student.id) {
                selectedIds.remove(student.id)
            } else {
                selectedIds.insert(student.id)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(student.avatarColor.color))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    if let chinese = student.chineseName {
                        Text(chinese)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if selectedIds.contains(student.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coach Picker for Reminders
struct ReminderCoachPicker: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedIds: Set<UUID>
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    private var activeCoaches: [StaffCoach] {
        dataManager.staffCoaches.filter { $0.isActive }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(activeCoaches) { coach in
                    coachRow(coach)
                }
            }
            .navigationTitle(isChinese ? "标记教练" : "Tag Coaches")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    @ViewBuilder
    private func coachRow(_ coach: StaffCoach) -> some View {
        Button {
            if selectedIds.contains(coach.id) {
                selectedIds.remove(coach.id)
            } else {
                selectedIds.insert(coach.id)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text(coach.role.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if selectedIds.contains(coach.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Preset Button
struct QuickPresetButton: View {
    let preset: QuickReminderPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 12))
                Text(preset.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #if canImport(UIKit)
            .background(isSelected ? Color.orange : Color(UIColor.systemGray6))
            #else
            .background(isSelected ? Color.orange : Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Priority Button
struct PriorityButton: View {
    let priority: ReminderPriority
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: priority.icon)
                    .font(.system(size: 12))
                Text(priority.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : priority.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? priority.color : priority.color.opacity(0.1))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Reminder Badge (for dashboard)
struct ReminderBadge: View {
    let reminder: Reminder
    let onToggle: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Completion circle
                Button(action: {
                    HapticFeedback.impact(.light)
                    onToggle()
                }) {
                    Circle()
                        .stroke(reminder.statusColor, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(reminder.relativeTimeString)
                        .font(.system(size: 11))
                        .foregroundColor(reminder.statusColor)
                }
                
                Spacer()
                
                if reminder.priority == .high {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(12)
            #if canImport(UIKit)
            .background(Color(UIColor.systemBackground))
            #else
            .background(Color(NSColor.windowBackgroundColor))
            #endif
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
