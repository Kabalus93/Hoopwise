import SwiftUI
import Combine

// MARK: - Date Header
struct CalendarDateHeader: View {
    let selectedDate: Date
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        
        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year().locale(locale)))
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .background(AppTheme.background)
    }
}

// MARK: - Timeline View (iOS Calendar Style)
struct CalendarTimelineView: View {
    let sessions: [SessionEvent]
    let programsById: [UUID: Program]
    let selectedDate: Date
    let currentTime: Date
    @Binding var showingCreateSession: Bool
    
    @State private var hourHeight: CGFloat = 60
    @State private var liveCurrentTime = Date()
    @GestureState private var magnification: CGFloat = 1.0
    
    private let hours = Array(4...23) // 4 AM to 11 PM
    private let minHourHeight: CGFloat = 30
    private let maxHourHeight: CGFloat = 120
    private let timeColumnWidth: CGFloat = 58
    private let trailingPadding: CGFloat = 12
    private let eventColumnSpacing: CGFloat = 6
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Hour labels and grid lines
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            ZStack(alignment: .topLeading) {
                                // Hour block container
                                Color.clear
                                    .frame(height: hourHeight * magnification)
                                
                                // Hour label and grid line at the very top
                                HStack(alignment: .center, spacing: 0) {
                                    Text(hourLabel(hour))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textTertiary)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 8)
                                    
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 0.5)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .id(hour)
                        }
                    }

                    GeometryReader { geometry in
                        let layouts = overlappingSessionLayouts(in: geometry.size.width)
                        ForEach(layouts, id: \.session.id) { layout in
                            sessionBlock(for: layout)
                        }
                    }

                    if Calendar.current.isDate(liveCurrentTime, inSameDayAs: selectedDate) {
                        currentTimeIndicator
                            .zIndex(10)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.bottom, 100)
            }
            .gesture(
                MagnificationGesture()
                    .updating($magnification) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        let newHeight = hourHeight * value
                        hourHeight = min(max(newHeight, minHourHeight), maxHourHeight)
                    }
            )
            .onAppear {
                liveCurrentTime = Date()
                scrollToClosestSession(proxy: proxy)
            }
            .onReceive(timer) { _ in
                liveCurrentTime = Date()
            }
        }
    }
    
    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func scrollToClosestSession(proxy: ScrollViewProxy) {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDate(now, inSameDayAs: selectedDate) {
            if let inProgress = sessions.first(where: { $0.startTime <= now && $0.endTime > now }) {
                let hour = calendar.component(.hour, from: inProgress.startTime)
                if hours.contains(hour) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(max(hour - 1, hours.first ?? 4), anchor: .top)
                        }
                    }
                }
                return
            }

            let hour = calendar.component(.hour, from: now)
            if hours.contains(hour) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(max(hour - 1, hours.first ?? 4), anchor: .top)
                    }
                }
            }
            return
        }

        let sortedSessions = sessions.sorted { $0.startTime < $1.startTime }
        if let first = sortedSessions.first {
            let hour = calendar.component(.hour, from: first.startTime)
            if hours.contains(hour) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(max(hour - 1, hours.first ?? 4), anchor: .top)
                    }
                }
            }
        }
    }
    
    private var currentTimeIndicator: some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: liveCurrentTime)
        let minute = calendar.component(.minute, from: liveCurrentTime)
        let second = calendar.component(.second, from: liveCurrentTime)
        
        // Calculate precise offset including seconds for smooth movement
        let effectiveHourHeight = hourHeight * magnification
        let totalMinutes = CGFloat(minute) + (CGFloat(second) / 60.0)
        let offset = CGFloat(hour - hours.first!) * effectiveHourHeight + (totalMinutes / 60.0) * effectiveHourHeight
        
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .padding(.leading, 50)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: offset)
    }

    private func overlappingSessionLayouts(in totalWidth: CGFloat) -> [SessionLayout] {
        let sortedSessions = sessions.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }

        let usableWidth = max(totalWidth - timeColumnWidth - trailingPadding, 120)
        var layouts: [SessionLayout] = []
        var activeColumns: [SessionEvent?] = []
        var activeIndicesBySessionId: [UUID: Int] = [:]
        var activeGroupSessionIds: [UUID] = []

        func finalizeActiveGroup() {
            guard !activeGroupSessionIds.isEmpty else { return }
            let maxColumnCount = max(activeColumns.count, 1)
            let totalSpacing = eventColumnSpacing * CGFloat(max(maxColumnCount - 1, 0))
            let columnWidth = max((usableWidth - totalSpacing) / CGFloat(maxColumnCount), 1)

            for sessionId in activeGroupSessionIds {
                guard let layoutIndex = layouts.firstIndex(where: { $0.session.id == sessionId }),
                      let columnIndex = activeIndicesBySessionId[sessionId] else { continue }
                let leading = timeColumnWidth + CGFloat(columnIndex) * (columnWidth + eventColumnSpacing)
                layouts[layoutIndex].columnIndex = columnIndex
                layouts[layoutIndex].columnCount = maxColumnCount
                layouts[layoutIndex].leading = leading
                layouts[layoutIndex].width = columnWidth
            }

            activeColumns.removeAll()
            activeIndicesBySessionId.removeAll()
            activeGroupSessionIds.removeAll()
        }

        for session in sortedSessions {
            for index in activeColumns.indices {
                if let activeSession = activeColumns[index], activeSession.endTime <= session.startTime {
                    activeColumns[index] = nil
                }
            }

            if activeColumns.allSatisfy({ $0 == nil }) {
                finalizeActiveGroup()
            }

            let assignedColumn: Int
            if let reusableIndex = activeColumns.firstIndex(where: { $0 == nil }) {
                assignedColumn = reusableIndex
                activeColumns[reusableIndex] = session
            } else {
                assignedColumn = activeColumns.count
                activeColumns.append(session)
            }

            activeIndicesBySessionId[session.id] = assignedColumn
            activeGroupSessionIds.append(session.id)
            layouts.append(SessionLayout(session: session, columnIndex: assignedColumn, columnCount: 1, leading: timeColumnWidth, width: usableWidth))
        }

        finalizeActiveGroup()
        return layouts
    }

    private func sessionBlock(for layout: SessionLayout) -> some View {
        let session = layout.session
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: session.startTime)
        let startMinute = calendar.component(.minute, from: session.startTime)
        let program = session.programId.flatMap { programsById[$0] }
        let blockColor = program.map { Color(hex: $0.colorHex) } ?? Color.blue
        
        let effectiveHourHeight = hourHeight * magnification
        let startOffset = CGFloat(startHour - hours.first!) * effectiveHourHeight + (CGFloat(startMinute) / 60.0) * effectiveHourHeight
        let duration = session.endTime.timeIntervalSince(session.startTime) / 3600.0
        let blockHeight = CGFloat(duration) * effectiveHourHeight
        let compactLayout = layout.columnCount > 1 || blockHeight < 56
        
        return NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
            VStack(alignment: .leading, spacing: compactLayout ? 1 : 3) {
                Text(session.title)
                    .font(.system(size: compactLayout ? 11 : 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(compactLayout ? 2 : 1)
                
                Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: compactLayout ? 9 : 10))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, compactLayout ? 6 : 8)
            .padding(.vertical, compactLayout ? 5 : 8)
            .frame(width: layout.width, alignment: .leading)
            .frame(height: max(blockHeight - 2, 30))
            .background(blockColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .frame(width: layout.width, alignment: .leading)
        .offset(x: layout.leading, y: startOffset)
    }
}

private struct SessionLayout {
    let session: SessionEvent
    var columnIndex: Int
    var columnCount: Int
    var leading: CGFloat
    var width: CGFloat
}
