import Foundation

// New Drill: the coach writes the description, presses Return, and Claude
// turns it into the drill's numbered Instructions and Key Points, which stay
// editable (Luther, November 2026). Same model, key and raw Messages call as
// DrillFinder (Swift has no Anthropic SDK). Only the drill's own text is sent.

nonisolated struct DrillWriterResult: Equatable {
    let instructions: [String]
    let keyPoints: [String]
    /// What the drill develops on the eight axes (DrillAttribute order).
    var attributes: [Int]? = nil
}

nonisolated enum DrillWriter {
    static let instructions = """
    You turn a basketball coach's description of a drill into what goes on its drill card. The coach \
    writes quickly and from memory; keep to what the description says and do not invent equipment, \
    numbers or rules it does not imply. Write in the same language as the description.

    "instructions": the drill as 2 to 7 steps in the order they happen — set-up first (where players \
    start, what equipment), then the action, then how a repetition ends and rotates. One short \
    imperative sentence each, no numbering.
    "keyPoints": 2 to 4 coaching points — what the coach watches for or corrects (technique, decision, \
    effort). Short phrases, no numbering.
    "attributes": how much the drill develops each of eight attributes, 0 to 3 (0 not involved, 1 touched \
    in passing, 2 worked, 3 a main focus), as eight integers in this order: ballHandling, passing, \
    shooting, finishing, playmaking, gameIQ, defense, footwork. Most drills have one or two 3s and zeros \
    elsewhere. The attributes:
    \(DrillAttribute.rubric)
    """

    static func requestBody(name: String, description: String, minPlayers: Int, minutes: Int) -> [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "instructions": ["type": "array", "items": ["type": "string"]],
                "keyPoints": ["type": "array", "items": ["type": "string"]],
                "attributes": ["type": "array", "items": ["type": "integer"]],
            ],
            "required": ["instructions", "keyPoints", "attributes"],
            "additionalProperties": false,
        ]
        var context = "Description:\n\(description)"
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { context = "Drill name: \(trimmedName)\n" + context }
        context += "\n\nAt least \(minPlayers) players; about \(minutes) minutes."
        return [
            "model": DrillFinder.model,
            "max_tokens": 1024,
            "system": instructions,
            "messages": [["role": "user", "content": context]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
    }

    static func parse(_ data: Data) throws -> DrillWriterResult {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = response["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let answer = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw DrillFinderError.unreadable
        }
        func lines(_ key: String) -> [String] {
            (answer[key] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let scores = (answer["attributes"] as? [Int]).flatMap { $0.count == DrillAttribute.allCases.count ? $0.map { max(0, min(3, $0)) } : nil }
        return DrillWriterResult(instructions: lines("instructions"), keyPoints: lines("keyPoints"), attributes: scores)
    }

    static func write(name: String, description: String, minPlayers: Int, minutes: Int, key: String) async throws -> DrillWriterResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            name: name, description: description, minPlayers: minPlayers, minutes: minutes))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? "no details"
            throw DrillFinderError.http(status, message)
        }
        return try parse(data)
    }

    /// Return in the description: the new text ends with a line break the old
    /// text did not have — the break itself is not kept.
    static func pressedReturn(old: String, new: String) -> String? {
        guard new.count == old.count + 1, new.hasSuffix("\n"), String(new.dropLast()) == old else { return nil }
        return old
    }

    /// Fill a list only when it is blank or still exactly what Claude wrote
    /// last time — never over the coach's own typing.
    static func mayReplace(_ current: [String], lastWritten: [String]?) -> Bool {
        let filled = current.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return filled.isEmpty || filled == lastWritten
    }
}
