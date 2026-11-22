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
    /// How the drill could be tracked, when it has a result worth logging
    /// (24 Nov 2026). Offered in the form; the coach takes it or not.
    var tracking: DrillWriterTracking? = nil
}

/// Claude's proposal for tracking a drill, as it answers it.
nonisolated struct DrillWriterTracking: Equatable {
    var kind: TrackKind
    var measure: TrackMeasure
    var amount: Int
    var unit: String
    var main: [DrillAttribute]
    var some: [DrillAttribute]
    var zones: [Int]
    var course: TrackCourse? = nil

    /// The kind's preset with what Claude read from the description on top.
    func definition(chinese: Bool) -> TrackDefinition {
        var d = kind.preset(measure: measure, chinese: chinese)
        if d.measure == .madeOf { d.amount = min(100, max(1, amount)) }
        if d.measure == .inTime { d.amount = min(1200, max(5, amount)) }
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty, d.measure == .inTime || d.measure == .count { d.unit = u }
        let m = main.filter { !some.contains($0) }
        if !m.isEmpty {
            d.skills = (m + some).map(\.rawValue)
            d.some = some.map(\.rawValue)
        }
        if kind.usesCourse, d.measure != .count, let course { d.course = course }
        if kind.usesShotMap {
            var seen = Set<Int>()
            d.zones = zones.filter { (0..<10).contains($0) && seen.insert($0).inserted }
        }
        return d
    }
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
    "tracking": how the coach could LOG a result for each athlete, or kind "none" when the drill has no \
    number worth recording (a game, a walkthrough, free play). Only what the description supports:
    - "kind": shooting (shots from the floor), finishing (lay-ups and shots at the rim), ballHandling, \
    passing, conditioning (running, sprints, laps), defense, other, or none.
    - "measure": madeOf (makes out of a fixed number of attempts), inTime (how many in a set time), \
    timeToFinish (a stopwatch time, faster is better), count (a plain number such as points or errors).
    - "amount": attempts for madeOf, seconds for inTime, else 0. Use the description's number; if it gives \
    none, 10 attempts or 60 seconds. When the shots are split over zones, the amount is PER ZONE ("20 \
    threes, 10 from each corner" is 10).
    - "unit": what is counted for inTime or count, one or two lower-case words in the description's \
    language ("passes", "laps"); "" otherwise.
    - "main": the one or two attributes (names from the list above) a result mainly measures; "some": at \
    most two it measures a little. Never the same attribute in both.
    - "zones": for kind shooting only, the shot-map zones the description names, as numbers: 0 at the rim, \
    1 left baseline mid-range, 2 left elbow, 3 right elbow, 4 right baseline mid-range, 5 left corner \
    three, 6 left wing three, 7 top three, 8 right wing three, 9 right corner three. [] when it names none.
    - "course": for kind conditioning or ballHandling, the distance the description names: halfCourt (to \
    half court, 14 m), fullCourt (baseline to baseline, 28 m), downAndBack (the full court and back), \
    lineDrill (suicides: to each line and back), seventeens (sideline to sideline 17 times), lap (around \
    the court); "none" when it names no such distance or for any other kind.
    """

    static func requestBody(name: String, description: String, minPlayers: Int, minutes: Int) -> [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "instructions": ["type": "array", "items": ["type": "string"]],
                "keyPoints": ["type": "array", "items": ["type": "string"]],
                "attributes": ["type": "array", "items": ["type": "integer"]],
                "tracking": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": TrackKind.allCases.map(\.rawValue) + ["none"]],
                        "measure": ["type": "string", "enum": TrackMeasure.allCases.map(\.rawValue)],
                        "amount": ["type": "integer"],
                        "unit": ["type": "string"],
                        "main": ["type": "array", "items": ["type": "string", "enum": DrillAttribute.allCases.map(\.rawValue)]],
                        "some": ["type": "array", "items": ["type": "string", "enum": DrillAttribute.allCases.map(\.rawValue)]],
                        "zones": ["type": "array", "items": ["type": "integer"]],
                        "course": ["type": "string", "enum": TrackCourse.allCases.map(\.rawValue) + ["none"]],
                    ],
                    "required": ["kind", "measure", "amount", "unit", "main", "some", "zones", "course"],
                    "additionalProperties": false,
                ] as [String: Any],
            ],
            "required": ["instructions", "keyPoints", "attributes", "tracking"],
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
        var tracking: DrillWriterTracking?
        if let t = answer["tracking"] as? [String: Any],
           let kind = (t["kind"] as? String).flatMap(TrackKind.init(rawValue:)),
           let measure = (t["measure"] as? String).flatMap(TrackMeasure.init(rawValue:)) {
            func axes(_ key: String) -> [DrillAttribute] {
                (t[key] as? [String] ?? []).compactMap(DrillAttribute.init(rawValue:))
            }
            tracking = DrillWriterTracking(kind: kind, measure: measure, amount: t["amount"] as? Int ?? 0,
                                           unit: t["unit"] as? String ?? "", main: axes("main"), some: axes("some"),
                                           zones: t["zones"] as? [Int] ?? [],
                                           course: (t["course"] as? String).flatMap(TrackCourse.init(rawValue:)))
        }
        return DrillWriterResult(instructions: lines("instructions"), keyPoints: lines("keyPoints"), attributes: scores,
                                 tracking: tracking)
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
