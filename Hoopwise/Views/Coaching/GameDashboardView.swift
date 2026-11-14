import SwiftUI

// THE GAMES DASHBOARD (14 November 2026, Luther: "the game page beside the
// record of games should have a ready dashboard … chemistry … well designed
// in the language of the app"). Beside the game list on iPad / Mac, under it
// on the phone. Reads GameStatsReport (per-game numbers) and GameChemistry
// (the basket logs): how baskets are made, who connects with whom, who sets
// the table. A scope switch reads this session or the whole program.

struct GameDashboardView: View {
    /// The program's sessions (coaches' lines already removed).
    let programSessions: [SessionEvent]
    let session: SessionEvent
    let roster: [UUID]
    let students: [Student]
    let excluding: Set<UUID>

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
            if chem.isEmpty {
                emptyNote
            } else {
                scoringCard(chem)
                if !chem.duos.isEmpty { chemistryCard(chem) }
                if !chem.playmakers.isEmpty { playmakersCard(chem) }
            }
        }
        .accessibilityIdentifier("games.dashboard")
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
        return HStack(spacing: 10) {
            tile("\(gamesCount)", isChinese ? "比赛" : "Games", icon: "sportscourt")
            tile(String(format: "%.1f", values[.points] ?? 0), isChinese ? "场均得分" : "Points / game", icon: "flame")
            tile(String(format: "%.1f", values[.rebounds] ?? 0), isChinese ? "场均篮板" : "Boards / game", icon: "arrow.down.to.line")
            tile(chem.isEmpty ? "—" : "\(Int((chem.assistedShare * 100).rounded()))%",
                 isChinese ? "助攻得分占比" : "Off a pass", icon: "arrow.triangle.branch")
        }
    }

    private func tile(_ value: String, _ caption: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: How they score

    private func scoringCard(_ chem: GameChemistry.Summary) -> some View {
        card(isChinese ? "如何得分" : "HOW THEY SCORE", icon: "basketball") {
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

    // MARK: Chemistry

    private func chemistryCard(_ chem: GameChemistry.Summary) -> some View {
        card(isChinese ? "默契组合" : "CHEMISTRY", icon: "person.2.wave.2") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chem.duos.prefix(4)) { duo in
                    HStack(spacing: 8) {
                        avatar(duo.passer, 28)
                        Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                        avatar(duo.scorer, 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(name(duo.passer)) → \(name(duo.scorer))")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            let assisted = chem.creation.first { $0.playerId == duo.scorer }?.assisted ?? duo.count
                            let share = Int((Double(duo.count) / Double(max(1, assisted)) * 100).rounded())
                            Text(isChinese ? "\(name(duo.scorer)) 助攻得分的 \(share)%"
                                           : "\(share)% of \(name(duo.scorer))'s assisted baskets")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("×\(duo.count)").font(.headline.monospacedDigit()).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    // MARK: Playmakers

    private func playmakersCard(_ chem: GameChemistry.Summary) -> some View {
        card(isChinese ? "组织者" : "PLAYMAKERS", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chem.playmakers.prefix(3)) { p in
                    HStack(spacing: 10) {
                        avatar(p.playerId, 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(p.playerId)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let fav = p.favourite {
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
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
