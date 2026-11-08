import Foundation
import SwiftData

#if targetEnvironment(macCatalyst)
// MARK: - Claude Desktop connector: the PLAYS tools (November 2026)
//
// Luther: Claude should create plays and save them in his library — from a
// conversation, or from concepts, adjustments and plays he feeds it — "accurate
// and fully using the capabilities". Every handler is a thin wrapper over
// JournalPlayAuthoring (shared, tested on the simulator): validate everything,
// then write; the same drawing model the editor writes, so a play Claude makes
// opens, plays back and edits like one drawn by hand. No delete tools.

extension ConnectorToolRegistry {
    private var playContext: ModelContext { dataManager.modelContext }

    private func playSchema(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    /// The JSON Schema for a step list (kept loose: the guide describes the
    /// diagram, and the validator names any mistake precisely).
    private var stepsSchema: [String: Any] {
        [
            "type": "array",
            "description": "Steps in order. Each {caption, text, diagram}; a diagram carries over from the step before, so write only what changes.",
            "items": [
                "type": "object",
                "properties": [
                    "caption": ["type": "string", "description": "Short: \"Set\", \"Entry\", \"The read\"."],
                    "text": ["type": "string", "description": "What happens and what to read, 1–3 sentences."],
                    "diagram": diagramSchema,
                ],
            ],
        ]
    }

    private var diagramSchema: [String: Any] {
        let point: [String: Any] = ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2,
                                    "description": "[x, y] in metres"]
        return [
            "type": "object",
            "description": "See get_play_drawing_guide. Omitted fields carry over from the previous step's end.",
            "properties": [
                "offense": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["number": ["type": "integer"], "x": ["type": "number"], "y": ["type": "number"]],
                    "required": ["number", "x", "y"],
                ]],
                "defense": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["x": ["type": "number"], "y": ["type": "number"],
                                   "read": ["type": "boolean", "description": "The defender the ball handler reads"]],
                    "required": ["x", "y"],
                ]],
                "balls": ["type": "array", "items": ["type": "integer"],
                          "description": "Players holding a ball when the step starts; several for a drill"],
                "actions": ["type": "array", "description": "In the order they happen.", "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["cut", "dribble", "pass", "shot", "screen"]],
                        "player": ["type": "integer"],
                        "path": ["type": "array", "items": point,
                                 "description": "cut/dribble/screen: where the player goes ([[x,y]]) or bends then the end"],
                        "to": ["type": "integer", "description": "pass: the receiver's number"],
                        "shape": ["type": "string", "enum": ["straight", "curved"]],
                    ],
                    "required": ["kind", "player"],
                ]],
                "notes": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["text": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"]],
                    "required": ["text", "x", "y"],
                ]],
            ],
        ]
    }

    private func result(_ play: JournalPlay, verb: String, warnings: [String], extra: [String: Any] = [:]) -> ConnectorToolResult {
        var payload = JournalPlayAuthoring.brief(play)
        if !warnings.isEmpty { payload["warnings"] = warnings }
        payload["next"] = "Read it back with get_play to check the drawing; the coach sees it in Hub → Plays."
        for (key, value) in extra { payload[key] = value }
        return ConnectorToolResult(payload: Self.encode(payload), summary: "\(verb) \(play.name)")
    }

    private func findPlay(_ args: [String: Any]) throws -> JournalPlay {
        do { return try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext) } catch let error as JournalPlayAuthoringError {
            throw ConnectorToolError.notFound(error.localizedDescription)
        }
    }

    private func wrap(_ body: () throws -> ConnectorToolResult) throws -> ConnectorToolResult {
        do { return try body() } catch let error as JournalPlayAuthoringError {
            throw ConnectorToolError.badArguments(error.localizedDescription)
        }
    }

    func playTools() -> [ConnectorTool] {
        let partProperty: [String: Any] = ["description": "\"concept\" (default), the part's number from get_play, or its name"]
        let playProperty: [String: Any] = ["type": "string", "description": "play_id from list_plays (or the play's exact name)"]
        return [
            ConnectorTool(
                name: "get_play_drawing_guide",
                description: "READ THIS FIRST before creating or changing a play: the court coordinates and landmarks (metres), what a play, part and step are, the diagram format (players, defenders, balls, cut/dribble/pass/shot/screen, straight or curved lines, notes), how steps carry over and how playback runs.",
                schema: playSchema([:], []),
                category: .read,
                run: { _ in ConnectorToolResult(payload: JournalPlayAuthoring.guide, summary: "read the play drawing guide") }),

            ConnectorTool(
                name: "list_plays",
                description: "The coach's play library (Hub → Plays): play_id, name, category, court, situation and size. Optional query filters by name, situation or concept.",
                schema: playSchema(["query": ["type": "string"]], []),
                category: .read,
                run: { [self] args in
                    let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                    let plays = JournalPlayAuthoring.allPlays(in: playContext).filter { play in
                        query.isEmpty || [play.name, play.situation, play.concept].contains { $0.localizedCaseInsensitiveContains(query) }
                    }
                    return ConnectorToolResult(
                        payload: Self.encode(["count": plays.count, "plays": plays.map(JournalPlayAuthoring.brief)]),
                        summary: "listed plays · \(plays.count)")
                }),

            ConnectorTool(
                name: "get_play",
                description: "One play in full, in the same format create_play takes: details, then every part (1 = concept, then wrinkles and variations) with every step's caption, text and diagram. Use it to study a play, to see the format filled in, or before changing one.",
                schema: playSchema(["play_id": playProperty], ["play_id"]),
                category: .read,
                run: { [self] args in
                    try wrap {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext)
                        return ConnectorToolResult(payload: Self.encode(JournalPlayAuthoring.describe(play)),
                                                   summary: "read \(play.name)")
                    }
                }),

            ConnectorTool(
                name: "create_play",
                description: "Save a new play in the coach's library, drawn step by step, with optional wrinkles and variations. Call get_play_drawing_guide first. Everything is checked before anything is saved; a mistake comes back naming the field. Warnings (saved, but probably not meant) come back too — fix them with update_play_step.",
                schema: playSchema([
                    "name": ["type": "string"],
                    "category": ["type": "string", "enum": ["transition", "half_court", "baseline_inbound", "sideline_inbound", "versus_man", "other"]],
                    "court": ["type": "string", "enum": ["half", "full"]],
                    "situation": ["type": "string", "description": "When it's run, e.g. \"After a made basket against a 2-3 zone\""],
                    "concept": ["type": "string", "description": "The idea and the roles"],
                    "concept_name": ["type": "string", "description": "Name of the base action if it differs from the play's"],
                    "source": ["type": "string", "description": "Where it comes from (a coach, a clinic, a video, \"Conversation with Claude\")"],
                    "source_url": ["type": "string"],
                    "steps": stepsSchema,
                    "wrinkles": ["type": "array", "items": ["type": "object", "properties": [
                        "name": ["type": "string"], "notes": ["type": "string"], "steps": stepsSchema]]],
                    "variations": ["type": "array", "items": ["type": "object", "properties": [
                        "name": ["type": "string"], "notes": ["type": "string"], "steps": stepsSchema]]],
                ], ["name", "steps"]),
                category: .playWrite,
                run: { [self] args in
                    try wrap {
                        let made = try JournalPlayAuthoring.createPlay(args, in: playContext)
                        return result(made.play, verb: "created", warnings: made.warnings)
                    }
                }),

            ConnectorTool(
                name: "update_play",
                description: "Change a play's details: name, category, situation, concept, source, source_url, or court (changing the court turns every drawing to the new court). Only the fields given change.",
                schema: playSchema([
                    "play_id": playProperty,
                    "name": ["type": "string"],
                    "category": ["type": "string", "enum": ["transition", "half_court", "baseline_inbound", "sideline_inbound", "versus_man", "other"]],
                    "court": ["type": "string", "enum": ["half", "full"]],
                    "situation": ["type": "string"], "concept": ["type": "string"],
                    "source": ["type": "string"], "source_url": ["type": "string"],
                ], ["play_id"]),
                category: .playWrite,
                run: { [self] args in
                    try wrap {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext)
                        try JournalPlayAuthoring.updatePlay(play, args, in: playContext)
                        return result(play, verb: "updated", warnings: [])
                    }
                }),

            ConnectorTool(
                name: "add_play_part",
                description: "Add a wrinkle (a small change the defence doesn't expect) or a variation (another way into the same idea) to a play. Its first step starts from the concept's set.",
                schema: playSchema([
                    "play_id": playProperty,
                    "kind": ["type": "string", "enum": ["wrinkle", "variation"]],
                    "name": ["type": "string"], "notes": ["type": "string"],
                    "steps": stepsSchema,
                ], ["play_id", "kind", "name", "steps"]),
                category: .playWrite,
                run: { [self] args in
                    try wrap {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext)
                        let (part, warnings) = try JournalPlayAuthoring.addPart(to: play, args, in: playContext)
                        let number = (play.sortedParts.firstIndex { $0 === part } ?? 0) + 1
                        return result(play, verb: "added \(part.name) to", warnings: warnings, extra: ["part": number])
                    }
                }),

            ConnectorTool(
                name: "add_play_step",
                description: "Add a step to a part of a play. It carries over from the step it follows (after_step, 1-based; 0 = first; default: the end), so give only what changes.",
                schema: playSchema([
                    "play_id": playProperty,
                    "part": partProperty,
                    "after_step": ["type": "integer"],
                    "caption": ["type": "string"], "text": ["type": "string"],
                    "diagram": diagramSchema,
                ], ["play_id"]),
                category: .playWrite,
                run: { [self] args in
                    try wrap {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext)
                        let part = try JournalPlayAuthoring.part(args["part"], of: play)
                        let (step, warnings) = try JournalPlayAuthoring.addStep(
                            to: part, after: JournalPlayAuthoring.int(args["after_step"]), args, in: playContext)
                        return result(play, verb: "added a step to", warnings: warnings,
                                      extra: ["part": part.name, "step": step.order + 1])
                    }
                }),

            ConnectorTool(
                name: "update_play_step",
                description: "Change one step: caption, text, and/or its diagram. Diagram fields given REPLACE the step's own (e.g. a new actions list); fields left out stay. Later steps are not moved — update them too if positions should follow.",
                schema: playSchema([
                    "play_id": playProperty,
                    "part": partProperty,
                    "step": ["type": "integer", "description": "1-based"],
                    "caption": ["type": "string"], "text": ["type": "string"],
                    "diagram": diagramSchema,
                ], ["play_id", "step"]),
                category: .playWrite,
                run: { [self] args in
                    try wrap {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: playContext)
                        let part = try JournalPlayAuthoring.part(args["part"], of: play)
                        let steps = part.sortedSteps
                        guard let n = JournalPlayAuthoring.int(args["step"]), steps.indices.contains(n - 1) else {
                            throw JournalPlayAuthoringError.invalid("step: 1–\(steps.count) in \(part.name).")
                        }
                        let warnings = try JournalPlayAuthoring.updateStep(steps[n - 1], args, in: playContext)
                        return result(play, verb: "updated step \(n) of", warnings: warnings, extra: ["part": part.name, "step": n])
                    }
                }),

            ConnectorTool(
                name: "add_play_to_session",
                description: "Put a play in a session's training plan (the session page's Plays card). Name the session by session_id from list_sessions, or by when (ISO start) + program.",
                schema: playSchema([
                    "play_id": playProperty,
                    "session_id": ["type": "string"],
                    "when": ["type": "string"], "program": ["type": "string"],
                ], ["play_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let found = try findPlay(args)
                    var session = try findSession(args)
                    let ref = found.planRef
                    if session.curriculum.plays.contains(where: { found.isNamed(by: $0) }) {
                        return ConnectorToolResult(payload: Self.encode(["already_in_plan": true, "session": session.title]),
                                                   summary: "\(found.name) already in \(session.title)")
                    }
                    session.curriculum.plays.append(ref)
                    session.updatedAt = Date()
                    // Plan only: games, marks and the photo keep the store's values.
                    dataManager.updateSessionEvent(session, keepLiveFields: true)
                    return ConnectorToolResult(
                        payload: Self.encode(["added": found.name, "session": session.title,
                                              "plays_in_plan": session.curriculum.plays.map(\.name)]),
                        summary: "added \(found.name) to \(session.title)")
                }),
        ]
    }
}
#endif
