import SwiftUI

// THE GAME RECAP (14 November 2026, Luther: "another page that's a weak point
// of our design. make it match the vision we're moving with"). The session
// page's language: a hero card over a drawn court with the final score, then
// glass cards under caps headers — player of the game, how they scored (the
// basket log), awards, and a box score by team. The random "tip" line and the
// opaque "Contribution / CTR" numbers are gone; contribution still picks the
// player of the game.

struct GameRecapView: View {
    let game: SessionGame
    let students: [Student]
    let allGamesInSession: [SessionGame]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var scheme

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    // MARK: - Awards

    enum GameAward: CaseIterable {
        case mvp, sharpshooter, playmaker, wall, pickpocket, boardBoss, allAround

        var icon: String {
            switch self {
            case .mvp: return "crown.fill"
            case .sharpshooter: return "scope"
            case .playmaker: return "arrow.triangle.branch"
            case .wall: return "hand.raised.fill"
            case .pickpocket: return "hand.point.up.left.fill"
            case .boardBoss: return "arrow.down.to.line"
            case .allAround: return "seal.fill"
            }
        }

        var color: Color {
            switch self {
            case .mvp, .sharpshooter: return .orange
            case .playmaker: return .blue
            case .wall: return .teal
            case .pickpocket: return .red
            case .boardBoss: return .purple
            case .allAround: return .green
            }
        }

        func name(chinese: Bool) -> String {
            switch self {
            case .mvp: return "MVP"
            case .sharpshooter: return chinese ? "得分王" : "Top Scorer"
            case .playmaker: return chinese ? "助攻王" : "Playmaker"
            case .wall: return chinese ? "盖帽王" : "The Wall"
            case .pickpocket: return chinese ? "抢断王" : "Pickpocket"
            case .boardBoss: return chinese ? "篮板王" : "Board Boss"
            case .allAround: return chinese ? "全能之星" : "All-Around"
            }
        }

        func unit(_ n: Int, chinese: Bool) -> String {
            switch self {
            case .mvp: return ""
            case .sharpshooter: return chinese ? "分" : (n == 1 ? "pt" : "pts")
            case .playmaker: return chinese ? "助攻" : (n == 1 ? "assist" : "assists")
            case .wall: return chinese ? "盖帽" : (n == 1 ? "block" : "blocks")
            case .pickpocket: return chinese ? "抢断" : (n == 1 ? "steal" : "steals")
            case .boardBoss: return chinese ? "篮板" : (n == 1 ? "board" : "boards")
            case .allAround: return chinese ? "项数据" : "stats"
            }
        }
    }

    private func contribution(_ s: SessionPlayerStats) -> Double {
        let scoring = Double(s.points) + Double(s.rebounds) * 1.2
        let defense: Double = Double(s.steals + s.blocks) * 1.5
        return scoring + Double(s.assists) * 1.5 + defense
    }

    private var lines: [SessionPlayerStats] { game.playerStats.filter(\.hasStats) }

    private var mvp: SessionPlayerStats? {
        lines.max { contribution($0) < contribution($1) }
    }

    private var awards: [(award: GameAward, playerId: UUID, value: Int)] {
        guard !lines.isEmpty else { return [] }
        var out: [(GameAward, UUID, Int)] = []
        func top(_ key: KeyPath<SessionPlayerStats, Int>, min: Int) -> SessionPlayerStats? {
            guard let best = lines.max(by: { $0[keyPath: key] < $1[keyPath: key] }), best[keyPath: key] >= min else { return nil }
            // A tie is nobody's award.
            return lines.filter { $0[keyPath: key] == best[keyPath: key] }.count == 1 ? best : nil
        }
        if let t = top(\.points, min: 2) { out.append((.sharpshooter, t.playerId, t.points)) }
        if let t = top(\.assists, min: 1) { out.append((.playmaker, t.playerId, t.assists)) }
        if let t = top(\.rebounds, min: 2) { out.append((.boardBoss, t.playerId, t.rebounds)) }
        if let t = top(\.steals, min: 1) { out.append((.pickpocket, t.playerId, t.steals)) }
        if let t = top(\.blocks, min: 1) { out.append((.wall, t.playerId, t.blocks)) }
        if let all = lines.first(where: { s in
            s.playerId != mvp?.playerId
                && [s.points >= 2, s.rebounds >= 1, s.assists >= 1, s.steals >= 1, s.blocks >= 1].filter { $0 }.count >= 3
        }) {
            let n = [all.points >= 2, all.rebounds >= 1, all.assists >= 1, all.steals >= 1, all.blocks >= 1].filter { $0 }.count
            out.append((.allAround, all.playerId, n))
        }
        return out
    }

