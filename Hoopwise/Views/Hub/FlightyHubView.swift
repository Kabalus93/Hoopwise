import SwiftUI
import Combine
import Charts

// MARK: - Flighty-Inspired Hub View
/// A command center for managing all coaching resources with Flighty's calm, confident aesthetic
struct FlightyHubView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentTime = Date()
    @State private var showingRevenueHistory = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed Properties
    
    /// Currency setting from app settings
    private var currency: CurrencyType {
        dataManager.appSettings.currency
    }
    
    /// This month's coach revenue. Source of truth: `coachRevenue(in:)` —
    /// the same accessor the revenue history view uses.
    private var monthlyEarnings: Double {
        dataManager.currentMonthCoachRevenue
    }

    /// Number of revenue events recorded this month (bundle purchases +
    /// PAYG attendances). Matches the count surfaced in the revenue view.
    private var newContractsThisMonth: Int {
        dataManager.currentMonthRevenueEvents.count
    }
    
    private var activeContracts: Int {
        dataManager.contracts.filter { $0.status == .active }.count
    }
    
    
    private var upcomingSessions: Int {
        dataManager.sessionEvents.filter { $0.isUpcoming }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header with time
                    headerSection
                    
                    // Revenue Dashboard Card
                    revenueDashboard
                        .padding(.horizontal, 16)
                    
                    // Main Navigation Grid
                    navigationGrid
                        .padding(.horizontal, 16)
                    
                    Spacer(minLength: 100)
                }
                .padding(.top, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "控制中心" : "COMMAND CENTER")
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(Color.accentColor)

                Text(LocalizationManager.shared.currentLanguage == .chinese ? "中心" : "Hub")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    themeManager.toggle()
                }
            } label: {
                Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.regular)
            .tint(.secondary)
            .sensoryFeedback(.impact(weight: .light), trigger: themeManager.isDarkMode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
    
    // MARK: - Revenue Dashboard
    private var revenueDashboard: some View {
        Button {
            showingRevenueHistory = true
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                        Text(Date().formatted(.dateTime.month(.wide).year()).uppercased())
                            .font(.caption2.weight(.bold))
                            .monospaced()
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(monthlyEarnings, format: .currency(code: currency.currencyCode))
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(newContractsThisMonth)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText(value: Double(newContractsThisMonth)))
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "事件" : "EVENTS")
                        .font(.caption2.weight(.bold))
                        .monospaced()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 12))
            }
            .padding(18)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .sensoryFeedback(.selection, trigger: showingRevenueHistory)
        .sheet(isPresented: $showingRevenueHistory) {
            MonthlyRevenueHistoryView()
        }
    }
    
    // MARK: - Navigation Grid
    private var navigationGrid: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 10) {
            NavigationLink(destination: FlightyLeagueView()) {
                hubNavCardWide(
                    icon: "trophy.fill",
                    title: isChinese ? "联赛" : "League",
                    subtitle: isChinese ? "比赛与排名" : "Games & standings"
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                NavigationLink(destination: DrillsLibraryView()) {
                    hubNavCard(
                        icon: "sportscourt.fill",
                        title: isChinese ? "训练" : "Coach",
                        subtitle: isChinese ? "\(dataManager.drills.count) 个训练" : "\(dataManager.drills.count) drills"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(destination: OrganizationView()) {
                    hubNavCard(
                        icon: "building.2.fill",
                        title: isChinese ? "组织" : "Organization",
                        subtitle: organizationSubtitle(isChinese: isChinese)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    /// Organization subtitle showing staff count
    private func organizationSubtitle(isChinese: Bool) -> String {
        return isChinese ? "\(dataManager.staffCoaches.count) 名员工" : "\(dataManager.staffCoaches.count) staff"
    }
    
private func hubNavCardWide(icon: String, title: String, subtitle: String, badge: String? = nil) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let badge = badge {
                Text(badge)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red, in: .rect(cornerRadius: 10))
            }

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func hubNavCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    
}


// MARK: - Monthly Revenue History View
/// Coach-pocket revenue. Pinpoints a single month at a time with prev/next
/// navigation so the coach can scrub back through history. Each row is a
/// discrete event (bundle purchase or PAYG attendance); group contracts are
/// excluded by design.
struct MonthlyRevenueHistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStudentId: UUID?
    @State private var presentedContract: Contract?
    @State private var showingReclassify = false
    @State private var focusedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    private var currency: CurrencyType { dataManager.appSettings.currency }
    private var currencyCode: String { currency.currencyCode }

    private var thisMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var isFocusedOnCurrentMonth: Bool {
        Calendar.current.isDate(focusedMonth, equalTo: thisMonth, toGranularity: .month)
    }

    private var focusedEvents: [SwiftDataManager.RevenueEvent] {
        dataManager.revenueEvents(in: focusedMonth)
    }

    private var focusedTotal: Double {
        dataManager.coachRevenue(in: focusedMonth)
    }

    private var activePrivateContracts: [Contract] {
        dataManager.contracts.filter { $0.kind == .privatePayPerSession || $0.kind == .privateBundle }
    }

    // MARK: - Financial breakdown / forecast

    private struct MonthBreakdown {
        let bundleTotal: Double
        let bundleCount: Int
        let paygTotal: Double
        let paygCount: Int
        var total: Double { bundleTotal + paygTotal }
    }

    private var breakdown: MonthBreakdown {
        let events = focusedEvents
        let bundles = events.filter { $0.kind == .bundlePurchase }
        let paygs = events.filter { $0.kind == .paygAttendance }
        return MonthBreakdown(
            bundleTotal: bundles.reduce(0) { $0 + $1.amount },
            bundleCount: bundles.count,
            paygTotal: paygs.reduce(0) { $0 + $1.amount },
            paygCount: paygs.count
        )
    }

    private var previousMonthDate: Date { previousMonth(focusedMonth) }
    private var previousMonthTotal: Double { dataManager.coachRevenue(in: previousMonthDate) }
    private var monthOverMonthDelta: Double { focusedTotal - previousMonthTotal }
    /// Returns nil when prior month is zero (percent change is undefined).
    private var monthOverMonthPercent: Double? {
        previousMonthTotal > 0
            ? (focusedTotal - previousMonthTotal) / previousMonthTotal * 100
            : nil
    }

    /// Linear month-end projection from MTD pace. Only meaningful while the
    /// month is in progress, so we return nil for past months.
    private var projectedMonthTotal: Double? {
        guard isFocusedOnCurrentMonth else { return nil }
        let cal = Calendar.current
        let now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        guard dayOfMonth > 0,
              let range = cal.range(of: .day, in: .month, for: now) else { return nil }
        let projection = focusedTotal * Double(range.count) / Double(dayOfMonth)
        // Don't project below what's already booked.
        return max(projection, focusedTotal)
    }

    /// 6 months oldest-first for left-to-right charting.
    private var trendHistory: [(month: Date, amount: Double)] {
        Array(dataManager.coachRevenueHistory(months: 6).reversed())
    }

    private var trendAverage: Double {
        let totals = trendHistory.map(\.amount)
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Double(totals.count)
    }

    private struct StudentRevenueSlice: Identifiable {
        let id: UUID
        let student: Student?
        let amount: Double
        let bundleCount: Int
        let paygCount: Int
    }

    /// Bundles with sessions still on the clock, surfaced regardless of which
    /// month is in focus — coaches need to see redemption progress at a glance.
    /// Sorted by remaining sessions ascending so near-empty bundles bubble up.
    private var activeBundles: [Contract] {
        dataManager.contracts
            .filter { $0.kind == .privateBundle }
            .filter { ($0.bundleRedemptionsRemaining ?? 0) > 0 }
            .sorted { ($0.bundleRedemptionsRemaining ?? 0) < ($1.bundleRedemptionsRemaining ?? 0) }
    }

    private var studentSlices: [StudentRevenueSlice] {
        let grouped = Dictionary(grouping: focusedEvents, by: { $0.studentId })
        return grouped.map { (sid, events) -> StudentRevenueSlice in
            StudentRevenueSlice(
                id: sid,
                student: dataManager.students.first(where: { $0.id == sid }),
                amount: events.reduce(0) { $0 + $1.amount },
                bundleCount: events.filter { $0.kind == .bundlePurchase }.count,
                paygCount: events.filter { $0.kind == .paygAttendance }.count
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if breakdown.total > 0 {
                    breakdownSection
                }
                if !activeBundles.isEmpty {
                    activeBundlesSection
                }
                trendSection
                if !studentSlices.isEmpty {
                    topStudentsSection
                }
                if focusedEvents.isEmpty {
                    emptyMonthSection
                } else {
                    eventsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Revenue")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    monthMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: studentSheetBinding) { box in
                NavigationStack {
                    if let s = dataManager.students.first(where: { $0.id == box.id }) {
                        StudentDetailView(student: s)
                    }
                }
            }
            .sheet(item: $presentedContract) { contract in
                PrivateClientDetailSheet(contract: contract)
            }
            .sheet(isPresented: $showingReclassify) {
                ReclassifyContractsSheet()
            }
        }
    }

    // MARK: - Header summary with prev/next month nav

    private var summarySection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)

                    VStack(spacing: 2) {
                        Text(monthLabel(focusedMonth))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                        Text(isFocusedOnCurrentMonth ? "This month"
                             : Calendar.current.isDate(focusedMonth,
                                                       equalTo: previousMonth(thisMonth),
                                                       toGranularity: .month)
                                ? "Last month"
                                : focusedMonth.formatted(.dateTime.year()))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .disabled(isFocusedOnCurrentMonth)
                }

                VStack(spacing: 6) {
                    Text(focusedTotal, format: .currency(code: currencyCode))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    let count = focusedEvents.count
                    Text(count == 0
                         ? "No revenue this month"
                         : "^[\(count) revenue event](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                comparisonChip

                if let projected = projectedMonthTotal, projected > focusedTotal {
                    projectionLine(projected: projected)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Δ vs the previous calendar month. Color-coded; gracefully degrades when
    /// the prior month was zero (no percent, just absolute) or both were zero.
    @ViewBuilder
    private var comparisonChip: some View {
        let delta = monthOverMonthDelta
        let prevLabel = monthShort(previousMonthDate)

        if focusedTotal == 0 && previousMonthTotal == 0 {
            HStack(spacing: 6) {
                Image(systemName: "minus")
                    .font(.caption2.weight(.bold))
                Text("No activity vs \(prevLabel)")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
        } else {
            let positive = delta >= 0
            let tint: Color = positive ? .green : .red
            HStack(spacing: 6) {
                Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.bold))
                if let pct = monthOverMonthPercent {
                    Text("\(positive ? "+" : "")\(Int(pct.rounded()))%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                Text(abs(delta), format: .currency(code: currencyCode))
                    .font(.caption.monospacedDigit())
                Text("vs \(prevLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
        }
    }

    private func projectionLine(projected: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Projected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(projected, format: .currency(code: currencyCode))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text("by month-end")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Bundle vs PAYG breakdown

    private var breakdownSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Stacked share bar
                GeometryReader { geo in
                    let total = max(breakdown.total, 1)
                    let bundleW = geo.size.width * (breakdown.bundleTotal / total)
                    let paygW = geo.size.width * (breakdown.paygTotal / total)
                    HStack(spacing: 2) {
                        if breakdown.bundleTotal > 0 {
                            Capsule().fill(Color.accentColor).frame(width: max(bundleW, 4))
                        }
                        if breakdown.paygTotal > 0 {
                            Capsule().fill(Color.green).frame(width: max(paygW, 4))
                        }
                    }
                }
                .frame(height: 10)

                breakdownRow(
                    color: .accentColor,
                    icon: "shippingbox.fill",
                    title: "Bundles",
                    count: breakdown.bundleCount,
                    amount: breakdown.bundleTotal
                )
                breakdownRow(
                    color: .green,
                    icon: "person.fill.checkmark",
                    title: "Pay per session",
                    count: breakdown.paygCount,
                    amount: breakdown.paygTotal
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Breakdown")
        } footer: {
            Text("Bundles are recognized in full when purchased; pay-per-session revenue lands each time a student attends a private session.")
                .font(.caption2)
        }
    }

    private func breakdownRow(color: Color, icon: String, title: String, count: Int, amount: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(count == 0
                     ? "No events"
                     : "^[\(count) event](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(amount, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                if breakdown.total > 0 {
                    Text("\(Int((amount / breakdown.total * 100).rounded()))% of total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Active bundles (redemption progress)

    private var activeBundlesSection: some View {
        Section {
            ForEach(activeBundles) { contract in
                activeBundleRow(contract)
            }
        } header: {
            HStack {
                Text("Active bundles")
                Spacer()
                Text("^[\(activeBundles.count) bundle](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        } footer: {
            Text("Each bundle is paid for up-front. Sessions tick down as the student attends.")
                .font(.caption2)
        }
    }

    private func activeBundleRow(_ contract: Contract) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        let used = contract.bundleSessionIds.count
        let total = max(contract.bundleSize, 1)
        let remaining = max(0, contract.bundleSize - used)
        let progress = Double(used) / Double(total)
        let lowStock = remaining <= 2
        let barColor: Color = lowStock ? .orange : .accentColor

        return Button {
            presentedContract = contract
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let s = student {
                        StudentAvatarView(student: s, size: 36)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student?.name ?? "—")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(contract.bundleSize)-pack · purchased \(contract.effectiveBundlePurchaseDate.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(used) / \(contract.bundleSize)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(remaining) left")
                            .font(.caption2)
                            .foregroundStyle(lowStock ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                            .fontWeight(lowStock ? .semibold : .regular)
                    }
                }

                ProgressView(value: progress)
                    .tint(barColor)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 6-month trend

    private var trendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text("6-month trend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Avg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(trendAverage, format: .currency(code: currencyCode))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                Chart {
                    ForEach(trendHistory, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.month, unit: .month),
                            y: .value("Revenue", item.amount)
                        )
                        .foregroundStyle(
                            Calendar.current.isDate(item.month, equalTo: focusedMonth, toGranularity: .month)
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.3)
                        )
                        .cornerRadius(4)
                    }
                    if trendAverage > 0 {
                        RuleMark(y: .value("Avg", trendAverage))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 140)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Top students this month

    private var topStudentsSection: some View {
        Section {
            ForEach(studentSlices.prefix(5)) { slice in
                topStudentRow(slice)
            }
        } header: {
            Text("Top students this month")
        }
    }

    private func topStudentRow(_ slice: StudentRevenueSlice) -> some View {
        Button {
            selectedStudentId = slice.id
        } label: {
            HStack(spacing: 12) {
                if let s = slice.student {
                    StudentAvatarView(student: s, size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.student?.name ?? "—")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(studentBreakdownLine(slice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(slice.amount, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func studentBreakdownLine(_ slice: StudentRevenueSlice) -> String {
        // Note: Foundation's inflect macro only resolves inside a
        // LocalizedStringKey context. Building the string by interpolation
        // and joining loses it, so we hand-pluralize here.
        var parts: [String] = []
        if slice.bundleCount > 0 {
            parts.append("\(slice.bundleCount) bundle\(slice.bundleCount == 1 ? "" : "s")")
        }
        if slice.paygCount > 0 {
            parts.append("\(slice.paygCount) attendance\(slice.paygCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func monthShort(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    /// Quick-jump menu in the top-leading slot. Lists the last 12 months with
    /// each month's total inline so the coach can scan and pick.
    private var monthMenu: some View {
        Menu {
            Section("Jump to month") {
                ForEach(dataManager.recentMonths(12), id: \.self) { month in
                    Button {
                        withAnimation { focusedMonth = month }
                    } label: {
                        HStack {
                            Text(monthLabel(month))
                            Spacer()
                            Text(dataManager.coachRevenue(in: month),
                                 format: .currency(code: currencyCode))
                                .monospacedDigit()
                        }
                    }
                }
            }
            Divider()
            Button {
                showingReclassify = true
            } label: {
                Label("Reclassify contracts…", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            Label("Pick month", systemImage: "calendar")
                .labelStyle(.iconOnly)
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private var emptyMonthSection: some View {
        if isFocusedOnCurrentMonth && !activePrivateContracts.isEmpty {
            Section {
                ForEach(activePrivateContracts) { contract in
                    contractStatusRow(contract)
                }
            } header: {
                Text("Active private contracts")
            } footer: {
                Text("Bundles count their full amount in the month they're purchased. Pay-per-session contracts add the per-session price each time the student attends a private session.")
                    .font(.caption2)
            }
        } else {
            Section {
                ContentUnavailableView(
                    "No revenue",
                    systemImage: "yensign.circle",
                    description: Text("Nothing was billed in \(monthLabel(focusedMonth)).")
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    private var eventsSection: some View {
        Section {
            ForEach(focusedEvents) { event in
                revenueRow(event)
            }
        } header: {
            HStack {
                Text(monthLabel(focusedMonth))
                Spacer()
                Text(focusedTotal, format: .currency(code: currencyCode))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func contractStatusRow(_ contract: Contract) -> some View {
        let student = dataManager.students.first(where: { $0.id == contract.studentId })
        Button {
            selectedStudentId = contract.studentId
        } label: {
            HStack(spacing: 12) {
                if let s = student { StudentAvatarView(student: s, size: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.name ?? "—")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(privateStatusLine(for: contract))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func privateStatusLine(for contract: Contract) -> String {
        let symbol = currency.symbol
        switch contract.kind {
        case .privateBundle:
            let used = contract.bundleSessionIds.count
            let left = max(0, contract.bundleSize - used)
            let purchase = contract.effectiveBundlePurchaseDate
                .formatted(.dateTime.month(.abbreviated).year())
            return "Bundle · \(used)/\(contract.bundleSize) used · \(left) left · purchased \(purchase)"
        case .privatePayPerSession:
            return "Pay per session · \(symbol)\(Int(contract.pricePerSession))/attendance"
        case .group:
            return ""
        }
    }

    private func revenueRow(_ event: SwiftDataManager.RevenueEvent) -> some View {
        let student = dataManager.students.first { $0.id == event.studentId }
        let contract = dataManager.contracts.first { $0.id == event.contractId }
        return Button {
            // For bundle/PAYG events, prefer the focused per-contract sheet so
            // the coach can review past sessions and schedule new ones.
            if let c = contract,
               c.kind == .privateBundle || c.kind == .privatePayPerSession {
                presentedContract = c
            } else {
                selectedStudentId = event.studentId
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: event.kind == .bundlePurchase ? "shippingbox.fill" : "person.fill.checkmark")
                    .font(.title3)
                    .foregroundStyle(event.kind == .bundlePurchase ? Color.accentColor : Color.green)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.name ?? "—")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(secondaryLine(for: event, contract: contract))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.amount, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                    Text(event.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func secondaryLine(for event: SwiftDataManager.RevenueEvent, contract: Contract?) -> String {
        switch event.kind {
        case .bundlePurchase:
            let size = contract?.bundleSize ?? 0
            let used = contract?.bundleSessionIds.count ?? 0
            let remaining = max(0, size - used)
            return "Bundle · \(used)/\(size) used · \(remaining) left"
        case .paygAttendance:
            return "Pay per session · attended"
        }
    }

    // MARK: - Helpers

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private func previousMonth(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date
    }

    /// Don't allow scrubbing into the future.
    private func shiftMonth(by delta: Int) {
        guard let candidate = Calendar.current.date(byAdding: .month, value: delta, to: focusedMonth) else { return }
        if candidate > thisMonth { return }
        withAnimation { focusedMonth = candidate }
    }

    // MARK: - Sheet plumbing

    private struct StudentBox: Identifiable { let id: UUID }
    private var studentSheetBinding: Binding<StudentBox?> {
        Binding(
            get: { selectedStudentId.map(StudentBox.init) },
            set: { selectedStudentId = $0?.id }
        )
    }
}

// MARK: - Private Client Detail Sheet
/// Focused view for a single private contract — bundle progress (or PAYG
/// status), the list of sessions this student has attended on the contract,
/// and an inline scheduler that creates a real SessionEvent on save.
struct PrivateClientDetailSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    let contract: Contract
    @State private var showingScheduler = false

    private var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }

    private var currency: CurrencyType { dataManager.appSettings.currency }
    private var currencyCode: String { currency.currencyCode }

    /// Sessions this student has actually attended on a private program.
    /// For bundles we strictly follow `bundleSessionIds`; for PAYG we look at
    /// any private SessionEvent the student showed up to.
    private var attendedSessions: [SessionEvent] {
        let all = dataManager.sessionEvents
        switch contract.kind {
        case .privateBundle:
            let ids = Set(contract.bundleSessionIds)
            return all.filter { ids.contains($0.id) }
                      .sorted { $0.date > $1.date }
        case .privatePayPerSession:
            return all.filter { event in
                event.actualAttendeeIds.contains(contract.studentId)
                    && isPrivate(event)
            }
            .sorted { $0.date > $1.date }
        case .group:
            return []
        }
    }

    /// Upcoming scheduled sessions for this student on a private program
    /// (created here or elsewhere) that haven't happened yet.
    private var upcomingSessions: [SessionEvent] {
        let now = Date()
        return dataManager.sessionEvents.filter { event in
            event.date >= now
                && event.attendeeIds.contains(contract.studentId)
                && isPrivate(event)
        }
        .sorted { $0.date < $1.date }
    }

    /// Past sessions where the student is on the roster but attendance was
    /// never marked. These don't count toward bundle redemption / PAYG
    /// revenue yet — surface them so the coach can fix the record.
    private var pastUnmarkedSessions: [SessionEvent] {
        let now = Date()
        let attendedIds = Set(attendedSessions.map(\.id))
        return dataManager.sessionEvents.filter { event in
            event.date < now
                && event.attendeeIds.contains(contract.studentId)
                && !event.actualAttendeeIds.contains(contract.studentId)
                && !attendedIds.contains(event.id)
                && isPrivate(event)
        }
        .sorted { $0.date > $1.date }
    }

    private func isPrivate(_ event: SessionEvent) -> Bool {
        // Mirror SwiftDataManager.eventIsPrivate: a session is private when
        // it's tied to a private-type program, OR when it has no program at
        // all (newer 1:1 sessions created from the scheduler are program-less
        // by design — see SchedulePrivateSessionSheet).
        if let pid = event.programId,
           let program = dataManager.programs.first(where: { $0.id == pid }) {
            return program.programType == .privateSessions
        }
        return event.programId == nil
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if !upcomingSessions.isEmpty {
                    upcomingSection
                }
                if !pastUnmarkedSessions.isEmpty {
                    pastUnmarkedSection
                }
                attendedSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(student?.name ?? "Client")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingScheduler = true
                    } label: {
                        Label("Schedule", systemImage: "calendar.badge.plus")
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingScheduler) {
                if let s = student {
                    SchedulePrivateSessionSheet(student: s, contract: contract)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                if let s = student {
                    StudentAvatarView(student: s, size: 64)
                }

                VStack(spacing: 4) {
                    Text(student?.name ?? "—")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if contract.kind == .privateBundle {
                    bundleProgressBlock
                } else if contract.kind == .privatePayPerSession {
                    paygBlock
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var kindLabel: String {
        switch contract.kind {
        case .privateBundle: return "Bundle"
        case .privatePayPerSession: return "Pay per session"
        case .group: return "Group"
        }
    }

    private var bundleProgressBlock: some View {
        let used = contract.bundleSessionIds.count
        let total = max(contract.bundleSize, 1)
        let remaining = max(0, contract.bundleSize - used)
        let progress = Double(used) / Double(total)
        let lowStock = remaining <= 2

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(used) / \(contract.bundleSize)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("sessions used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(lowStock ? .orange : .accentColor)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                Label("\(remaining) left", systemImage: "calendar")
                    .foregroundStyle(lowStock ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                Text("·").foregroundStyle(.tertiary)
                Text(contract.bundleAmount, format: .currency(code: currencyCode))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("·").foregroundStyle(.tertiary)
                Text("Purchased \(contract.effectiveBundlePurchaseDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
        }
    }

    private var paygBlock: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(contract.pricePerSession, format: .currency(code: currencyCode))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("per session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 32)
            VStack(spacing: 2) {
                Text("\(attendedSessions.count)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("attended total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        Section {
            ForEach(upcomingSessions) { event in
                NavigationLink(destination: FlightySessionPageView(session: event, accessMode: .architect)) {
                    sessionRow(event, isUpcoming: true)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Upcoming")
        }
    }

    @ViewBuilder
    private var pastUnmarkedSection: some View {
        Section {
            ForEach(pastUnmarkedSessions) { event in
                NavigationLink(destination: FlightySessionPageView(session: event, accessMode: .architect)) {
                    sessionRow(event, isUpcoming: false, unmarked: true)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Past · attendance not marked")
        } footer: {
            Text("These sessions don't count toward bundle redemption or pay-per-session revenue until the student is marked attended. Tap a row to fix.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var attendedSection: some View {
        Section {
            if attendedSessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "calendar.badge.clock",
                    description: Text("Tap Schedule to add the first private session.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(attendedSessions) { event in
                    NavigationLink(destination: FlightySessionPageView(session: event, accessMode: .architect)) {
                        sessionRow(event, isUpcoming: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(contract.kind == .privateBundle ? "Bundle history" : "Attended sessions")
        }
    }

    private func sessionRow(_ event: SessionEvent, isUpcoming: Bool, unmarked: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(event.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(Calendar.current.component(.day, from: event.date))")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Private session" : event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.startTime.formatted(date: .omitted, time: .shortened))
                    if let location = event.location, !location.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(location).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isUpcoming {
                Text("Scheduled")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            } else if unmarked {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Schedule Private Session Sheet
/// Minimal scheduling form: pick date/time/duration, attach optional location,
/// and create a SessionEvent attributed to one of the coach's private programs
/// so the new session counts toward bundle redemption / PAYG revenue.
struct SchedulePrivateSessionSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    let student: Student
    let contract: Contract

    @State private var date: Date
    @State private var startTime: Date
    @State private var duration: Int  // minutes
    @State private var selectedLocationId: UUID?
    @State private var customLocation: String = ""
    @State private var title: String
    @State private var notes: String = ""
    @State private var markAttended: Bool

    init(student: Student, contract: Contract) {
        self.student = student
        self.contract = contract

        let cal = Calendar.current
        // Default: tomorrow at 6:30 PM, 60 min duration.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let defaultDate = cal.startOfDay(for: tomorrow)
        let defaultStart = cal.date(bySettingHour: 18, minute: 30, second: 0, of: defaultDate) ?? defaultDate

        _date = State(initialValue: defaultDate)
        _startTime = State(initialValue: defaultStart)
        _duration = State(initialValue: 60)
        _title = State(initialValue: "Private — \(student.name)")
        // Future date by default → not attended yet. Coach can flip to
        // pre-mark if they want; past dates flip it on automatically below.
        _markAttended = State(initialValue: false)
    }

    private var isPastDate: Bool { combinedStart < Date() }

    private var resolvedLocation: String? {
        if let id = selectedLocationId,
           let loc = dataManager.locations.first(where: { $0.id == id }) {
            return loc.name
        }
        let trimmed = customLocation.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var endTime: Date {
        Calendar.current.date(byAdding: .minute, value: duration, to: combinedStart) ?? combinedStart
    }

    private var combinedStart: Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: startTime)
        return cal.date(bySettingHour: hm.hour ?? 18, minute: hm.minute ?? 30, second: 0, of: date) ?? date
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    Stepper(value: $duration, in: 15...240, step: 15) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(duration) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Location") {
                    if !dataManager.locations.isEmpty {
                        Picker("Saved location", selection: $selectedLocationId) {
                            Text("None").tag(UUID?.none)
                            ForEach(dataManager.locations) { loc in
                                Text(loc.name).tag(UUID?.some(loc.id))
                            }
                        }
                    }
                    TextField("Or type a place", text: $customLocation)
                }

                Section {
                    Toggle(isOn: $markAttended) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mark as attended")
                            Text(isPastDate
                                 ? "Counts toward bundle redemption / revenue right away."
                                 : "Pre-marks the session — leave off if you'd rather record attendance later.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Attendance")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Schedule Session")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createSession() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            // Flip the toggle on automatically the first moment the date
            // resolves to the past so retroactive entries "just work."
            .onChange(of: isPastDate) { _, nowPast in
                if nowPast { markAttended = true }
            }
            .onAppear {
                if isPastDate { markAttended = true }
            }
        }
    }

    private func createSession() {
        guard canSave else { return }

        // Private 1:1 sessions are intentionally program-less. They're
        // identified as private downstream by the attendee having an active
        // private contract — see SwiftDataManager.eventIsPrivate.
        let event = SessionEvent(
            programId: nil,
            sessionType: .training,
            title: title.trimmingCharacters(in: .whitespaces),
            date: combinedStart,
            startTime: combinedStart,
            endTime: endTime,
            location: resolvedLocation,
            attendeeIds: [student.id],
            actualAttendeeIds: markAttended ? [student.id] : [],
            notes: notes.isEmpty ? nil : notes,
            createdByCoachId: dataManager.loggedInCoachId
        )

        dataManager.addSessionEvent(event)

        // If pre-marking attendance, redeem a bundle slot right away so the
        // counter ticks down without a second trip through the attendance UI.
        if markAttended {
            dataManager.redeemPrivateAttendance(sessionId: event.id, studentId: student.id)
        }

        HapticFeedback.notification(.success)
        dismiss()
    }
}

// MARK: - Private Clients List
/// Drilldown from the Programs view's "Private clients" tile. Lists every
/// active private contract (bundle or PAYG); rows present the same per-client
/// detail sheet used elsewhere so history and scheduling stay in one place.
struct PrivateClientsListView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var presentedContract: Contract?

    private var currency: CurrencyType { dataManager.appSettings.currency }
    private var currencyCode: String { currency.currencyCode }

    private var activeContracts: [Contract] {
        dataManager.contracts
            .filter { ($0.kind == .privateBundle || $0.kind == .privatePayPerSession)
                       && $0.status == .active }
            .sorted { lhs, rhs in
                let lname = dataManager.students.first(where: { $0.id == lhs.studentId })?.name ?? ""
                let rname = dataManager.students.first(where: { $0.id == rhs.studentId })?.name ?? ""
                if lname != rname { return lname < rname }
                // Bundles before PAYG for the same student
                return lhs.kind == .privateBundle && rhs.kind != .privateBundle
            }
    }

    var body: some View {
        List {
            if activeContracts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No private clients",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Create a private bundle or pay-per-session contract on a student to see them here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(activeContracts) { contract in
                        Button {
                            presentedContract = contract
                        } label: {
                            row(for: contract)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Sessions scheduled from a client's detail page are program-less. They count toward bundle redemption and pay-per-session revenue automatically.")
                        .font(.caption2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Private clients")
        .navigationBarTitleDisplayModeCompat(.inline)
        .sheet(item: $presentedContract) { contract in
            PrivateClientDetailSheet(contract: contract)
        }
    }

    @ViewBuilder
    private func row(for contract: Contract) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        HStack(spacing: 12) {
            if let s = student {
                StudentAvatarView(student: s, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(student?.name ?? "—")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(secondaryLine(for: contract))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing(for: contract)
        }
        .padding(.vertical, 2)
    }

    private func secondaryLine(for contract: Contract) -> String {
        switch contract.kind {
        case .privateBundle:
            let used = contract.bundleSessionIds.count
            let total = contract.bundleSize
            let remaining = max(0, total - used)
            return "Bundle · \(used)/\(total) used · \(remaining) left"
        case .privatePayPerSession:
            let attended = contract.bundleSessionIds.count  // legacy field also tracks PAYG attendances elsewhere; safe fallback
            _ = attended
            return "Pay per session"
        case .group:
            return ""
        }
    }

    @ViewBuilder
    private func trailing(for contract: Contract) -> some View {
        switch contract.kind {
        case .privateBundle:
            let remaining = contract.bundleRedemptionsRemaining ?? 0
            let lowStock = remaining <= 2
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(contract.bundleSessionIds.count)/\(contract.bundleSize)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("\(remaining) left")
                    .font(.caption2)
                    .foregroundStyle(lowStock ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .fontWeight(lowStock ? .semibold : .regular)
            }
        case .privatePayPerSession:
            VStack(alignment: .trailing, spacing: 1) {
                Text(contract.pricePerSession, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("/session")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .group:
            EmptyView()
        }
    }
}

// MARK: - Reclassify Contracts Sheet
/// One-shot maintenance tool for fixing students who were mistakenly given a
/// private bundle / pay-per-session contract. The coach picks the actual
/// private clients to keep; everyone else's private contract is flipped to
/// `.group` (and bundle fields wiped, since group contracts don't use them).
struct ReclassifyContractsSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var keeperIds: Set<UUID> = []
    @State private var showingPicker = false
    @State private var showingConfirmation = false

    /// Students who currently have at least one private-kind contract.
    /// They're the only candidates that could be mis-classified.
    private var privateClientCandidates: [Student] {
        let ids = Set(dataManager.contracts
            .filter { $0.kind == .privateBundle || $0.kind == .privatePayPerSession }
            .map(\.studentId))
        return dataManager.students
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Contracts that will be flipped to `.group` once Apply is tapped.
    private var contractsToFlip: [Contract] {
        dataManager.contracts.filter { contract in
            (contract.kind == .privateBundle || contract.kind == .privatePayPerSession)
                && !keeperIds.contains(contract.studentId)
        }
        .sorted { lhs, rhs in
            let lname = dataManager.students.first(where: { $0.id == lhs.studentId })?.name ?? ""
            let rname = dataManager.students.first(where: { $0.id == rhs.studentId })?.name ?? ""
            return lname.localizedStandardCompare(rname) == .orderedAscending
        }
    }

    private var affectedStudentCount: Int {
        Set(contractsToFlip.map(\.studentId)).count
    }

    private var keeperStudents: [Student] {
        privateClientCandidates.filter { keeperIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                keepersSection
                if !contractsToFlip.isEmpty {
                    flipSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reclassify Contracts")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { showingConfirmation = true }
                        .fontWeight(.semibold)
                        .disabled(contractsToFlip.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ReclassifyKeeperPicker(
                    candidates: privateClientCandidates,
                    selectedIds: $keeperIds
                )
            }
            .alert("Reclassify \(contractsToFlip.count) contracts?",
                   isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Apply", role: .destructive) { applyChanges() }
            } message: {
                Text("\(affectedStudentCount) students will be moved to group billing. Bundle counts and per-session prices on those contracts will be cleared. This isn't reversible from inside the app.")
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                summaryStat(value: "\(privateClientCandidates.count)",
                            label: "Currently private")
                Divider().frame(height: 32)
                summaryStat(value: "\(keeperIds.count)",
                            label: "Keeping",
                            color: .green)
                Divider().frame(height: 32)
                summaryStat(value: "\(contractsToFlip.count)",
                            label: "Will flip",
                            color: contractsToFlip.isEmpty ? .secondary : .orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } footer: {
            Text("Pick the students who actually are private clients. Every other private/bundle contract becomes a group contract when you tap Apply.")
                .font(.caption2)
        }
    }

    private func summaryStat(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var keepersSection: some View {
        Section {
            if keeperStudents.isEmpty {
                Button {
                    showingPicker = true
                } label: {
                    Label("Pick private clients to keep", systemImage: "person.crop.circle.badge.plus")
                }
            } else {
                ForEach(keeperStudents) { student in
                    HStack(spacing: 12) {
                        StudentAvatarView(student: student, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.name)
                                .foregroundStyle(.primary)
                            if let cn = student.chineseName, !cn.isEmpty {
                                Text(cn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            keeperIds.remove(student.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    showingPicker = true
                } label: {
                    Label("Edit selection", systemImage: "pencil")
                }
            }
        } header: {
            Text("Keep as private")
        }
    }

    private var flipSection: some View {
        Section {
            ForEach(contractsToFlip) { contract in
                contractFlipRow(contract)
            }
        } header: {
            HStack {
                Text("Will become group")
                Spacer()
                Text("\(contractsToFlip.count) contract\(contractsToFlip.count == 1 ? "" : "s") · \(affectedStudentCount) student\(affectedStudentCount == 1 ? "" : "s")")
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("`bundleSize`, `bundleSessionIds`, and `pricePerSession` on these contracts will be cleared.")
                .font(.caption2)
        }
    }

    private func contractFlipRow(_ contract: Contract) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        return HStack(spacing: 12) {
            if let s = student {
                StudentAvatarView(student: s, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(student?.name ?? "—")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(currentKindLabel(contract))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Group")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func currentKindLabel(_ contract: Contract) -> String {
        switch contract.kind {
        case .privateBundle:
            return "Bundle · \(contract.bundleSessionIds.count)/\(contract.bundleSize)"
        case .privatePayPerSession:
            return "Pay per session"
        case .group:
            return "Group"
        }
    }

    // MARK: - Apply

    private func applyChanges() {
        for contract in contractsToFlip {
            var updated = contract
            updated.kind = .group
            updated.bundleSize = 0
            updated.bundleSessionIds = []
            updated.pricePerSession = 0
            updated.bundlePurchaseDate = nil
            updated.updatedAt = Date()
            dataManager.updateContract(updated)
        }
        HapticFeedback.notification(.success)
        dismiss()
    }
}

// MARK: - Reclassify Keeper Picker
/// Multi-select searchable list — used by ReclassifyContractsSheet to choose
/// the students who should remain private. Searches both English and Chinese
/// names so romanization variations don't trip the coach up.
struct ReclassifyKeeperPicker: View {
    let candidates: [Student]
    @Binding var selectedIds: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Student] {
        guard !search.isEmpty else { return candidates }
        let q = search.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return candidates.filter { s in
            let name = s.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let chinese = (s.chineseName ?? "").folding(options: [.caseInsensitive], locale: .current)
            return name.contains(q) || chinese.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { student in
                    Button {
                        if selectedIds.contains(student.id) {
                            selectedIds.remove(student.id)
                        } else {
                            selectedIds.insert(student.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            StudentAvatarView(student: student, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(student.name)
                                    .foregroundStyle(.primary)
                                if let cn = student.chineseName, !cn.isEmpty {
                                    Text(cn)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedIds.contains(student.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search clients")
            .navigationTitle(selectedIds.isEmpty
                             ? "Select clients"
                             : "\(selectedIds.count) selected")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Contract Detail Sheet
struct ContractDetailSheet: View {
    let contract: Contract
    let currency: CurrencyType
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    private var student: Student? {
        dataManager.students.first { $0.id == contract.studentId }
    }
    
    private var enrollingCoach: Coach? {
        if contract.createdByCoachId == dataManager.coach.id {
            return dataManager.coach
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Student Info
                    studentInfoCard
                    
                    // Contract Details
                    contractDetailsCard
                    
                    // Enrolling Coach Info
                    enrollingCoachCard
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Contract Details")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accentColor)
                }
            }
        }
    }
    
    // MARK: - Student Info Card
    private var studentInfoCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(student?.avatarColor.color ?? .blue).opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(student?.initials ?? "?")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(student?.avatarColor.color ?? .blue))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(student?.name ?? "Unknown Student")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let chineseName = student?.chineseName, !chineseName.isEmpty {
                        Text(chineseName)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Contract Details Card
    private var contractDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contract Information")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                detailRow(label: "Contract #", value: contract.contractLabel)
                detailRow(label: "Signed Date", value: contract.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                detailRow(label: "Total Sessions", value: "\(contract.totalSessions)")
                detailRow(label: "Price per Session", value: contract.pricePerSession.formatted(.currency(code: currency.currencyCode)))
                
                Divider()
                
                HStack {
                    Text("Amount Paid")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(contract.amountPaid, format: .currency(code: currency.currencyCode))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.successColor)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Enrolling Coach Card
    private var enrollingCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enrolled By")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(enrollingCoach?.initials ?? "?")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(enrollingCoach?.name ?? "Unknown Coach")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Coach")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview
#Preview {
    FlightyHubView()
        .environmentObject(DataManager.shared)
}
