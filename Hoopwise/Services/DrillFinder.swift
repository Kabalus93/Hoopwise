import Foundation
import NaturalLanguage
import Security

// "Describe a drill" (November 2026, Luther: "I have these great drills and the
// only way I can find them is to name them by their exact name … I don't want to
// create a new drill if it exists already"). His example — "players pass 10
// times to score a point while the opposite team defends" — is "20 Passes,
// Keeping Off" (U7, small games): the description is right about how the game
// works and wrong about the number. On-device similarity ranked it 41st, so the
// finder asks CLAUDE (Haiku), which reads the WHOLE catalog every time (~38k
// tokens; the library half is prompt-cached), and falls back to an on-device
// ranking (word match with coaching synonyms + sentence embedding) when there
// is no key or no connection. Only drill text leaves the Mac — never athletes.
// The Mac drills page and the session plan's drill picker use it: Return in
// their search field asks Claude.

/// One drill as the finder sees it.
nonisolated struct DrillFinderEntry: Hashable, Sendable {
    let drillId: UUID
    /// The first 8 hex characters of the id: what Claude is shown and answers with.
    var ref: String { String(drillId.uuidString.prefix(8)).lowercased() }
    let name: String
    let nameZh: String
    /// "U7 · Small games · Passing", or "Personal · Offense".
    let place: String
    let text: String
    let textZh: String
    let isPersonal: Bool
}

nonisolated struct DrillFinderMatch: Hashable, Sendable {
    let drillId: UUID
    let why: String
}

nonisolated struct DrillFinderResult: Sendable {
    enum Source: Sendable { case claude, onDevice }
    let matches: [DrillFinderMatch]
    /// Claude's one line when nothing fits well ("Nothing counts to 10 …").
    let note: String
    let source: Source
}

nonisolated enum DrillFinderError: LocalizedError {
    case noKey
    case http(Int, String)
    case unreadable
    var errorDescription: String? {
        switch self {
        case .noKey: return "No Anthropic API key is set."
        case .http(let code, let message): return "Claude answered \(code): \(message)"
        case .unreadable: return "Claude's answer could not be read."
        }
    }
}

