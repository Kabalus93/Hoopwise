import SwiftUI
import SwiftData
import Combine
import Charts

// MARK: - Flighty-Inspired Hub View
/// A command center for managing all coaching resources with Flighty's calm, confident aesthetic
struct FlightyHubView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentTime = Date()
    @State private var showingRevenueHistory = false
    /// The Coach board opens straight into the editor, full screen.
    @State private var boardOpen = false
    @State private var presentedClient: Contract?
    @Environment(\.modelContext) private var modelContext
    
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
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Full page everywhere (15 Nov 2026, Luther: on the iPad "let the hub
        // landing page be the full page rather than a side bar"); its tiles
        // push their pages.
        NavigationStack { hubColumn }
            .fullScreenCover(isPresented: $boardOpen) {
                CoachBoardScreen()
                    .environmentObject(dataManager)
            }
    }

    // THE HUB, REDESIGNED (15 November 2026, Luther: "the command center bar
    // should be more like a header that occupies the upper half … change
    // Coach to Drills … a better set of icons, bespoke to the app … the
    // private class tracker deserves to be better presented"). A court hero
    // in the session page's language carries the title and the PRIVATE
    // LESSONS tracker (this month, against last month, six months of bars,
    // bundles and sessions left); under it two groups of tiles with the
    // Hub's own glyphs (HubGlyphs.swift): LIBRARY — Plays, Drills, Lexicon —
    // and PEOPLE — Teams, Organization.
    private var hubColumn: some View {
        GeometryReader { outer in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hubHero(topInset: outer.safeAreaInsets.top)
                    navigationGrid
                        .padding(.horizontal, 16)
                    Spacer(minLength: 100)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectHidden(true, for: .top)
            .filmRoomPage()
        }
        .onReceive(timer) { _ in currentTime = Date() }
        // Revenue is a full page (15 Nov 2026, Luther: it opened in a popup).
        .navigationDestination(isPresented: $showingRevenueHistory) {
            MonthlyRevenueHistoryView(pushed: true)
        }
        // A client in the header opens their private contract card: history,
        // sessions, Schedule.
        .sheet(item: $presentedClient) { contract in
            PrivateClientDetailSheet(contract: contract)
                .environmentObject(dataManager)
        }
    }

    // MARK: - Hero

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    /// Title on the left and the theme switch on one line on a phone, the
    /// tracker under them; on a wide screen the switch top right, the title
    /// bottom left and the tracker beside it.
    private func hubHero(topInset: CGFloat) -> some View {
        let wide = horizontalSizeClass == .regular
        return Group {
            if wide {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        themeButton
                    }
                    Spacer(minLength: 24)
                    HStack(alignment: .bottom, spacing: 28) {
                        heroTitle
                        Spacer(minLength: 0)
                        privateLessonsPanel
                            .frame(maxWidth: 560)
                    }
                }
                .frame(minHeight: 300, alignment: .bottom)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        heroTitle
                        Spacer()
                        themeButton
                    }
                    privateLessonsPanel
                }
            }
        }
        .padding(.horizontal, wide ? 32 : 20)
        .padding(.top, topInset + (wide ? 20 : 12))
        .padding(.bottom, wide ? 28 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CardCourtBackground(color: Color(red: 0.08, green: 0.3, blue: 0.75), style: .fullCourt)
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isChinese ? "控制中心" : "COMMAND CENTER")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            Text(isChinese ? "中心" : "Hub")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var themeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { themeManager.toggle() }
        } label: {
            Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .sensoryFeedback(.impact(weight: .light), trigger: themeManager.isDarkMode)
        .accessibilityLabel(isChinese ? "切换外观" : "Switch appearance")
        // The Mac's film room is always dark: no switch there.
        .opacity(FilmRoom.isOn ? 0 : 1)
        .allowsHitTesting(!FilmRoom.isOn)
        .accessibilityHidden(FilmRoom.isOn)
    }

    // MARK: - Private lessons tracker

    private var privateBundles: [Contract] {
        dataManager.contracts.filter { $0.kind == .privateBundle && ($0.bundleRedemptionsRemaining ?? 0) > 0 }
    }

    /// PRIVATE LESSONS, second version (15 Nov 2026, Luther: not convinced
    /// by the month total + bars — bundle sales arrive in lumps, so the bars
    /// were mostly zero). Money is one small line; the body is the CLIENTS:
    /// each private client with an active bundle as their photo in a ring of
    /// what is left (orange at ≤ 2), nearest to renewal first.
    private var privateLessonsPanel: some View {
        let history = dataManager.coachRevenueHistory(months: 2)   // newest first
        let last = history.count > 1 ? history[1].amount : 0
        let bundles = privateBundles.sorted { ($0.bundleRedemptionsRemaining ?? 0) < ($1.bundleRedemptionsRemaining ?? 0) }
        let sessionsLeft = bundles.reduce(0) { $0 + ($1.bundleRedemptionsRemaining ?? 0) }
        let monthName = Date().formatted(.dateTime.month(.wide))
        let lastName = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.formatted(.dateTime.month(.wide)) ?? ""
        let shown = Array(bundles.prefix(5))
        return VStack(alignment: .leading, spacing: 14) {
            // The money line and the footer open Revenue; each client opens
            // their contract card.
            Button {
                showingRevenueHistory = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isChinese ? "私教课" : "PRIVATE LESSONS")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 4)
                    Text("\(monthName) \(money(monthlyEarnings)) · \(lastName) \(money(last))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hub.revenue")

            if shown.isEmpty {
                Text(isChinese ? "没有进行中的私教课包" : "No private bundles running")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(shown) { contract in
                        Button {
                            presentedClient = contract
                        } label: {
                            clientBubble(contract)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hub.client")
                    }
                    if bundles.count > shown.count {
                        Button {
                            showingRevenueHistory = true
                        } label: {
                            Text("+\(bundles.count - shown.count)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    showingRevenueHistory = true
                } label: {
                    Text(isChinese ? "\(bundles.count) 个课包 · 剩余 \(sessionsLeft) 节"
                                   : "\(bundles.count) \(bundles.count == 1 ? "bundle" : "bundles") · \(sessionsLeft) \(sessionsLeft == 1 ? "session" : "sessions") left")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .rect(cornerRadius: 20))
        .sensoryFeedback(.selection, trigger: showingRevenueHistory)
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: currency.currencyCode).precision(.fractionLength(0)))
    }

    /// A client's photo inside a ring of the bundle still to use.
    private func clientBubble(_ contract: Contract) -> some View {
        let left = contract.bundleRedemptionsRemaining ?? 0
        let size = max(1, contract.bundleSize)
        let low = left <= 2
        let student = dataManager.students.first { $0.id == contract.studentId }
        let firstName = student.map { $0.primaryDisplayName.components(separatedBy: " ").first ?? $0.primaryDisplayName } ?? "—"
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(left) / CGFloat(size))
                    .stroke(low ? Color.orange : .white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let student {
                    StudentAvatarView(student: student, size: 44)
                } else {
                    Circle().fill(.white.opacity(0.2)).frame(width: 44, height: 44)
                }
            }
            .frame(width: 52, height: 52)
            Text(firstName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 60)
            Text(isChinese ? "剩 \(left) 节" : "\(left) left")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(low ? Color.orange : .white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(student?.primaryDisplayName ?? ""), \(left) of \(size)")
    }


    // MARK: - Tiles

    private var navigationGrid: some View {
        let playCount = (try? modelContext.fetchCount(FetchDescriptor<JournalPlay>())) ?? 0
        let teams = dataManager.teams.count
        let wide = horizontalSizeClass == .regular
        let lexiconTitle = isChinese ? "术语词典" : "Lexicon"
        let lexiconCount = "\(Lexicon.shared.entryCount)"
        // The glass goes on the LINK, never inside its label: a glassEffect in
        // a NavigationLink's label swallowed every tap on iOS 26.
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(isChinese ? "资料库" : "LIBRARY")
                if wide {
                    HStack(spacing: 12) {
                        playsLink(playCount)
                        drillsLink
                        NavigationLink(destination: LexiconScreen()) {
                            hubTile(.lexicon, title: lexiconTitle, count: lexiconCount, unit: isChinese ? "个术语" : "terms")
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        .accessibilityIdentifier("hub.lexicon")
                    }
                } else {
                    HStack(spacing: 10) {
                        playsLink(playCount)
                        drillsLink
                    }
                    NavigationLink(destination: LexiconScreen()) {
                        hubWideTile(.lexicon, title: lexiconTitle,
                                    detail: isChinese ? "\(lexiconCount) 个篮球术语 · 战术、动作、规则、防守"
                                                      : "\(lexiconCount) terms · plays, actions, rules, defenses")
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .accessibilityIdentifier("hub.lexicon")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(isChinese ? "人员" : "PEOPLE")
                HStack(spacing: wide ? 12 : 10) {
                    NavigationLink(destination: TeamsScreen()) {
                        hubTile(.teams, title: isChinese ? "球队" : "Teams", count: "\(teams)",
                                unit: isChinese ? "支球队" : (teams == 1 ? "team" : "teams"))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .accessibilityIdentifier("hub.teams")

                    NavigationLink(destination: OrganizationView()) {
                        hubTile(.organization, title: isChinese ? "组织" : "Organization",
                                count: "\(dataManager.staffCoaches.count)",
                                unit: isChinese ? "名教练" : (dataManager.staffCoaches.count == 1 ? "coach" : "coaches"))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .accessibilityIdentifier("hub.organization")

                    // The Coach board takes the third slot on a wide screen.
                    if wide { boardLink(wide: true) }
                }
                if !wide { boardLink(wide: false) }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// The Coach board (17 Nov 2026, Luther): a court that keeps what is drawn
    /// until Clear, saved as a play or a drill when it is worth keeping.
    @ViewBuilder
    private func boardLink(wide: Bool) -> some View {
        let title = isChinese ? "战术板" : "Coach board"
        let detail = CoachBoardStore.load() == nil
            ? (isChinese ? "空白" : "Empty")
            : (isChinese ? "有未保存的画板" : "Drawing in progress")
        Button { boardOpen = true } label: {
            if wide {
                hubTile(.board, title: title, count: detail, unit: "")
            } else {
                hubWideTile(.board, title: title,
                            detail: isChinese ? "\(detail) · 画战术，存为战术或训练"
                                              : "\(detail) · draw it out, save it as a play or a drill")
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("hub.board")
    }

    private func playsLink(_ count: Int) -> some View {
        NavigationLink(destination: JournalPlaysScreen()) {
            hubTile(.plays, title: jp("Plays"), count: "\(count)",
                    unit: isChinese ? "个战术" : (count == 1 ? "play" : "plays"))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("hub.plays")
    }

    private var drillsLink: some View {
        NavigationLink(destination: DrillsLibraryView()) {
            hubTile(.drills, title: isChinese ? "训练" : "Drills",
                    count: "\(dataManager.drills.count)", unit: isChinese ? "个训练" : "drills")
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("hub.drills")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .monospaced()
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    /// Icons in the ink colour on a neutral tile (15 Nov 2026, Luther: "we
    /// can do without the colors" — the cone too, the same day).
    private func glyphTile(_ kind: HubGlyph.Kind, tint: Color?, size: CGFloat) -> some View {
        HubGlyph(kind: kind, tint: tint ?? .primary, size: size * 0.56)
            .frame(width: size, height: size)
            .background((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.15),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            // The editor rail's hairline edge (18 Nov 2026 — same treatment).
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }

    private func hubTile(_ kind: HubGlyph.Kind, tint: Color? = nil, title: String, count: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                glyphTile(kind, tint: tint, size: 48)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(count)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 20))
        .filmRoomHover(cornerRadius: 20)
    }

    private func hubWideTile(_ kind: HubGlyph.Kind, tint: Color? = nil, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            glyphTile(kind, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 20))
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

    /// Pushed from the Hub as a full page (15 Nov 2026): no stack of its own
    /// and no Done — the page's Back returns.
    var pushed = false

    var body: some View {
        if pushed {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            List {
                summarySection
                if breakdown.total > 0 {
                    breakdownSection
                }
                if !activeBundles.isEmpty || !payPerSessionClients.isEmpty || !recentlyUsedUp.isEmpty {
                    privateClientsSection
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
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
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

    // MARK: - Private clients (15 Nov 2026)
    //
    // ONE section (Luther: "Active bundles" and "Active private contracts"
    // repeated the same clients — the second was an empty-month stand-in
    // listing every private contract, used-up ones included, despite its
    // title). Bundles with sessions left (nearest to running out first),
    // pay-per-session clients with their rate and this month's sessions, and
    // bundles used up in the last 30 days, dimmed, so a renewal does not slip.
    // Every row opens the contract card.

    private var payPerSessionClients: [Contract] {
        dataManager.contracts.filter { $0.kind == .privatePayPerSession && $0.status == .active }
    }

    /// Bundles with nothing left whose last session was within 30 days.
    private var recentlyUsedUp: [(contract: Contract, last: Date)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return dataManager.contracts
            .filter { $0.kind == .privateBundle && $0.bundleSize > 0 && ($0.bundleRedemptionsRemaining ?? 0) == 0 }
            .compactMap { contract -> (Contract, Date)? in
                let ids = Set(contract.bundleSessionIds)
                guard let last = dataManager.cachedSessionEvents.filter({ ids.contains($0.id) }).map(\.startTime).max(),
                      last >= cutoff else { return nil }
                return (contract, last)
            }
            .sorted { $0.1 > $1.1 }
    }

    private var privateClientsSection: some View {
        let count = activeBundles.count + payPerSessionClients.count + recentlyUsedUp.count
        return Section {
            ForEach(activeBundles) { contract in
                activeBundleRow(contract)
            }
            ForEach(payPerSessionClients) { contract in
                payPerSessionRow(contract)
            }
            ForEach(recentlyUsedUp, id: \.contract.id) { item in
                usedUpRow(item.contract, last: item.last)
            }
        } header: {
            HStack {
                Text("Private clients")
                Spacer()
                Text("^[\(count) client](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        } footer: {
            Text("A bundle is paid up front and counts in the month it is bought; its sessions tick down as the student attends. Pay-per-session adds the price each time the student attends.")
                .font(.caption2)
        }
    }

    private func payPerSessionRow(_ contract: Contract) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        let thisMonth = dataManager.revenueEvents(in: Date())
            .filter { $0.contractId == contract.id && $0.kind == .paygAttendance }.count
        return Button {
            presentedContract = contract
        } label: {
            HStack(spacing: 12) {
                if let s = student { StudentAvatarView(student: s, size: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.primaryDisplayName ?? "—")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Pay per session · \(contract.pricePerSession.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(thisMonth)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("this month")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func usedUpRow(_ contract: Contract, last: Date) -> some View {
        let student = dataManager.students.first { $0.id == contract.studentId }
        return Button {
            presentedContract = contract
        } label: {
            HStack(spacing: 12) {
                if let s = student { StudentAvatarView(student: s, size: 36).opacity(0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.primaryDisplayName ?? "—")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(contract.bundleSize)-pack used up · last session \(last.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("Renew?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
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
                        Text(student?.primaryDisplayName ?? "—")
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

    /// A past month with nothing billed says so; the current month's summary
    /// already reads "No revenue this month" and the clients are listed
    /// above, so it adds nothing.
    @ViewBuilder
    private var emptyMonthSection: some View {
        if !isFocusedOnCurrentMonth {
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
                    Text(student?.primaryDisplayName ?? "—")
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

    /// The shared rule. This used to be a local copy whose comment claimed to
    /// mirror the money authority while omitting its contract check, so every
    /// program-less group session — including the legacy orphan recurring
    /// series — read as private here and appeared in a client's history.
    private func isPrivate(_ event: SessionEvent) -> Bool {
        dataManager.eventIsPrivate(event)
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
                    Text(student?.primaryDisplayName ?? "—")
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
                } footer: {
                    // Consent, not surprise: this toggle moves a prepaid
                    // session the moment Create is tapped, and it used to do
                    // so silently (it auto-switches on for past dates).
                    // Contract work, so permitted under the iOS UI freeze.
                    if markAttended, let remaining = contract.bundleRedemptionsRemaining {
                        Text("Creating this session redeems 1 prepaid session — \(max(0, remaining - 1)) of \(contract.bundleSize) will remain. Deleting the session returns it.")
                    }
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

        // A 1:1 belongs to the client's private micro-group. It used to be
        // deliberately program-less, with privateness inferred downstream from
        // the attendee's contract — the encoding Phase 1 replaced with the
        // program's TYPE, and Phase 2.5 stopped minting here.
        let result = dataManager.createSession(SessionCreation.Intent(
            group: .privateClient(student.id),
            start: combinedStart,
            durationMinutes: Int(endTime.timeIntervalSince(combinedStart) / 60),
            title: title.trimmingCharacters(in: .whitespaces),
            location: resolvedLocation,
            notes: notes.isEmpty ? nil : notes,
            actualAttendeeIds: markAttended ? [student.id] : [],
            createdByCoachId: dataManager.loggedInCoachId))
        let event = result.session

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
                Text(student?.primaryDisplayName ?? "—")
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
                            Text(student.primaryDisplayName)
                                .foregroundStyle(.primary)
                            if let cn = student.secondaryNameLine {
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
                Text(student?.primaryDisplayName ?? "—")
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
                                Text(student.primaryDisplayName)
                                    .foregroundStyle(.primary)
                                if let cn = student.secondaryNameLine {
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
                    Text(student?.primaryDisplayName ?? "Unknown Student")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let chineseName = student?.secondaryNameLine {
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
