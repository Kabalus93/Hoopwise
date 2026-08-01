import Foundation

// MARK: - Name Index
//
// Collation and search keys for a bilingual roster, Contacts-style: 蔡一明
// sorts under C (by pinyin initial), interleaved with latin names, and is
// findable by typing "cai". One derivation feeds sorting, the A–Z index rail,
// and search — three consumers of one key can never disagree about where a
// name lives.
struct NameIndex {
    /// Romanized, diacritic-stripped, lowercased key used for ordering and
    /// type-to-select. Latin names keep themselves; Chinese names become
    /// plain pinyin. (Roster latin names often carry tone marks — Zhāng —
    /// so stripping diacritics here is what makes them collate as ASCII.)
    let sortKey: String
    /// "A"–"Z" from the sort key's first letter, else "#".
    let section: String
    /// Everything search may match against, lowercased and diacritic-free:
    /// latin name, hanzi, full plain pinyin, and pinyin initials (so "cym"
    /// finds 蔡一明 too, like Contacts).
    let searchBlob: String

    init(name: String, secondary: String?) {
        let romanName: String
        if PinyinConverter.containsChinese(name) {
            romanName = PinyinConverter.toPinyinPlain(name)
        } else {
            romanName = name
        }
        var roman = Self.fold(romanName)
        // A latin field that is empty falls back to the secondary name's
        // pinyin, so a hanzi-only record still sorts by initial, not "#".
        if roman.isEmpty, let secondary, PinyinConverter.containsChinese(secondary) {
            roman = Self.fold(PinyinConverter.toPinyinPlain(secondary))
        }
        sortKey = roman

        if let first = roman.unicodeScalars.first,
           first.value >= 97, first.value <= 122 {   // a-z
            section = String(Character(first)).uppercased()
        } else {
            section = "#"
        }

        var blob: [String] = [roman]
        if let secondary, !secondary.isEmpty {
            blob.append(Self.fold(secondary))
            if PinyinConverter.containsChinese(secondary) {
                let pinyin = Self.fold(PinyinConverter.toPinyinPlain(secondary))
                blob.append(pinyin)
                let initials = pinyin.split(separator: " ").compactMap { $0.first }
                blob.append(String(initials))
            }
        }
        if PinyinConverter.containsChinese(name) {
            blob.append(Self.fold(name))
            let initials = roman.split(separator: " ").compactMap { $0.first }
            blob.append(String(initials))
        }
        searchBlob = blob.joined(separator: "\n")
    }

    /// Whether a query matches: any line of the blob containing the folded
    /// query, or any word starting with it — "cai" hits "cai yi ming".
    func matches(_ query: String) -> Bool {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return true }
        return searchBlob.contains(folded)
    }

    /// The full A–Z rail plus the overflow bucket, in display order.
    static let railSections: [String] =
        (65...90).map { String(UnicodeScalar($0)!) } + ["#"]

    /// Memoized lookup — CFStringTransform is not free and the directory
    /// derives keys on every render. Keyed by both names so an edit
    /// invalidates naturally. Kuxun-scale rosters (800+) stay well under a
    /// megabyte of keys.
    @MainActor private static var cache: [String: NameIndex] = [:]

    @MainActor
    static func cached(name: String, secondary: String?) -> NameIndex {
        let key = name + "\u{1}" + (secondary ?? "")
        if let hit = cache[key] { return hit }
        let fresh = NameIndex(name: name, secondary: secondary)
        cache[key] = fresh
        return fresh
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }
}
