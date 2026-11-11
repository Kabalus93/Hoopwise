import Foundation

// Claude rates what drills develop on the eight DrillAttribute axes.
// The library is rated ONCE (DEBUG HOOPWISE_SHOT=rateLibrary on the Mac demo
// copy logs every rating; tools/attributes/merge.py writes
// ActivityLibraryAttributes.swift). Personal drills are rated by DrillWriter
// when the coach presses Return in the description.

nonisolated enum DrillRater {
    /// Sonnet for the one-time library pass — the ratings ship to everyone.
    static let libraryModel = "claude-sonnet-5"

    static let instructions = """
    You rate basketball drills for a youth coaching app: for each drill, how much it develops each of \
    eight attributes, 0 to 3 — 0 not involved, 1 touched in passing (it happens but is not the point), \
    2 worked (a real part of the drill), 3 a main focus (what the drill is for). Most drills have one or \
    two 3s, a couple of 2s or 1s, and zeros elsewhere; do not spread points evenly, and do not give a 3 \
    to an attribute that only happens incidentally. Judge from how the drill actually runs.

    The attributes:
    \(DrillAttribute.rubric)

    Each drill line is: ref | age · block · type | name | how it runs.
    Return one rating per ref, with "scores" as eight integers in this order: \
    ballHandling, passing, shooting, finishing, playmaking, gameIQ, defense, footwork.
    """

    struct Item { let ref: String; let line: String }

    static func requestBody(items: [Item], model: String = libraryModel) -> [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "ratings": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "ref": ["type": "string"],
                            "scores": ["type": "array", "items": ["type": "integer"]],
                        ],
                        "required": ["ref", "scores"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["ratings"],
            "additionalProperties": false,
        ]
        return [
            "model": model,
            "max_tokens": 8000,
            "system": instructions,
            "messages": [["role": "user", "content": items.map(\.line).joined(separator: "\n")]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
    }

    /// ref → eight scores, clamped; refs not asked for and wrong lengths dropped.
    static func parse(_ data: Data, refs: Set<String>) throws -> [String: [Int]] {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = response["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let answer = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw DrillFinderError.unreadable
        }
        var out: [String: [Int]] = [:]
        for item in answer["ratings"] as? [[String: Any]] ?? [] {
            guard let ref = (item["ref"] as? String)?.trimmingCharacters(in: .whitespaces), refs.contains(ref),
                  let scores = item["scores"] as? [Int], scores.count == DrillAttribute.allCases.count else { continue }
            out[ref] = scores.map { max(0, min(3, $0)) }
        }
        return out
    }

    static func rate(items: [Item], key: String) async throws -> [String: [Int]] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(items: items))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? "no details"
            throw DrillFinderError.http(status, message)
        }
        return try parse(data, refs: Set(items.map(\.ref)))
    }

    /// A library activity as one line.
    static func line(ref: String, _ activity: LibraryActivity) -> String {
        let text = activity.howItRuns.replacingOccurrences(of: "\n", with: " ")
        return "\(ref) | \(activity.age.rawValue) · \(activity.block.rawValue) · \(activity.type.rawValue) | \(activity.name) | \(text.prefix(600))"
    }
}
