import Foundation

#if targetEnvironment(macCatalyst)
// MARK: - Claude Desktop connector: DRILLS (November 2026)
//
// Luther: "create a new category in the drills library called Personal. This is
// where Claude would drop new drills when I tell it to create new ones" — e.g.
// "Game simulation action series: Drive and kick". The library's "Mine" chip
// became "Personal": every drill that is not from the bundled activity library.
// Claude's drills are ordinary coach drills (owner = the coach, tagged
// `by:claude` for provenance), written through addDrill / updateDrill /
// deleteDrill like the app's own Add Drill sheet. Library drills are never
// edited or deleted from here — they are re-seeded from the bundle every launch.

extension ConnectorToolRegistry {
    private func drillSchema(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private var drillFields: [String: Any] {
        [
            "name": ["type": "string"],
            "category": ["type": "string", "enum": DrillCategory.allCases.map(\.rawValue),
                         "description": "What it trains most (default skills)"],
            "difficulty": ["type": "string", "enum": DifficultyLevel.allCases.map(\.rawValue)],
            "duration_minutes": ["type": "integer"],
            "description": ["type": "string", "description": "What the drill is and why — 1–3 sentences"],
            "instructions": ["type": "array", "items": ["type": "string"],
                             "description": "How it runs, one step or one progression per item, in order"],
            "key_points": ["type": "array", "items": ["type": "string"], "description": "Coaching points to watch"],
            "variations": ["type": "array", "items": ["type": "string"]],
            "equipment": ["type": "array", "items": ["type": "string"]],
            "min_players": ["type": "integer"],
            "max_players": ["type": "integer"],
        ]
    }

    private func findDrill(_ raw: String, personalOnly: Bool) throws -> DrillItem {
        if personalOnly, let library = try? findDrill(raw, personalOnly: false), library.isLibraryDrill {
            throw ConnectorToolError.ruleViolation("\(library.localizedName) is a library activity (re-seeded from the bundled library every launch), so it cannot be changed or deleted here. create_drill a personal version instead.")
        }
        let pool = dataManager.drills.filter { !personalOnly || !$0.isLibraryDrill }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = text.lowercased().replacingOccurrences(of: "-", with: "")
        if key.count >= 6 {
            let hits = pool.filter { $0.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(key) }
            if hits.count == 1 { return hits[0] }
        }
        let named = pool.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame
            || $0.localizedName.caseInsensitiveCompare(text) == .orderedSame }
        if named.count == 1 { return named[0] }
        let containing = pool.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.localizedName.localizedCaseInsensitiveContains(text) }
        if containing.count == 1 { return containing[0] }
        let candidates = (named.isEmpty ? containing : named).prefix(8).map { "\($0.localizedName) [\(Self.ref($0.id))]" }
        if candidates.isEmpty {
            throw ConnectorToolError.notFound("No \(personalOnly ? "personal " : "")drill matches \"\(text)\". Use list_drills.")
        }
        throw ConnectorToolError.badArguments("Several drills match \"\(text)\": \(candidates.joined(separator: ", ")). Pass a drill_id.")
    }

    private func strings(_ any: Any?) -> [String]? {
        (any as? [Any])?.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The tool's fields written onto a drill; only what was sent changes.
    private func apply(_ args: [String: Any], to drill: inout DrillItem) throws {
        if let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else { throw ConnectorToolError.badArguments("name cannot be empty") }
            drill.name = name
        }
        if let raw = args["category"] as? String {
            guard let category = DrillCategory(rawValue: raw.lowercased()) else {
                throw ConnectorToolError.badArguments("category: " + DrillCategory.allCases.map(\.rawValue).joined(separator: ", "))
            }
            drill.category = category
        }
        if let raw = args["difficulty"] as? String {
            guard let level = DifficultyLevel(rawValue: raw.lowercased()) else {
                throw ConnectorToolError.badArguments("difficulty: beginner, intermediate or advanced")
            }
            drill.difficulty = level
        }
        if let minutes = args["duration_minutes"] as? Int {
            guard (1...120).contains(minutes) else { throw ConnectorToolError.badArguments("duration_minutes: 1–120") }
            drill.durationMinutes = minutes
        }
        if let text = args["description"] as? String { drill.description = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let list = strings(args["instructions"]) { drill.instructions = list }
        if let list = strings(args["key_points"]) { drill.keyPoints = list }
        if let list = strings(args["variations"]) { drill.variations = list }
        if let list = strings(args["equipment"]) { drill.equipmentNeeded = list }
        if let n = args["min_players"] as? Int { drill.minPlayers = max(1, n) }
        if let n = args["max_players"] as? Int { drill.maxPlayers = n > 0 ? n : nil }
        drill.updatedAt = Date()
    }

    private func drillBrief(_ drill: DrillItem) -> [String: Any] {
        ["drill_id": Self.ref(drill.id), "name": drill.localizedName, "category": drill.category.rawValue,
         "duration_minutes": drill.durationMinutes, "personal": !drill.isLibraryDrill]
    }

    private func drillDetail(_ drill: DrillItem) -> [String: Any] {
        var out = drillBrief(drill)
        out["difficulty"] = drill.difficulty.rawValue
        out["description"] = drill.localizedDescription
        out["instructions"] = drill.instructions
        out["key_points"] = drill.keyPoints
        out["variations"] = drill.variations
        out["equipment"] = drill.equipmentNeeded
        out["min_players"] = drill.minPlayers
        if let max = drill.maxPlayers { out["max_players"] = max }
        return out
    }

    private enum PlanSection: String, CaseIterable { case warmup, skills }

    func drillTools() -> [ConnectorTool] {
        let drillRef: [String: Any] = ["type": "string", "description": "drill_id from list_drills (or the drill's exact name)"]
        let sessionFields: [String: Any] = [
            "session_id": ["type": "string"], "when": ["type": "string"], "program": ["type": "string"],
        ]
        return [
            ConnectorTool(
                name: "list_drills",
                description: "Drills in the coach's library. By default only PERSONAL drills (the coach's own and Claude's — the Personal chip in Drills); scope \"all\" includes the 422 bundled library activities. Optional query searches names and descriptions.",
                schema: drillSchema(["query": ["type": "string"],
                                     "scope": ["type": "string", "enum": ["personal", "all"]]], []),
                category: .read,
                run: { [self] args in
                    let all = (args["scope"] as? String) == "all"
                    let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                    let drills = dataManager.drills
                        .filter { all || !$0.isLibraryDrill }
                        .filter { query.isEmpty || [$0.name, $0.localizedName, $0.description].contains { $0.localizedCaseInsensitiveContains(query) } }
                        .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
                    return ConnectorToolResult(
                        payload: Self.encode(["count": drills.count, "drills": drills.prefix(60).map(drillBrief)]),
                        summary: "listed drills · \(drills.count)")
                }),

            ConnectorTool(
                name: "get_drill",
                description: "One drill in full: description, how it runs (instructions), key points, variations, equipment, players.",
                schema: drillSchema(["drill_id": drillRef], ["drill_id"]),
                category: .read,
                run: { [self] args in
                    let drill = try findDrill(args["drill_id"] as? String ?? "", personalOnly: false)
                    return ConnectorToolResult(payload: Self.encode(drillDetail(drill)), summary: "read \(drill.localizedName)")
                }),

            ConnectorTool(
                name: "create_drill",
                description: """
                Save a NEW drill in the coach's PERSONAL drills (Drills → Personal), e.g. from a session he describes \
                or a concept he shares. Give a clear name, a short description (what and why), instructions as \
                ordered steps or progressions (one per item — a series of variations of one drill is one drill \
                with one instruction per progression), key points, duration and category. It can then go in \
                session plans (add_drill_to_session). Check list_drills first so you do not make a duplicate — \
                update_drill an existing one instead.
                """,
                schema: drillSchema(drillFields, ["name"]),
                category: .sessionWrite,
                run: { [self] args in
                    let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { throw ConnectorToolError.badArguments("name is required") }
                    if let twin = dataManager.drills.first(where: { !$0.isLibraryDrill && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        throw ConnectorToolError.ruleViolation("A personal drill is already called \"\(name)\" [\(Self.ref(twin.id))] — update_drill it, or choose another name.")
                    }
                    let owner = dataManager.loggedInCoachId ?? dataManager.coach.id
                    var drill = DrillItem(name: name, category: .skills,
                                          tags: ["visibility:private", "owner:\(owner.uuidString)", "by:claude"])
                    try apply(args, to: &drill)
                    dataManager.addDrill(drill)
                    return ConnectorToolResult(payload: Self.encode(drillDetail(drill).merging(["saved_in": "Drills → Personal"]) { $1 }),
                                               summary: "created drill \(drill.name)")
                }),

            ConnectorTool(
                name: "update_drill",
                description: "Change a PERSONAL drill: any of its fields (lists given replace the old list). Library activities cannot be edited here.",
                schema: drillSchema(drillFields.merging(["drill_id": drillRef]) { $1 }, ["drill_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    var drill = try findDrill(args["drill_id"] as? String ?? "", personalOnly: true)
                    try apply(args, to: &drill)
                    dataManager.updateDrill(drill)
                    return ConnectorToolResult(payload: Self.encode(drillDetail(drill)), summary: "updated \(drill.name)")
                }),

            ConnectorTool(
                name: "delete_drill",
                description: "Delete a PERSONAL drill (its photos and videos go with it; session plans that used it simply lose it). Library activities cannot be deleted. It cannot be brought back.",
                schema: drillSchema(["drill_id": drillRef], ["drill_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let drill = try findDrill(args["drill_id"] as? String ?? "", personalOnly: true)
                    let plans = dataManager.sessionEvents.filter {
                        ($0.curriculum.warmupDrillIds + $0.curriculum.skillDrillIds + $0.curriculum.gameDrillIds).contains(drill.id)
                    }.count
                    dataManager.deleteDrill(drill)
                    return ConnectorToolResult(payload: Self.encode(["deleted": drill.name, "was_in_plans": plans]),
                                               summary: "deleted drill \(drill.name)")
                },
                destructive: true),

            ConnectorTool(
                name: "add_drill_to_session",
                description: "Put a drill (personal or library) in a session's plan, in its Warm-up or Skills section, at the end.",
                schema: drillSchema(sessionFields.merging([
                    "drill_id": drillRef,
                    "section": ["type": "string", "enum": PlanSection.allCases.map(\.rawValue)],
                ]) { $1 }, ["drill_id", "section"]),
                category: .sessionWrite,
                run: { [self] args in
                    let drill = try findDrill(args["drill_id"] as? String ?? "", personalOnly: false)
                    guard let section = PlanSection(rawValue: (args["section"] as? String ?? "").lowercased()) else {
                        throw ConnectorToolError.badArguments("section: warmup or skills")
                    }
                    var session = try findSession(args)
                    let already = session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds
                    guard !already.contains(drill.id) else {
                        throw ConnectorToolError.ruleViolation("\(drill.localizedName) is already in \(session.title)'s plan.")
                    }
                    switch section {
                    case .warmup: session.curriculum.warmupDrillIds.append(drill.id)
                    case .skills: session.curriculum.skillDrillIds.append(drill.id)
                    }
                    session.updatedAt = Date()
                    // Plan only: games, marks and the photo keep the store's values.
                    dataManager.updateSessionEvent(session, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["added": drill.localizedName, "section": section.rawValue,
                                                                     "session": session.title]),
                                               summary: "added \(drill.localizedName) to \(session.title)")
                }),

            ConnectorTool(
                name: "remove_drill_from_session",
                description: "Take a drill out of a session's plan. The drill stays in the library.",
                schema: drillSchema(sessionFields.merging(["drill_id": drillRef]) { $1 }, ["drill_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let drill = try findDrill(args["drill_id"] as? String ?? "", personalOnly: false)
                    var session = try findSession(args)
                    let before = session.curriculum.totalDrillCount
                    session.curriculum.warmupDrillIds.removeAll { $0 == drill.id }
                    session.curriculum.skillDrillIds.removeAll { $0 == drill.id }
                    session.curriculum.gameDrillIds.removeAll { $0 == drill.id }
                    guard session.curriculum.totalDrillCount < before else {
                        throw ConnectorToolError.notFound("\(drill.localizedName) is not in \(session.title)'s plan.")
                    }
                    session.updatedAt = Date()
                    dataManager.updateSessionEvent(session, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["removed": drill.localizedName, "session": session.title]),
                                               summary: "removed \(drill.localizedName) from \(session.title)")
                }),
        ]
    }
}
#endif
