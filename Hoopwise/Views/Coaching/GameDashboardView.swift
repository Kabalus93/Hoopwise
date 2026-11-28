import SwiftUI

// THE GAMES DASHBOARD (14 November 2026, Luther: "the game page beside the
// record of games should have a ready dashboard … chemistry … well designed
// in the language of the app"). Beside the game list on iPad / Mac, under it
// on the phone. Reads GameStatsReport (per-game numbers) and GameChemistry
// (the basket logs): how baskets are made, who connects with whom, who sets
// the table. A scope switch reads this session or the whole program.
//
// REWORKED 28 Nov 2026 (Luther: "is this the best we can do in terms of
// insight?" → "build all 7, and rework the UI"). The page now reads RESULTS
// first (Services/GameImpact.swift): who makes their team win, which pairs
// win together, whether what was trained showed up in games, where the
// ratings and the games disagree, and what to watch — each saying how many
// games it stands on, and silent until there are enough. Counting (how they
// score, connections) comes after, and a connection needs to have happened
// at least twice ("100% of his assisted baskets" used to be one basket).

struct GameDashboardView: View {
    /// The program's sessions (coaches' lines already removed).
    let programSessions: [SessionEvent]
    let session: SessionEvent
    let roster: [UUID]
    let students: [Student]
    let excluding: Set<UUID>
    @EnvironmentObject private var dataManager: DataManager
    /// The results reading of the whole program — worked out off the draw.
    @State private var analysis = GameImpact.Report()
    @State private var showAllImpact = false

