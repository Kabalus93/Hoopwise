import Foundation
import SwiftData

/// The starter library (`Resources/StarterPlays.json`, made by
/// `scripts/plays/make_starter_plays.py`): the plays from Luther's game plan
/// and the Horns family, in English and Chinese. They are added once, in
/// the app's language, and are then the athlete's to edit like any play.
enum JournalPlayLibrary {
    static let seededKey = "starterPlaysVersion"

    // MARK: - The file

    struct Localized: Decodable, Sendable {
        let en: String
        let zh: String
        func text(_ language: Language) -> String { language == .zh ? zh : en }
    }

    enum Language { case en, zh }

    struct StarterNote: Decodable, Sendable { let text: Localized; let at: JournalCourtPoint }

    struct StarterDiagram: Decodable, Sendable {
        let offense: [JournalPlayDiagram.Player]
        let ball: Int?
        let defense: [JournalPlayDiagram.Defender]
        let actions: [JournalPlayDiagram.Action]
        let notes: [StarterNote]

        func diagram(_ language: Language) -> JournalPlayDiagram {
            JournalPlayDiagram(offense: offense, defense: defense, ball: ball, actions: actions,
                        notes: notes.map { JournalPlayDiagram.Note(text: $0.text.text(language), at: $0.at) })
        }
    }

    struct StarterStep: Decodable, Sendable { let caption: Localized; let text: Localized; let diagram: StarterDiagram }

    struct StarterPart: Decodable, Sendable {
        let kind: JournalPlayPartKind
        let name: Localized
        let notes: Localized
        let steps: [StarterStep]
    }

    struct StarterPlay: Decodable, Sendable {
        let key: String
        let category: JournalPlayCategory
        let court: JournalCourtKind
        let name: Localized
        let situation: Localized
        let concept: Localized
        let source: String
        let sourceURL: String?
        let parts: [StarterPart]
    }

    struct File: Decodable, Sendable {
        let version: Int
        let plays: [StarterPlay]
    }

    static func load(from bundle: Bundle = .main) -> File? {
        guard let url = bundle.url(forResource: "StarterPlays", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    /// Chinese when the app shows Chinese, English otherwise.
    static var appLanguage: Language {
        JournalPlayLanguage.isChinese ? .zh : .en
    }

    // MARK: - Adding

    /// Adds the starter plays the first time (or when a newer starter set
    /// ships). A play the athlete deleted stays deleted.
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard,
                             language: Language = appLanguage) -> Int {
        guard let file = load(), defaults.integer(forKey: seededKey) < file.version else { return 0 }
        let added = addMissing(file, to: context, language: language)
        // Only once they are on disk: a run that ends before the save lands
        // must seed again, not leave an empty library marked as seeded.
        if (try? context.fetchCount(FetchDescriptor<JournalPlay>(
            predicate: #Predicate { $0.starterKey != nil }))) ?? 0 > 0 || added == 0 {
            defaults.set(file.version, forKey: seededKey)
        }
        return added
    }

    /// Hoopwise syncs plays through iCloud, which the Journal did not. A
    /// phone reinstalled (or a second phone) seeds before CloudKit has brought
    /// the library back, so the same starter can arrive twice. Keep the
    /// OLDEST copy of each starter (the one other devices already have) and
    /// delete the later ones.
    @discardableResult
    static func removeDuplicateStarters(_ context: ModelContext) -> Int {
        let plays = ((try? context.fetch(FetchDescriptor<JournalPlay>())) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
        var seen = Set<String>()
        var removed = 0
        for play in plays {
            guard let key = play.starterKey else { continue }
            if seen.insert(key).inserted { continue }
            context.delete(play)
            removed += 1
        }
        if removed > 0 { try? context.save() }
        return removed
    }

    /// "Add the starter plays again": any starter play not in the library.
    @discardableResult
    static func restoreStarters(_ context: ModelContext, language: Language = appLanguage) -> Int {
        guard let file = load() else { return 0 }
        return addMissing(file, to: context, language: language)
    }

    static func addMissing(_ file: File, to context: ModelContext, language: Language) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<JournalPlay>())) ?? []).compactMap(\.starterKey))
        var order = ((try? context.fetch(FetchDescriptor<JournalPlay>())) ?? []).map(\.order).max() ?? -1
        var added = 0
        for starter in file.plays where !existing.contains(starter.key) {
            order += 1
            insert(starter, order: order, into: context, language: language)
            added += 1
        }
        try? context.save()
        return added
    }

    @discardableResult
    static func insert(_ starter: StarterPlay, order: Int, into context: ModelContext, language: Language) -> JournalPlay {
        let play = JournalPlay(name: starter.name.text(language), category: starter.category, court: starter.court)
        context.insert(play)
        play.situation = starter.situation.text(language)
        play.concept = starter.concept.text(language)
        play.source = starter.source
        play.sourceURL = starter.sourceURL
        play.starterKey = starter.key
        play.order = order
        for (i, starterPart) in starter.parts.enumerated() {
            let part = JournalPlayPart(kind: starterPart.kind, name: starterPart.name.text(language), order: i)
            context.insert(part)
            part.notes = starterPart.notes.text(language)
            play.parts?.append(part)
            for (j, starterStep) in starterPart.steps.enumerated() {
                let step = JournalPlayStep(order: j, caption: starterStep.caption.text(language),
                                    text: starterStep.text.text(language),
                                    diagram: starterStep.diagram.diagram(language))
                context.insert(step)
                part.steps?.append(step)
            }
        }
        return play
    }
}
