import SwiftUI

// MARK: - Calendar Monthly View (Apple Calendar Style)
struct CalendarMonthlyView: View {
    @Binding var selectedDate: Date
    let sessions: [SessionEvent]
    let onDateSelected: (Date) -> Void
    
    @State private var currentMonth: Date = Date()
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with month/year and navigation
            monthHeader
            
            // Weekday labels
            weekdayLabels
            
            // Calendar grid
            ScrollView(showsIndicators: false) {
                monthGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Month Header
    private var monthHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")

        return HStack {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                        currentMonth = newMonth
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(.secondary)
            .sensoryFeedback(.selection, trigger: currentMonth)

            Spacer()

            VStack(spacing: 2) {
                Text(currentMonth.formatted(.dateTime.month(.wide).locale(locale)))
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(currentMonth.formatted(.dateTime.year().locale(locale)))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                        currentMonth = newMonth
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Weekday Labels
    private var weekdayLabels: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let sundayFirst = isChinese ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"]
        // Align column 0 with calendar.firstWeekday so labels track the grid below.
        let offset = (calendar.firstWeekday - 1 + 7) % 7
        let weekdaySymbols = Array(sundayFirst[offset...]) + Array(sundayFirst[..<offset])

        return HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Month Grid
    private var monthGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 60)
                }
            }
        }
    }
    
    // MARK: - Day Cell
    private func dayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        let daySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
        
        return Button {
            onDateSelected(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(Color.white) :
                        isToday ? AnyShapeStyle(Color.accentColor) :
                        isCurrentMonth ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.quaternary)
                    )
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
                    }

                HStack(spacing: 2) {
                    ForEach(0..<min(daySessions.count, 3), id: \.self) { index in
                        Circle()
                            .fill(sessionColor(for: daySessions[index]))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
    
    // MARK: - Helper Functions
    private func daysInMonth() -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: currentMonth)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Fill trailing empty days to complete the grid
        let remainingDays = (7 - (days.count % 7)) % 7
        days.append(contentsOf: Array(repeating: nil, count: remainingDays))
        
        return days
    }
    
    private func sessionColor(for session: SessionEvent) -> Color {
        Color.accentColor.opacity(0.8)
    }
}