    /// nil = not chosen yet: this session when it has games, else the program.
    @State private var chosenScope: Scope?
    enum Scope: Hashable { case session, program }
    private var scope: Scope {
        chosenScope ?? (session.games.contains(where: GameStatsReport.played) ? .session : .program)
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var hasOtherSessions: Bool { programSessions.contains { $0.id != session.id && !$0.games.isEmpty } }
    private var sessions: [SessionEvent] { scope == .session || !hasOtherSessions ? [session] : programSessions }

    var body: some View {
        let report = GameStatsReport.make(sessions: sessions, roster: roster, current: session, excluding: excluding)
        let chem = GameChemistry.summary(sessions: sessions, excluding: excluding)
        VStack(alignment: .leading, spacing: 14) {
            header
            tiles(report, chem)

            // RESULTS — always the whole program: one class is too few games.
            sectionTitle(isChinese ? "比赛结果说明什么" : "WHAT THE RESULTS SAY",
                         note: analysis.hasResults
                            ? (isChinese ? "来自两队对抗的 \(analysis.games.count) 场比赛" : "From \(analysis.games.count) games between two teams")
                            : nil)
            if analysis.hasResults {
                impactCard
                if !analysis.pairs.isEmpty { pairsCard }
            } else {
                waitingNote
            }
            if !analysis.transfer.isEmpty { transferCard }
            if !analysis.mismatches.isEmpty { mismatchCard }
            if !analysis.watch.isEmpty { watchCard }

            sectionTitle(isChinese ? "怎么得分" : "HOW THEY SCORE", note: nil)
            if chem.isEmpty {
                emptyNote
            } else {
                scoringCard(chem)
                connectionsCard(chem)
            }
        }
        .task(id: analysisKey) { analysis = makeAnalysis() }
        .accessibilityIdentifier("games.dashboard")
    }

    /// Changes when a game is added or scored anywhere in the program.
    private var analysisKey: Int {
        var hasher = Hasher()
        for s in programSessions {
            hasher.combine(s.id)
            for g in s.games { hasher.combine(g.id); hasher.combine(g.teamScores); hasher.combine(g.playerStats.count) }
        }
        hasher.combine(dataManager.players.count)
        return hasher.finalize()
    }

    private func makeAnalysis() -> GameImpact.Report {
        var trained: [UUID: [DrillAttribute: Double]] = [:]
        for s in programSessions { trained[s.id] = PlanCoverage.minutes(of: s.curriculum, drills: dataManager.drills) }
        var evaluations: [UUID: SkillsEvaluation] = [:]
        for player in dataManager.players { evaluations[player.studentId] = player.skills }
        return GameImpact.report(sessions: programSessions, trained: trained, evaluations: evaluations, excluding: excluding)
    }

    private func sectionTitle(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.bold)).monospaced().foregroundStyle(.secondary)
            if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.top, 8)
    }

    // MARK: Who makes their team win

    private var impactCard: some View {
        let all = analysis.impact
        let shown = showAllImpact || all.count <= 6 ? all : Array(all.prefix(3)) + Array(all.suffix(2))
        let reach = max(1.0, all.map { abs($0.worth) }.max() ?? 1)
        return card(isChinese ? "谁让球队赢球" : "WHO MAKES THEIR TEAM WIN", icon: "trophy") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shown) { p in
                    HStack(spacing: 10) {
                        avatar(p.playerId, 30)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(name(p.playerId)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(signed(p.worth))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(p.worth >= 0.15 ? Color.green : (p.worth <= -0.15 ? Color.orange : Color.secondary))
                            }
                            divergingBar(p.worth / reach)
                            Text(isChinese ? "\(p.wins) 胜 \(p.losses) 负 · \(p.games) 场 · 所在队场均 \(signed(p.margin)) 球"
                                           : "\(p.wins) won · \(p.losses) lost · \(p.games) games · their teams \(signed(p.margin)) baskets a game")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("games.impact.row")
                }
                if all.count > 6 {
                    Button(showAllImpact ? (isChinese ? "收起" : "Show fewer") : (isChinese ? "显示全部 \(all.count) 人" : "Show all \(all.count)")) {
                        withAnimation(.snappy(duration: 0.25)) { showAllImpact.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                }
                Text(isChinese ? "数字是这名球员为所在队每场多带来的净胜球数，已考虑队友和对手是谁。比赛越多越准。"
                               : "The number is what the player adds to their team's winning margin each game, in baskets, allowing for who they played with and against. It firms up as games add up.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("games.impact")
    }

    /// A bar from the middle: right and green for positive, left and orange
    /// for negative. `value` is −1…1.
    private func divergingBar(_ value: Double) -> some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let length = min(half, half * abs(value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(value >= 0 ? Color.green : Color.orange)
                    .frame(width: max(2, length))
                    .offset(x: value >= 0 ? half : half - length)
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1).offset(x: half)
            }
        }
        .frame(height: 5)
    }

    // MARK: Pairs

    private var pairsCard: some View {
        let best = analysis.pairs.filter { $0.margin >= 0.75 }.prefix(3)
        let worst = analysis.pairs.reversed().filter { $0.margin <= -0.75 }.prefix(2)
        return SwiftUI.Group {
            if !best.isEmpty || !worst.isEmpty {
                card(isChinese ? "同队时的组合" : "PAIRS ON THE SAME TEAM", icon: "person.2") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(best)) { pairRow($0, good: true) }
                        if !best.isEmpty, !worst.isEmpty { Divider() }
                        ForEach(Array(worst)) { pairRow($0, good: false) }
                    }
                }
                .accessibilityIdentifier("games.pairs")
            }
        }
    }

    private func pairRow(_ pair: GameImpact.Pair, good: Bool) -> some View {
        HStack(spacing: 8) {
            avatar(pair.first, 28)
            avatar(pair.second, 28).padding(.leading, -12)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(name(pair.first)) + \(name(pair.second))")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(isChinese ? "同队 \(pair.games) 场，赢 \(pair.wins) 场"
                               : "\(pair.games) games together, \(pair.wins) won")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(signed(pair.margin)).font(.headline.monospacedDigit())
                    .foregroundStyle(good ? Color.green : Color.orange)
                Text(isChinese ? "球/场" : "a game").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Training → games

    private var transferCard: some View {
        card(isChinese ? "练的东西打出来了吗" : "DID TRAINING SHOW UP", icon: "arrow.triangle.turn.up.right.diamond") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(analysis.transfer) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(t.axis.title(chinese: isChinese), systemImage: t.axis.icon)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            Image(systemName: t.direction > 0 ? "arrow.up.right" : (t.direction < 0 ? "arrow.down.right" : "equal"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(t.direction > 0 ? Color.green : (t.direction < 0 ? Color.orange : Color.secondary))
                            Text("\(transferValue(t, t.before)) → \(transferValue(t, t.now))")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        Text(isChinese
                             ? "最近 \(t.classes) 节课练了它（占计划时间 \(Int((t.share * 100).rounded()))%）。\(transferMetricName(t))：之前 → 之后。"
                             : "Trained in \(t.classes) recent class\(t.classes == 1 ? "" : "es") (\(Int((t.share * 100).rounded()))% of plan time). \(transferMetricName(t)): before → since.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("games.transfer")
    }

    private func transferMetricName(_ t: GameImpact.Transfer) -> String {
        switch t.metric {
        case .offAPass: isChinese ? "接传球得分的比例" : "Baskets made off a pass"
        case .stocks: isChinese ? "每人每场抢断+盖帽" : "Steals + blocks a player a game"
        case .baskets: isChinese ? "每人每场进球" : "Baskets a player a game"
        }
    }

    private func transferValue(_ t: GameImpact.Transfer, _ v: Double) -> String {
        t.metric == .offAPass ? "\(Int((v * 100).rounded()))%" : String(format: "%.1f", v)
    }

    // MARK: Rating v games

    private var mismatchCard: some View {
        card(isChinese ? "评分和比赛不一致" : "RATING AND GAMES DISAGREE", icon: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(analysis.mismatches) { m in
                    HStack(alignment: .top, spacing: 10) {
                        avatar(m.playerId, 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(m.playerId)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(isChinese
                                 ? "\(m.axis.title(chinese: true))评 \(m.rating) 分，比赛里在 \(m.of) 人中排第 \(m.rank)。\(m.playsAbove ? "比赛表现高于评分。" : "评分高于比赛表现：技术还没带进比赛，或评分该再看看。")"
                                 : "Rated \(m.rating) in \(m.axis.title(chinese: false)), \(ordinal(m.rank)) of \(m.of) in games. \(m.playsAbove ? "Plays above the rating." : "The rating is ahead of the games: the skill is not reaching games yet, or the rating is worth another look.")")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityIdentifier("games.mismatch")
    }

    // MARK: Watch

    private var watchCard: some View {
        card(isChinese ? "留意" : "WORTH WATCHING", icon: "eye") {
            VStack(alignment: .leading, spacing: 10) {
                if let d = analysis.watch.dependence {
                    Label {
                        Text(isChinese
                             ? "\(name(d.top)) 一人进了全队 \(Int((d.topShare * 100).rounded()))% 的球（前两名合计 \(Int((d.topTwoShare * 100).rounded()))%），共 \(d.games) 场。"
                             : "\(name(d.top)) makes \(Int((d.topShare * 100).rounded()))% of all baskets (the top two \(Int((d.topTwoShare * 100).rounded()))%), over \(d.games) games.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "chart.pie").foregroundStyle(.orange)
                    }
                }
                if !analysis.watch.quiet.isEmpty {
                    Label {
                        Text((isChinese ? "上场 3 场以上却没有任何数据：" : "Three games or more without a single stat: ")
                             + analysis.watch.quiet.prefix(5).map(name).joined(separator: isChinese ? "、" : ", ")
                             + (analysis.watch.quiet.count > 5 ? (isChinese ? " 等" : " and more") : ""))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(.orange)
                    }
                }
            }
        }
        .accessibilityIdentifier("games.watch")
    }

    private var waitingNote: some View {
        card(isChinese ? "谁让球队赢球" : "WHO MAKES THEIR TEAM WIN", icon: "trophy") {
            Text(isChinese
                 ? "两队对抗打满 \(GameImpact.minimumGames) 场后，这里会显示谁所在的队更常赢、哪些组合同队时更好（目前 \(analysis.games.count) 场）。"
                 : "After \(GameImpact.minimumGames) games between two teams this shows whose teams win more and which pairs do better together (\(analysis.games.count) so far).")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("games.impact.waiting")
    }

    private func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + String(format: "%.1f", abs(v)) }
    private func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : (["th", "st", "nd", "rd"] + Array(repeating: "th", count: 6))[n % 10]
        return "\(n)\(suffix)"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(isChinese ? "比赛看板" : "GAME DASHBOARD").font(.caption2.weight(.bold)).monospaced()
            } icon: {
                Image(systemName: "chart.xyaxis.line").font(.caption)
            }
            .foregroundStyle(.secondary)
            Spacer()
            if hasOtherSessions {
                Picker("", selection: Binding(get: { scope }, set: { chosenScope = $0 })) {
                    Text(isChinese ? "本次课" : "This session").tag(Scope.session)
                    Text(isChinese ? "整个项目" : "Program").tag(Scope.program)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("games.dashboard.scope")
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ report: GameStatsReport.Report, _ chem: GameChemistry.Summary) -> some View {
        let values = scope == .session || !hasOtherSessions ? (report.thisSession ?? report.average) : report.average
        let gamesCount = scope == .session || !hasOtherSessions ? session.games.filter(GameStatsReport.played).count : report.games
        return HStack(alignment: .top, spacing: 10) {
            tile("\(gamesCount)", isChinese ? "比赛" : "Games", icon: "sportscourt")
            tile(String(format: "%.1f", values[.points] ?? 0), isChinese ? "场均得分" : "Points / game", icon: "flame")
            tile(String(format: "%.1f", values[.rebounds] ?? 0), isChinese ? "场均篮板" : "Boards / game", icon: "arrow.down.to.line")
            tile(chem.isEmpty ? "—" : "\(Int((chem.assistedShare * 100).rounded()))%",
                 isChinese ? "助攻得分占比" : "Off a pass", icon: "arrow.triangle.branch")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ value: String, _ caption: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .filmGlass(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: How they score

    private func scoringCard(_ chem: GameChemistry.Summary) -> some View {
        card(isChinese ? "接传球还是自己创造" : "OFF A PASS OR SELF-CREATED", icon: "basketball") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chem.creation.prefix(6)) { c in
                    HStack(spacing: 10) {
                        avatar(c.playerId, 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(name(c.playerId)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(isChinese ? "\(c.baskets) 球" : "\(c.baskets) baskets")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            splitBar(assisted: c.assisted, own: c.own)
                        }
                    }
                }
                HStack(spacing: 14) {
                    legendDot(.accentColor, isChinese ? "接队友传球" : "Off a pass")
                    legendDot(.orange, isChinese ? "自己创造" : "Self-created")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
    }

    private func splitBar(assisted: Int, own: Int) -> some View {
        GeometryReader { proxy in
            let total = max(1, assisted + own)
            HStack(spacing: 2) {
                if assisted > 0 {
                    Capsule().fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(assisted) / CGFloat(total))
                }
                if own > 0 {
                    Capsule().fill(Color.orange)
                }
            }
        }
        .frame(height: 6)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    // MARK: Connections (a pass that found the same scorer at least twice)

    @ViewBuilder
    private func connectionsCard(_ chem: GameChemistry.Summary) -> some View {
        let duos = chem.duos.filter { $0.count >= 2 }
        let makers = chem.playmakers.filter { $0.assists >= 2 }
        if !duos.isEmpty || !makers.isEmpty {
            card(isChinese ? "传球配合" : "CONNECTIONS", icon: "person.2.wave.2") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(duos.prefix(4)) { duo in
                        HStack(spacing: 8) {
                            avatar(duo.passer, 28)
                            Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                            avatar(duo.scorer, 28)
                            Text("\(name(duo.passer)) → \(name(duo.scorer))")
                                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                            Text("×\(duo.count)").font(.headline.monospacedDigit()).foregroundStyle(Color.accentColor)
                        }
                    }
                    if !duos.isEmpty, !makers.isEmpty { Divider() }
                    ForEach(makers.prefix(3)) { p in
                        HStack(spacing: 10) {
                            avatar(p.playerId, 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name(p.playerId)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if let fav = p.favourite, p.favouriteCount >= 2 {
                                    Text(isChinese ? "最常传给 \(name(fav))（\(p.favouriteCount) 次）"
                                                   : "Finds \(name(fav)) most (\(p.favouriteCount))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(p.assists)").font(.headline.monospacedDigit())
                                Text(isChinese ? "助攻" : "assists").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty

    private var emptyNote: some View {
        card(isChinese ? "如何得分 · 默契" : "HOW THEY SCORE · CHEMISTRY", icon: "basketball") {
            Text(isChinese
                 ? "记分时把得分球员拖到传球的队友身上，这里就会显示谁接传球得分、谁自己创造，以及谁和谁最有默契。"
                 : "Score a basket by dragging from the scorer to the teammate who passed, and this shows who scores off a pass, who creates their own shot, and who connects with whom.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title).font(.caption2.weight(.bold)).monospaced()
            } icon: {
                Image(systemName: icon).font(.caption)
            }
            .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filmGlass(.regular, in: .rect(cornerRadius: 16))
    }

    private func student(_ id: UUID) -> Student? { students.first { $0.id == id } }

    private func name(_ id: UUID) -> String {
        student(id)?.primaryDisplayName ?? (isChinese ? "队员" : "Player")
    }

    @ViewBuilder
    private func avatar(_ id: UUID, _ size: CGFloat) -> some View {
        if let s = student(id) {
            StudentAvatarView(student: s, size: size)
        } else {
            Circle().fill(Color.secondary.opacity(0.2)).frame(width: size, height: size)
        }
    }
}
