import Foundation

// Hub → LEXICON (November 2026, Luther: "a lexicon in the Hub for
// basketball terms — names of plays and their definitions, actions, rules,
// defenses", from his researched Claude Docs "Basketball Lexicon").
// Resources/Lexicon.json is generated from that doc (sections → groups →
// entries, plus its numbered sources) — regenerate, don't hand-edit. Read
// only; nothing here is stored or synced.

struct Lexicon: Decodable {
    let title: String
    let intro: [String]
    let sections: [Section]
    let sources: [Source]

    struct Section: Decodable, Identifiable, Hashable {
        let title: String
        let note: String
        let groups: [Group]
        var id: String { title }
        var entryCount: Int { groups.reduce(0) { $0 + $1.entries.count } }
    }

    struct Group: Decodable, Identifiable, Hashable {
        /// terms (term · also called · definition), compare (a rule's value
        /// per rulebook), history (year · change), disputed (term · meanings).
        enum Kind: String, Decodable { case terms, compare, history, disputed }
        let title: String
        let note: String
        let kind: Kind
        let columns: [String]?
        let entries: [Entry]
        var id: String { title + kind.rawValue + "\(entries.count)" }
    }

    struct Entry: Decodable, Identifiable, Hashable {
        let term: String
        let aka: String
        let definition: String
        let sources: [Int]
        /// Compare rows: one value per `Group.columns`.
        let values: [String]?
        var id: String { term + "|" + definition.prefix(40) + (values?.joined() ?? "") }
    }

    struct Source: Decodable, Identifiable, Hashable {
        let n: Int
        let title: String
        let url: String
        var id: Int { n }
    }

    /// An entry with where it lives, for search results and links.
    struct Located: Identifiable, Hashable {
        let entry: Entry
        let section: Section
        let group: Group
        var id: String { section.title + "/" + entry.id }
    }

    static let shared: Lexicon = {
        guard let url = Bundle.main.url(forResource: "Lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lexicon = try? JSONDecoder().decode(Lexicon.self, from: data) else {
            return Lexicon(title: "Basketball Lexicon", intro: [], sections: [], sources: [])
        }
        return lexicon
    }()

    var all: [Located] {
        sections.flatMap { section in
            section.groups.flatMap { group in group.entries.map { Located(entry: $0, section: section, group: group) } }
        }
    }

    var entryCount: Int { sections.reduce(0) { $0 + $1.entryCount } }

    func source(_ n: Int) -> Source? { sources.first { $0.n == n } }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Every typed word must appear in the term, its other names or the
    /// definition; terms that match by name come first.
    func search(_ query: String) -> [Located] {
        let words = Lexicon.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let phrase = Lexicon.fold(query.trimmingCharacters(in: .whitespaces))
        var scored: [(Located, Int)] = []
        for item in all {
            let term = Lexicon.fold(item.entry.term)
            let aka = Lexicon.fold(item.entry.aka)
            let body = Lexicon.fold(item.entry.definition + " " + (item.entry.values ?? []).joined(separator: " "))
            guard words.allSatisfy({ term.contains($0) || aka.contains($0) || body.contains($0) }) else { continue }
            let score: Int
            if term == phrase { score = 0 }
            else if term.hasPrefix(phrase) { score = 1 }
            else if term.contains(phrase) { score = 2 }
            else if aka.contains(phrase) { score = 3 }
            else if words.allSatisfy({ term.contains($0) || aka.contains($0) }) { score = 4 }
            else { score = 5 }
            scored.append((item, score))
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.entry.term.count < $1.0.entry.term.count }
            .map(\.0)
    }

    /// Other entries this definition names, by term (whole words, longest
    /// first so "Pick-and-roll" wins over "Roll"); never itself.
    func related(to item: Located, limit: Int = 8) -> [Located] {
        let text = " " + Lexicon.fold(item.entry.definition + " " + item.entry.aka) + " "
        let ownTerm = Lexicon.fold(item.entry.term)
        var found: [Located] = []
        var seen = Set<String>([ownTerm])
        let candidates = all.filter { $0.group.kind == .terms && $0.entry.term.count >= 4 }
            .sorted { $0.entry.term.count > $1.entry.term.count }
        for candidate in candidates {
            let term = Lexicon.fold(candidate.entry.term)
            guard !seen.contains(term), Lexicon.containsWord(term, in: text) else { continue }
            seen.insert(term)
            found.append(candidate)
            if found.count == limit { break }
        }
        return found
    }

    /// The disputed-terms entry for this term, when it has one.
    func dispute(for item: Located) -> Located? {
        guard item.group.kind != .disputed else { return nil }
        let names = Lexicon.names(item.entry.term)
        return all.first { candidate in
            guard candidate.group.kind == .disputed else { return false }
            return Lexicon.names(candidate.entry.term).contains { part in
                names.contains { $0 == part || (part.contains(" ") && $0.hasPrefix(part + " ")) }
            }
        }
    }

    /// "Gather step / zero step" → both; "Unsportsmanlike vs flagrant" →
    /// both; "Amoeba defense origin" → "amoeba defense".
    static func names(_ term: String) -> [String] {
        fold(term)
            .replacingOccurrences(of: " vs ", with: " / ")
            .components(separatedBy: " / ")
            .map { name in
                var name = name.trimmingCharacters(in: .whitespaces)
                for suffix in [" origin", " distance"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
                return name
            }
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let hit = text.range(of: word, range: range) {
            let before = hit.lowerBound == text.startIndex ? " " : text[text.index(before: hit.lowerBound)]
            let after = hit.upperBound == text.endIndex ? " " : text[hit.upperBound]
            if !before.isLetter && !after.isLetter { return true }
            range = hit.upperBound..<text.endIndex
        }
        return false
    }
}