    private func previousLine(for playerId: UUID) -> SessionPlayerStats? {
        let earlier = allGamesInSession.filter { $0.id != game.id && $0.gameNumber < game.gameNumber && $0.status == .completed }
            .sorted { $0.gameNumber < $1.gameNumber }
        for g in earlier.reversed() {
            if let s = g.playerStats.first(where: { $0.playerId == playerId && $0.hasStats }) { return s }
        }
        return nil
    }

    private func student(_ id: UUID) -> Student? { students.first { $0.id == id } }
    private func name(_ id: UUID) -> String { student(id)?.primaryDisplayName ?? (isChinese ? "队员" : "Player") }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero
                    if let mvp, student(mvp.playerId) != nil { playerOfTheGame(mvp) }
                    scoringCard
                    if !awards.isEmpty { awardsCard }
                    boxScore
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isChinese ? "比赛回顾" : "Game Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("game.recap")
    }

    // MARK: - Hero

    private var teams: [GameTeam] { game.activeTeams.isEmpty ? game.teams : game.activeTeams }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
            if game.gameType.isIndividual || teams.count != 2 {
                podium
            } else {
                scoreRow(teams[0], teams[1])
            }
            if let result = resultLine {
                Text(result)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CardCourtBackground(color: Color(red: 0.08, green: 0.3, blue: 0.75), style: .fullCourt)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var eyebrow: String {
        var parts = [isChinese ? "第\(game.gameNumber)场 · 终场" : "GAME \(game.gameNumber) · FINAL"]
        if let start = game.startedAt, let end = game.endedAt, end > start {
            let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
            parts.append(isChinese ? "\(minutes) 分钟" : "\(minutes) MIN")
        }
        return parts.joined(separator: " · ")
    }

    private var resultLine: String? {
        guard !game.gameType.isIndividual, teams.count == 2 else {
            if let first = game.individualLeaderboard.first, first.points > 0 {
                return isChinese ? "\(name(first.playerId)) 以 \(first.points) 分胜出" : "\(name(first.playerId)) wins with \(first.points)"
            }
            return nil
        }
        let a = game.score(for: teams[0].id), b = game.score(for: teams[1].id)
        if a == b { return isChinese ? "\(a) 平" : "Tied at \(a)" }
        let (winner, margin) = a > b ? (teams[0], a - b) : (teams[1], b - a)
        let team = GameTeam.localizedColorName(winner.name)
        return isChinese ? "\(team)队 \(margin) 分胜出" : "\(team) won by \(margin)"
    }

    private func scoreRow(_ left: GameTeam, _ right: GameTeam) -> some View {
        let l = game.score(for: left.id), r = game.score(for: right.id)
        return HStack(alignment: .center, spacing: 0) {
            teamScore(left, score: l, won: l > r, alignment: .leading)
            Text("–")
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
            teamScore(right, score: r, won: r > l, alignment: .trailing)
        }
    }

    private func teamScore(_ team: GameTeam, score: Int, won: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                if alignment == .trailing { winPill(won) }
                Circle()
                    .fill(Color(hex: team.colorHex))
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 14, height: 14)
                Text(GameTeam.localizedColorName(team.name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if alignment == .leading { winPill(won) }
            }
            Text("\(score)")
                .font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(won ? 1 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: Double(score)))
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private func winPill(_ won: Bool) -> some View {
        if won {
            Text(isChinese ? "胜" : "WIN")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.green.opacity(0.5)), in: .capsule)
        }
    }

    private var podium: some View {
        let top = Array(game.individualLeaderboard.prefix(3))
        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(top.enumerated()), id: \.element.playerId) { index, entry in
                VStack(spacing: 6) {
                    if let s = student(entry.playerId) {
                        StudentAvatarView(student: s, size: index == 0 ? 64 : 48)
                            .overlay(Circle().strokeBorder(.white.opacity(index == 0 ? 0.9 : 0.4), lineWidth: index == 0 ? 3 : 1.5))
                    }
                    Text("\(entry.points)")
                        .font(.system(size: index == 0 ? 34 : 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.75))
                    Text(name(entry.playerId))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Player of the game

    private func playerOfTheGame(_ line: SessionPlayerStats) -> some View {
        let prev = previousLine(for: line.playerId)
        return card(isChinese ? "本场最佳" : "PLAYER OF THE GAME", icon: "crown.fill", tint: .orange) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    if let s = student(line.playerId) {
                        StudentAvatarView(student: s, size: 64)
                            .overlay(Circle().strokeBorder(Color.orange, lineWidth: 2.5).padding(-3))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name(line.playerId))
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let second = student(line.playerId)?.secondaryNameLine {
                            Text(second).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let team = game.teams.first(where: { $0.id == line.teamId || $0.playerIds.contains(line.playerId) }) {
                            HStack(spacing: 5) {
                                Circle().fill(team.displayColor(for: scheme)).frame(width: 8, height: 8)
                                Text(GameTeam.localizedColorName(team.name))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 0) {
                    ForEach(statColumns(line), id: \.label) { col in
                        VStack(spacing: 2) {
                            Text("\(col.value)")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(col.value > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                            Text(col.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let p = prev {
                                deltaLabel(col.value - col.previous(p))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if prev != nil {
                    Text(isChinese ? "箭头：与本节课上一场比较" : "Arrows: against this player's previous game today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private struct StatColumn {
        let label: String
        let value: Int
        let previous: (SessionPlayerStats) -> Int
    }

    private func statColumns(_ s: SessionPlayerStats) -> [StatColumn] {
        [StatColumn(label: isChinese ? "得分" : "PTS", value: s.points, previous: { $0.points }),
         StatColumn(label: isChinese ? "篮板" : "REB", value: s.rebounds, previous: { $0.rebounds }),
         StatColumn(label: isChinese ? "助攻" : "AST", value: s.assists, previous: { $0.assists }),
         StatColumn(label: isChinese ? "抢断" : "STL", value: s.steals, previous: { $0.steals }),
         StatColumn(label: isChinese ? "盖帽" : "BLK", value: s.blocks, previous: { $0.blocks })]
    }

    @ViewBuilder
    private func deltaLabel(_ diff: Int) -> some View {
        if diff == 0 {
            Text("–").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        } else {
            Text(diff > 0 ? "↑\(diff)" : "↓\(-diff)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(diff > 0 ? Color.green : Color.red)
        }
    }

    // MARK: - How they scored (the basket log)

    @ViewBuilder
    private var scoringCard: some View {
        let chem = GameChemistry.summary(games: [game])
        if !chem.isEmpty {
            card(isChinese ? "如何得分" : "HOW THEY SCORED", icon: "basketball.fill", tint: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int((chem.assistedShare * 100).rounded()))%")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text(isChinese ? "的进球来自队友传球 · \(chem.assisted)/\(chem.baskets)"
                                       : "of baskets came off a pass · \(chem.assisted) of \(chem.baskets)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            if chem.assisted > 0 {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: proxy.size.width * chem.assistedShare)
                            }
                            if chem.assisted < chem.baskets { Capsule().fill(Color.orange) }
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 14) {
                        legend(.accentColor, isChinese ? "接队友传球" : "Off a pass")
                        legend(.orange, isChinese ? "自己创造" : "Self-created")
                    }
                    if let duo = chem.duos.first, duo.count >= 2 {
                        Divider()
                        HStack(spacing: 8) {
                            avatar(duo.passer, 28)
                            Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                            avatar(duo.scorer, 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(name(duo.passer)) → \(name(duo.scorer))")
                                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(isChinese ? "本场最默契的传球组合" : "The game's strongest connection")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("×\(duo.count)").font(.headline.monospacedDigit()).foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Awards

    private var awardsCard: some View {
        card(isChinese ? "荣誉" : "AWARDS", icon: "rosette", tint: .purple) {
            VStack(spacing: 10) {
                ForEach(awards, id: \.award) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.award.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.award.color)
                            .frame(width: 34, height: 34)
                            .background(item.award.color.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.award.name(chinese: isChinese))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.award.color)
                            HStack(spacing: 6) {
                                avatar(item.playerId, 22)
                                Text(name(item.playerId))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(item.value)").font(.headline.monospacedDigit())
                            Text(item.award.unit(item.value, chinese: isChinese))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Box score

    private var groups: [(team: GameTeam?, lines: [SessionPlayerStats])] {
        let sorted = game.playerStats.sorted { contribution($0) > contribution($1) }
        guard !game.gameType.isIndividual, !teams.isEmpty else { return [(nil, sorted)] }
        var used = Set<UUID>()
        var out: [(GameTeam?, [SessionPlayerStats])] = []
        for team in teams {
            let mine = sorted.filter { $0.teamId == team.id || team.playerIds.contains($0.playerId) }
                .filter { !used.contains($0.playerId) }
            mine.forEach { used.insert($0.playerId) }
            if !mine.isEmpty { out.append((team, mine)) }
        }
        let rest = sorted.filter { !used.contains($0.playerId) }
        if !rest.isEmpty { out.append((nil, rest)) }
        return out
    }

    private var columnLabels: [String] {
        isChinese ? ["分", "板", "助", "断", "帽"] : ["PTS", "REB", "AST", "STL", "BLK"]
    }

    private var boxScore: some View {
        card(isChinese ? "技术统计" : "BOX SCORE", icon: "tablecells", tint: .secondary) {
            VStack(spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            if let team = group.team {
                                Circle().fill(team.displayColor(for: scheme)).frame(width: 10, height: 10)
                                Text(GameTeam.localizedColorName(team.name)).font(.subheadline.weight(.bold))
                                Text("\(game.score(for: team.id))")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(isChinese ? "球员" : "Players").font(.subheadline.weight(.bold))
                            }
                            Spacer()
                            ForEach(columnLabels, id: \.self) { label in
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 31)
                            }
                        }
                        ForEach(group.lines, id: \.playerId) { line in
                            boxRow(line)
                        }
                    }
                }
            }
        }
    }

    private func boxRow(_ line: SessionPlayerStats) -> some View {
        let isMVP = line.playerId == mvp?.playerId
        return HStack(spacing: 8) {
            avatar(line.playerId, 30)
                .overlay(alignment: .topTrailing) {
                    if isMVP {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.orange, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            Text(name(line.playerId))
                .font(.subheadline.weight(isMVP ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            ForEach(Array([line.points, line.rebounds, line.assists, line.steals, line.blocks].enumerated()), id: \.offset) { _, v in
                Text("\(v)")
                    .font(.subheadline.monospacedDigit().weight(v > 0 ? .semibold : .regular))
                    .foregroundStyle(v > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 31)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isMVP ? Color.orange.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, -8)
    }

    // MARK: - Pieces

    private func card<Content: View>(_ title: String, icon: String, tint: Color,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title).font(.caption2.weight(.bold)).monospaced()
            } icon: {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
            }
            .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