nonisolated enum DrillFinder {
    // MARK: - The catalog

    /// Library activities (games and activities, not rule options) and the
    /// coach's personal drills, each in one line. Library entries come in the
    /// library's own order, so their text never changes between searches and
    /// stays cached; personal drills are sorted by id.
    static func entries(library: [LibraryActivity], personal: [DrillItem]) -> [DrillFinderEntry] {
        let lib = library.filter { !$0.isRule }.map { activity in
            DrillFinderEntry(
                drillId: activity.id, name: activity.name, nameZh: activity.nameZh ?? "",
                place: "\(activity.age.rawValue) · \(activity.block.rawValue) · \(activity.type.rawValue)",
                text: activity.howItRuns, textZh: activity.howItRunsZh ?? "", isPersonal: false)
        }
        let own = personal.sorted { $0.id.uuidString < $1.id.uuidString }.map { drill in
            DrillFinderEntry(
                drillId: drill.id, name: drill.name, nameZh: "",
                place: "Personal · \(drill.category.rawValue)",
                text: ([drill.description] + drill.instructions).filter { !$0.isEmpty }.joined(separator: " "),
                textZh: "", isPersonal: true)
        }
        return lib + own
    }

    /// The catalog for a list of drills the coach can see: library activities
    /// the store has, then personal drills.
    @MainActor
    static func entries(for drills: [DrillItem]) -> [DrillFinderEntry] {
        let stored = Set(drills.map(\.id))
        return entries(library: ActivityLibrary.shared.items.filter { stored.contains($0.id) },
                       personal: drills.filter { !$0.isLibraryDrill })
    }

    // MARK: - Typed search

    /// As-you-type search: every word typed appears somewhere in the fields
    /// (name, Chinese name, description, instructions), ignoring case and
    /// accents, in any order — "pass defend" finds "20 Passes, Keeping Off".
    /// Hanzi typed without spaces is matched as a whole.
    static func typedMatch(_ query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = fields.joined(separator: " ")
        return words.allSatisfy {
            haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static let textLimit = 320

    static func line(_ entry: DrillFinderEntry) -> String {
        let name = entry.nameZh.isEmpty ? entry.name : "\(entry.name) / \(entry.nameZh)"
        let text = entry.text.replacingOccurrences(of: "\n", with: " ")
        return "\(entry.ref) | \(entry.place) | \(name) | \(text.prefix(textLimit))"
    }

    // MARK: - Claude

    static let model = "claude-haiku-4-5"

    static let instructions = """
    You help a youth basketball coach find a drill in his library from a description. His descriptions \
    are from memory: names, numbers, team sizes and details may be off ("pass 10 times" for a game that \
    counts to 20). Match on how the drill WORKS — the activity, its rules, what players do, how it is \
    scored, who defends — not on exact words. Coaches may write in English or Chinese.

    Each catalog line is: id | age · block · type (or Personal · category) | name | how it runs.

    Return up to 6 drills, best first, using only ids from the catalog. For each, "why" says in at most \
    18 words what matches and, when it matters, what differs from the description (e.g. "counts to 20 \
    passes, not 10; the other team defends"). Leave out drills that only share a word. If nothing fits \
    well, return the closest few anyway and say so in "note" in one sentence; otherwise "note" is "".
    """

    /// The Messages API body: the library half of the system prompt is cached
    /// (it is ~35k tokens, far above Haiku 4.5's 4096-token minimum); personal
    /// drills follow the breakpoint so editing one never invalidates the cache.
    static func requestBody(description: String, entries: [DrillFinderEntry], chinese: Bool) -> [String: Any] {
        let library = entries.filter { !$0.isPersonal }.map(line).joined(separator: "\n")
        let personal = entries.filter(\.isPersonal).map(line).joined(separator: "\n")
        var system: [[String: Any]] = [
            ["type": "text", "text": instructions + "\n\nLIBRARY:\n" + library, "cache_control": ["type": "ephemeral"]],
        ]
        if !personal.isEmpty { system.append(["type": "text", "text": "PERSONAL DRILLS (his own):\n" + personal]) }
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "matches": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["id": ["type": "string"], "why": ["type": "string"]],
                        "required": ["id", "why"],
                        "additionalProperties": false,
                    ],
                ],
                "note": ["type": "string"],
            ],
            "required": ["matches", "note"],
            "additionalProperties": false,
        ]
        let language = chinese ? "Write \"why\" and \"note\" in Simplified Chinese." : "Write \"why\" and \"note\" in English."
        return [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": "The coach's description:\n\(description)\n\n\(language)"]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
    }

    /// Claude's answer → matches, keeping only ids the catalog really has.
    static func parse(_ data: Data, entries: [DrillFinderEntry]) throws -> DrillFinderResult {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = response["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let answer = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw DrillFinderError.unreadable
        }
        let byRef = Dictionary(entries.map { ($0.ref, $0.drillId) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let matches: [DrillFinderMatch] = (answer["matches"] as? [[String: Any]] ?? []).compactMap { item in
            guard let raw = item["id"] as? String,
                  let id = byRef[raw.trimmingCharacters(in: .whitespaces).lowercased().prefix(8).description],
                  seen.insert(id).inserted else { return nil }
            return DrillFinderMatch(drillId: id, why: (item["why"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return DrillFinderResult(matches: matches, note: (answer["note"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 source: .claude)
    }

    static func askClaude(description: String, entries: [DrillFinderEntry], chinese: Bool, key: String) async throws -> DrillFinderResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(description: description, entries: entries, chinese: chinese))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? "no details"
            throw DrillFinderError.http(status, message)
        }
        return try parse(data, entries: entries)
    }

    // MARK: - On device (no key, or no connection)

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "to", "of", "in", "on", "at", "for", "with", "while", "is", "are", "be", "it",
        "they", "their", "them", "each", "one", "then", "that", "this", "as", "by", "from", "who", "when", "where",
        "player", "team", "other", "opposite", "try", "get", "into", "up", "out", "so", "can", "must", "after",
        "until", "first", "again", "drill", "game", "where", "which", "there", "have", "has",
    ]

    /// Coaching synonyms folded onto one word, so "defends" meets "defence".
    private static let concepts: [String: String] = [
        "passing": "pass", "passes": "pass", "passed": "pass", "passer": "pass", "catch": "pass", "throw": "pass",
        "defend": "defence", "defends": "defence", "defending": "defence", "defense": "defence",
        "defender": "defence", "defenders": "defence", "defensive": "defence", "intercept": "defence",
        "steal": "defence", "guard": "defence",
        "scores": "score", "scoring": "score", "point": "score", "points": "score", "basket": "score",
        "shot": "shoot", "shots": "shoot", "shooting": "shoot", "shooter": "shoot",
        "dribbling": "dribble", "dribbles": "dribble", "dribbler": "dribble",
        "cones": "cone", "slides": "slide", "sliding": "slide", "shuffle": "slide",
        "relay": "race", "sprint": "race",
        "ten": "10", "five": "5", "three": "3", "four": "4", "two": "2", "twenty": "20",
    ]

    static func tokens(_ text: String) -> [String] {
        let lower = text.lowercased()
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = lower
        var out: [String] = []
        tagger.enumerateTags(in: lower.startIndex..<lower.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let raw = String(lower[range])
            for word in Set([raw, tag?.rawValue.lowercased() ?? raw]) {
                let word = concepts[word] ?? word
                if !stopWords.contains(word), word.count > 1 || word.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
                    out.append(word)
                }
            }
            return true
        }
        return out
    }

    /// Word match (BM25 over lemmas and synonyms) and sentence similarity,
    /// fused by rank. Good for "dribble around cones and race back"; weak for
    /// describing how a game works — that is what Claude is for.
    static func rankOnDevice(_ description: String, entries: [DrillFinderEntry], limit: Int = 8) -> DrillFinderResult {
        let chinese = description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let docs = entries.map { tokens($0.name + " " + $0.name + " " + $0.nameZh + " " + $0.text + " " + $0.textZh) }
        let query = tokens(description)
        let n = Double(max(docs.count, 1))
        let average = max(docs.map { Double($0.count) }.reduce(0, +) / n, 1)
        var documentFrequency: [String: Double] = [:]
        for doc in docs { for term in Set(doc) { documentFrequency[term, default: 0] += 1 } }
        let lexical: [Double] = docs.map { doc in
            var frequency: [String: Double] = [:]
            for term in doc { frequency[term, default: 0] += 1 }
            return Set(query).reduce(0) { sum, term in
                guard let f = frequency[term] else { return sum }
                let df = documentFrequency[term] ?? 0
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                return sum + idf * f * 2.2 / (f + 1.2 * (0.25 + 0.75 * Double(doc.count) / average))
            }
        }
        var fused = [Double](repeating: 0, count: entries.count)
        for (rank, i) in entries.indices.sorted(by: { lexical[$0] > lexical[$1] }).enumerated() where lexical[i] > 0 {
            fused[i] += 1 / (20 + Double(rank))
        }
        if let embedding = NLEmbedding.sentenceEmbedding(for: chinese ? .simplifiedChinese : .english),
           let queryVector = embedding.vector(for: description) {
            let similarity: [Double] = entries.map { entry in
                let text = chinese && !entry.textZh.isEmpty ? entry.nameZh + "。" + entry.textZh : entry.name + ". " + entry.text
                guard let vector = embedding.vector(for: String(text.prefix(400))) else { return -1 }
                return cosine(queryVector, vector)
            }
            for (rank, i) in entries.indices.sorted(by: { similarity[$0] > similarity[$1] }).enumerated() {
                fused[i] += 1 / (20 + Double(rank))
            }
        }
        let best = entries.indices.filter { fused[$0] > 0 }.sorted { fused[$0] > fused[$1] }.prefix(limit)
        return DrillFinderResult(matches: best.map { DrillFinderMatch(drillId: entries[$0].drillId, why: "") },
                                 note: "", source: .onDevice)
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, x = 0.0, y = 0.0
        for i in a.indices where i < b.count { dot += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i] }
        return dot / (x.squareRoot() * y.squareRoot() + 1e-9)
    }
}

/// The coach's Anthropic API key, in this Mac's Keychain (never synced, never
/// in the store). Set from the finder sheet.
nonisolated enum AnthropicKeyStore {
    private static let service = "com.hoopwise.anthropic"
    private static let account = "api-key"

    static var key: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        remove()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account,
                                   kSecValueData as String: Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
