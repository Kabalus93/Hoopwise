import SwiftUI

/// Shows a list of all sessions a student has attended
struct AttendedSessionsListView: View {
    @EnvironmentObject var dataManager: DataManager
    let studentId: UUID
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var showingDateFilter = false
    
    private var student: Student? {
        dataManager.students.first { $0.id == studentId }
    }
    
    private var allAttendedSessions: [SessionEvent] {
        dataManager.attendedSessionDetails(for: studentId)
    }
    
    private var attendedSessions: [SessionEvent] {
        allAttendedSessions.filter { session in
            session.date >= startDate && session.date <= Calendar.current.date(byAdding: .day, value: 1, to: endDate)!
        }
    }
    
    private var allExcusedSessions: [SessionEvent] {
        dataManager.cachedSessionEvents.filter { event in
            event.excusedAbsences.contains(studentId)
        }.sorted { $0.date > $1.date }
    }
    
    private var excusedSessions: [SessionEvent] {
        allExcusedSessions.filter { session in
            session.date >= startDate && session.date <= Calendar.current.date(byAdding: .day, value: 1, to: endDate)!
        }
    }
    
    var body: some View {
        List {
            // Compact Header: Date + Stats
            Section {
                compactHeader
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            // Attended Sessions
            Section {
                if attendedSessions.isEmpty {
                    emptyState
                } else {
                    ForEach(attendedSessions) { session in
                        sessionRow(session, type: .attended)
                    }
                }
            } header: {
                Text(isChinese ? "出勤记录 (\(attendedSessions.count))" : "Attended (\(attendedSessions.count))")
            }
            
            // Excused Absences
            if !excusedSessions.isEmpty {
                Section {
                    ForEach(excusedSessions) { session in
                        sessionRow(session, type: .excused)
                    }
                } header: {
                    Text(isChinese ? "请假记录 (\(excusedSessions.count))" : "Excused (\(excusedSessions.count))")
                }
            }
        }
        .listStyle(.plain)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(isChinese ? "出勤历史" : "Attendance History")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
    }
    
    // MARK: - Compact Header
    private var compactHeader: some View {
        VStack(spacing: 4) {
            // Date range row
            HStack(spacing: 6) {
                dateChipPicker(selection: $startDate)
                
                Text("–")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                
                dateChipPicker(selection: $endDate)
                
                Spacer()
                
                Menu {
                    Button(isChinese ? "全部" : "All") {
                        if let earliest = allAttendedSessions.last?.date { startDate = earliest }
                        endDate = Date()
                    }
                    Button(isChinese ? "本月" : "This Month") {
                        startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
                        endDate = Date()
                    }
                    Button(isChinese ? "3个月" : "3 Months") {
                        startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
                        endDate = Date()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            
            // Inline stats badges
            HStack(spacing: 0) {
                statBadge(attendedSessions.count, isChinese ? "出勤" : "Attended", .green)
                statBadge(excusedSessions.count, isChinese ? "请假" : "Excused", .orange)
                statBadge(attendedSessions.count, isChinese ? "计入" : "Counted", .blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func dateChipPicker(selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .font(.system(size: 12, weight: .medium))
            .tint(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.surfaceColor)
            .clipShape(Capsule())
    }
    
    private func statBadge(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Session Row
    private enum SessionType {
        case attended, excused
    }
    
    private func sessionRow(_ session: SessionEvent, type: SessionType) -> some View {
        HStack(spacing: 8) {
            // Status icon
            Circle()
                .fill(type == .attended ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: type == .attended ? "checkmark" : "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(type == .attended ? .green : .orange)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Date
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    // Time
                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    // Program name if available
                    if let programId = session.programId,
                       let program = dataManager.programs.first(where: { $0.id == programId }) {
                        Text(program.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(hex: program.colorHex))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: program.colorHex).opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Duration
            Text("\(session.durationMinutes) min")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(isChinese ? "暂无出勤记录" : "No attendance records yet")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            
            Text(isChinese ? "学生参加课程后会在这里显示记录" : "Sessions will appear here once attended")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    NavigationStack {
        AttendedSessionsListView(studentId: UUID())
            .environmentObject(DataManager.shared)
    }
}
