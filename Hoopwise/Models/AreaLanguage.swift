import Foundation

// LANGUAGE PER AREA (17 November 2026, Luther: "choose a different language
// than the main one for: Export PDF, in app player card, game recap, roll call
// camera"). Each area follows the app language unless the coach picks one in
// Profile → Preferences → Languages. Device setting (UserDefaults), like the
// app language itself.
//
// The roll-call photo LEFT this list on 19 Nov 2026 (Luther: everything on it
// in Chinese, the coach's name too) — it is always Chinese now.

nonisolated enum AreaLanguage {
    enum Area: String, CaseIterable, Identifiable {
        /// The Parent Guide PDF and long image.
        case exports
        /// The player card — in the app, the shared image and the A3 sheets.
        case playerCard
        case gameRecap

        var id: String { rawValue }

        var key: String { "language.area.\(rawValue)" }

        /// What an area reads when the coach never chose.
        var defaultChoice: Choice { .app }

        func title(chinese: Bool) -> String {
            switch self {
            case .exports: return chinese ? "导出的 PDF（家长指南、战术单）" : "Exported PDFs (Parent Guide, play sheets)"
            case .playerCard: return chinese ? "球员卡" : "Player card"
            case .gameRecap: return chinese ? "比赛回顾" : "Game recap"
            }
        }
    }

    enum Choice: String, CaseIterable, Identifiable {
        case app, english, chinese
        var id: String { rawValue }

        func title(chinese: Bool) -> String {
            switch self {
            case .app: return chinese ? "跟随应用" : "Same as app"
            case .english: return "English"
            case .chinese: return "中文"
            }
        }
    }

    static func choice(for area: Area, defaults: UserDefaults = .standard) -> Choice {
        defaults.string(forKey: area.key).flatMap(Choice.init(rawValue:)) ?? area.defaultChoice
    }

    static func set(_ choice: Choice, for area: Area, defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: area.key)
    }

    /// Whether `area` speaks Chinese right now. Reads the app language from
    /// the key LocalizationManager writes, so it works off the main actor.
    nonisolated static func isChinese(_ area: Area, defaults: UserDefaults = .standard) -> Bool {
        switch choice(for: area, defaults: defaults) {
        case .app: return defaults.string(forKey: "app_language") == AppLanguage.chinese.rawValue
        case .english: return false
        case .chinese: return true
        }
    }
}
