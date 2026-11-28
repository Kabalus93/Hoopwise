import Foundation

// WHAT A POST SAYS (26 Nov 2026, Luther: "Hoopwise can automatically overlay a
// cool stat on it … templates that adjust to the player's stats"). Pure: from
// the athlete's games, one block of numbers for a photo — their best game of
// the latest class with games, this month's averages, or every game's. Only
// what was recorded; a stat of zero is never put on show in the headline row.

nonisolated struct AthletePostFacts: Equatable {
    enum Source: String, CaseIterable, Identifiable {
        case lastGame, month, allTime
        var id: String { rawValue }
        func title(chinese: Bool) -> String {
            switch self {
            case .lastGame: chinese ? "最近一场" : "Last game"
            case .month: chinese ? "本月" : "This month"
            case .allTime: chinese ? "全部比赛" : "All games"
            }
        }
    }

    struct Stat: Equatable, Identifiable {
        var key: String          // "pts"
        var label: String        // "PTS" / "得分"
        var word: String         // "Points" / "得分"
        var value: Double
        var text: String         // "24" / "12.4"
        var id: String { key }
    }

    var firstName: String
    var lastName: String
    /// The whole name as it is written, in letters (the signature).
    var signature: String = ""
    var jersey: Int?
    var colorHex: String
    var academy: String
    var source: Source
    /// "GAME · 21 NOV", "NOVEMBER", "ALL GAMES".
    var eyebrow: String
    /// "vs Hawks" / the class / "12 games".
    var subtitle: String
    /// PTS REB AST STL BLK (+ GAMES for averages), in that order.
    var stats: [Stat]
    var games: Int

    var hasStats: Bool { games > 0 }

    /// The three to headline: the biggest non-zero, kept in the usual order.
    var headline: [Stat] {
        let counting = stats.filter { $0.key != "gp" }
        let top = counting.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        let picked = counting.filter { top.contains($0.key) }
        return picked.isEmpty ? Array(counting.prefix(3)) : picked
    }

    /// The biggest number, for the poster.
    var big: Stat? { headline.max { $0.value < $1.value } }

    // MARK: Making it

    static func make(student: Student, jersey: Int?, colorHex: String, academy: String,
                     sessions: [SessionEvent], source: Source, chinese: Bool,
                     now: Date = .now, calendar: Calendar = .current) -> AthletePostFacts {
        let names = nameParts(student, chinese: chinese)
        var facts = AthletePostFacts(firstName: names.first, lastName: names.last,
                                     signature: student.name.trimmingCharacters(in: .whitespaces),  // a signature is written in letters
                                     jersey: jersey,
                                     colorHex: colorHex, academy: academy, source: source,
                                     eyebrow: "", subtitle: "", stats: [], games: 0)
        let all = GameStatsReport.playerGames(student.id, in: sessions)
        let monthFormat = DateFormatter()
        monthFormat.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        switch source {
        case .lastGame:
            // The best game (most counted) of the latest class with games.
            guard let lastSession = all.last?.sessionId,
                  let best = all.filter({ $0.sessionId == lastSession })
                    .max(by: { contribution($0.line) < contribution($1.line) }) else {
                facts.eyebrow = source.title(chinese: chinese).uppercased()
                return facts
            }
            monthFormat.dateFormat = chinese ? "M月d日" : "d MMM"
            facts.eyebrow = (chinese ? "比赛 · " : "GAME · ") + monthFormat.string(from: best.date).uppercased()
            let session = sessions.first { $0.id == best.sessionId }
            if let opponent = session?.curriculum.gamePlan?.opponent, !opponent.isEmpty {
                facts.subtitle = (chinese ? "对阵 " : "vs ") + opponent
            } else if let other = best.game.teams.first(where: { $0.id != best.line.teamId }), !best.game.gameType.isIndividual {
                facts.subtitle = (chinese ? "对阵 " : "vs ") + other.name
            } else {
                facts.subtitle = session?.title ?? ""
            }
            facts.games = 1
            facts.stats = counted(best.line, chinese: chinese).map { stat($0.0, $0.1, Double($0.2), chinese: chinese, decimals: false) }
        case .month, .allTime:
            let games: [GameStatsReport.PlayerGame]
            if source == .month {
                let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
                games = all.filter { $0.date >= start }
                monthFormat.dateFormat = chinese ? "M月" : "MMMM"
                facts.eyebrow = monthFormat.string(from: now).uppercased()
            } else {
                games = all
                facts.eyebrow = chinese ? "全部比赛" : "ALL GAMES"
            }
            facts.games = games.count
            facts.subtitle = chinese ? "\(games.count) 场 · 场均" : "\(games.count) game\(games.count == 1 ? "" : "s") · per game"
            guard !games.isEmpty else { return facts }
            let n = Double(games.count)
            var sums: [String: Int] = [:]
            for g in games { for (key, _, value) in counted(g.line, chinese: chinese) { sums[key, default: 0] += value } }
            facts.stats = counted(games[0].line, chinese: chinese).map { key, _, _ in
                stat(key, "", Double(sums[key] ?? 0) / n, chinese: chinese, decimals: true)
            }
            facts.stats.append(Stat(key: "gp", label: chinese ? "场次" : "GAMES", word: chinese ? "场次" : "Games",
                                    value: n, text: "\(games.count)"))
        }
        return facts
    }

    private static func contribution(_ l: SessionPlayerStats) -> Int {
        l.points + l.rebounds + l.assists + l.steals + l.blocks
    }

    private static func counted(_ l: SessionPlayerStats, chinese: Bool) -> [(String, String, Int)] {
        [("pts", "", l.points), ("reb", "", l.rebounds), ("ast", "", l.assists), ("stl", "", l.steals), ("blk", "", l.blocks)]
    }

    private static func stat(_ key: String, _ unused: String, _ value: Double, chinese: Bool, decimals: Bool) -> Stat {
        let words: [String: (String, String, String, String)] = [
            "pts": ("PTS", "Points", "得分", "得分"),
            "reb": ("REB", "Rebounds", "篮板", "篮板"),
            "ast": ("AST", "Assists", "助攻", "助攻"),
            "stl": ("STL", "Steals", "抢断", "抢断"),
            "blk": ("BLK", "Blocks", "盖帽", "盖帽"),
        ]
        let w = words[key] ?? (key.uppercased(), key, key, key)
        let text = decimals ? String(format: "%.1f", value) : String(Int(value.rounded()))
        return Stat(key: key, label: chinese ? w.2 : w.0, word: chinese ? w.3 : w.1, value: value, text: text)
    }

    /// First and last name for the big type: the last word is the last name;
    /// a Chinese card prints the Chinese name whole as the last name.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter }
    }

    static func nameParts(_ s: Student, chinese: Bool) -> (first: String, last: String) {
        let name = s.primaryName(chinese: chinese).trimmingCharacters(in: .whitespaces)
        if name.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return ("", name)
        }
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1 else { return ("", name) }
        // Pinyin of their Chinese name runs family name first ("Liú Chén Lín"
        // = 刘晨林): the family name is the FIRST word (28 Nov 2026 — the
        // Torn paper poster printed "LÍN" big as if it were the surname).
        if let hanzi = s.chineseName, PinyinConverter.containsChinese(hanzi),
           fold(name) == fold(PinyinConverter.toPinyinPlain(hanzi)) {
            return (words.dropFirst().joined(separator: " "), words[0])
        }
        return (words.dropLast().joined(separator: " "), words.last ?? "")
    }
}
