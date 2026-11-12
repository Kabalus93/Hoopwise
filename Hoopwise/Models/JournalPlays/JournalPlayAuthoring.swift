import Foundation
import SwiftData

// Plays written from a description instead of a finger (November 2026,
// Luther: Claude should create plays and save them in the library from our
// conversations, or from concepts, adjustments and plays he feeds it — "accurate
// and fully using the capabilities"). The Claude Desktop connector's play tools
// are thin wrappers over this; it is shared and pure-ish (a ModelContext in,
// models out) so it is tested on the simulator like the rest of Plays.
//
// THE FORMAT is the drawing model itself, in metres on the play's court, with
// three conveniences so a written play stays coherent:
// 1. A step CARRIES OVER from the step before (everyone where their moves
//    ended, the ball passed on): only what changes need be written.
// 2. A move's path may be just its destination; it starts where the player is.
// 3. A pass names its receiver ("to": 4) and a shot names nothing; both are
//    drawn from where the players are at that moment, exactly as the editor
//    snaps them.
// Everything is validated first and written second, so a mistake never leaves
// half a play in the library. No deletes (the connector's rule).

enum JournalPlayAuthoringError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let detail): detail }
    }
}

@MainActor
enum JournalPlayAuthoring {
    private typealias P = JournalCourtPoint
    private typealias D = JournalPlayDiagram

    /// Players and marks may stand this far outside the lines (an inbounder).
    static let outOfBounds = 1.3

    // MARK: - The guide (what a writer needs to know)

    static let guide = """
    HOOPWISE PLAY DRAWING — how to write a play the app draws and animates.

    COURTS (metres, FIBA):
    • half: x 0–15 across the floor (left sideline → right sideline), y 0–14 from the baseline (y 0) to half court (y 14). \
    Basket (7.5, 1.575). Lane x 5.05–9.95, from the baseline to the free-throw line at y 5.8. Blocks (5.05, 2.5) / (9.95, 2.5). \
    Elbows (5.05, 5.8) / (9.95, 5.8). Three-point arc radius 6.75 from the basket; corner threes at x 0.9 / 14.1 up to y 3. \
    Usual spots: top of the key (7.5, 9.6), wings (2.4, 6.6) / (12.6, 6.6), corners (1.1, 1.2) / (13.9, 1.2), \
    slot/guard spots (4.5, 8.8) / (10.5, 8.8), short corners (3.2, 1.5) / (11.8, 1.5).
    • full: x 0–28 along the floor ATTACKING RIGHT (own baseline x 0, the basket attacked at (26.425, 7.5), own basket (1.575, 7.5)), \
    y 0–15 across. Half-court line x 14. Free-throw lines x 5.8 and 22.2; lanes y 5.05–9.95.
    Players may stand up to 1.3 m outside the lines (an inbounder on the baseline: half y ≈ −0.7).

    A PLAY = name, category (transition | half_court | baseline_inbound | sideline_inbound | versus_man | other), court (half | full), \
    situation ("when it's run"), concept (the idea and the roles), source, then PARTS: the concept's steps, and optional wrinkles \
    (a small change the defence doesn't expect) and variations (another way into the same idea), each with its own steps.

    A STEP = caption (short: "Set", "Entry", "The read"), text (what happens, what to read — 1–3 sentences), diagram.

    DIAGRAM (every field optional — omitted fields CARRY OVER from the previous step's end: players where their moves ended, \
    the ball passed on, defenders where they were; a part's first step starts from the concept's set):
    • offense: [{"number": 1, "x": 7.5, "y": 9.6}, …] — numbers are roles (1 point, 2 shooting guard, 3 small forward, 4 power forward, 5 centre). \
    Usually 5; a drill may use more players (numbers up to 99). Giving offense REPLACES everyone's positions.
    • defense: [{"x": 7.5, "y": 7.8, "read": true}] — drawn as X; "read" marks THE defender the ball handler reads (amber; usually one).
    • balls: [1] — who holds a ball when the step starts. A play has one; a drill may give several players one each ([1, 2, 3]).
    • actions: in the ORDER THEY HAPPEN (write a cut, then the pass to the cutter). Each {"kind", "player", …}:
      – cut: the player runs. "path": [[x, y]] (destination) or [[x1, y1], [x2, y2]] (via a bend). Optional "shape": straight | curved.
      – dribble: the ball handler dribbles along "path" (same as cut). A dribble that ends at the rim is drawn red (a drive).
      – screen: the player goes to "path"'s end and sets a screen there (a bar), angled along the last segment.
      – pass: {"kind": "pass", "player": 1, "to": 4} — from where 1 is to where 4 is at that moment. No path.
      – shot: {"kind": "shot", "player": 2} — a red line into the nearest rim. No path. The ball leaves play.
      – handoff: {"kind": "handoff", "player": 5, "to": 2} — 5 hands the ball to 2 (a line ending in a double bar);     write the moves that bring them together first (5 dribbles over, 2 cuts around). No path.
      A path starts where the player is (after their earlier moves in this step); give only where they go. \
    "straight" draws straight segments with corners at the bends; "curved" one smooth curve through them (default: straight \
    for one point, curved for bends). A player's later move starts where their earlier one ended (screen, then roll).
    • defense_mode: "man" | "2-3" | "3-2" | "off" — AUTO DEFENSE: defenders are placed for you and follow the offense in \
    playback (man: matched to the nearest player, one each, ball–you–man positions, and on every screen the two defenders \
    SWITCH; zones shift toward the ball). Set it on the first step; later steps carry it. With it on, do not give "defense".
    • notes: [{"text": "Rebound", "x": 3.5, "y": 4}] — a word or two written on the court; a single character is drawn large (①).

    PLAYBACK follows the order the actions are written, each as soon as it can: everyone free moves at once; a pass leaves \
    when the passer is free and has the ball (written before their own cut = pass and cut; after their dribble = drive and \
    kick); a pass to someone whose cut was written EARLIER is a lead pass, landing as they arrive; a receiver waits for the \
    catch before any move written after it. Split a play into steps where the coach would pause to explain.

    GOOD HABITS: one idea per step; 2–5 steps for a concept; captions a coach would say aloud; keep players at least ~1.5 m apart; \
    put defenders between their man and the basket; read get_play on an existing play to see the format filled in.
    """

    // MARK: - Ids

    /// A play's id for a caller: its starter key, else "p" + its creation
    /// moment in base 36 (short enough not to be mis-copied).
    static func playID(_ play: JournalPlay) -> String {
        if let key = play.starterKey { return key }
        let ms = Int64((play.createdAt.timeIntervalSince1970 * 1000).rounded())
        return "p" + String(ms, radix: 36)
    }

    static func allPlays(in context: ModelContext) -> [JournalPlay] {
        let plays = (try? context.fetch(FetchDescriptor<JournalPlay>())) ?? []
        return plays.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    /// The play a caller meant: its id, else its exact name, else the one
    /// name containing the text. Fails naming what was sent and candidates.
    static func find(_ raw: String, in context: ModelContext) throws -> JournalPlay {
        let plays = allPlays(in: context)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'`")))
        if let hit = plays.first(where: { playID($0).caseInsensitiveCompare(text) == .orderedSame }) { return hit }
        let named = plays.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame }
        if named.count == 1 { return named[0] }
        let containing = plays.filter { $0.name.localizedCaseInsensitiveContains(text) }
        if containing.count == 1, named.isEmpty { return containing[0] }
        let candidates = (named.isEmpty ? (containing.isEmpty ? plays : containing) : named).prefix(10)
            .map { "\(playID($0)) — \($0.name)" }.joined(separator: "; ")
        throw JournalPlayAuthoringError.invalid("No single play matches \"\(text)\". Plays: \(candidates)")
    }

    /// A part: "concept" (or nothing), its 1-based number among the play's
    /// parts, or its name.
    static func part(_ raw: Any?, of play: JournalPlay) throws -> JournalPlayPart {
        let parts = play.sortedParts
        if raw == nil || (raw as? String)?.lowercased() == "concept" {
            guard let concept = play.conceptPart else { throw JournalPlayAuthoringError.invalid("This play has no concept.") }
            return concept
        }
        if let n = int(raw) {
            guard parts.indices.contains(n - 1) else {
                throw JournalPlayAuthoringError.invalid("part \(n): the play has \(parts.count) parts (1 is the concept).")
            }
            return parts[n - 1]
        }
        if let name = raw as? String, let hit = parts.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return hit
        }
        let names = parts.enumerated().map { "\($0 + 1) \($1.kind.rawValue) \"\($1.name)\"" }.joined(separator: "; ")
        throw JournalPlayAuthoringError.invalid("No part \"\(raw ?? "")\". Parts: \(names)")
    }

    // MARK: - Reading what was sent

    static func int(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// [x, y], {"x": …, "y": …}, or {"at": {…}}.
    private static func point(_ any: Any?, _ label: String, court: JournalCourtKind) throws -> P {
        var p: P?
        if let pair = any as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) { p = P(x, y) }
        if let dict = any as? [String: Any] {
            if let x = number(dict["x"]), let y = number(dict["y"]) { p = P(x, y) }
            else if let at = dict["at"] { return try point(at, label, court: court) }
        }
        guard let p else {
            throw JournalPlayAuthoringError.invalid("\(label): a point is [x, y] or {\"x\": …, \"y\": …} in metres.")
        }
        let size = court.size
        guard (-outOfBounds...(size.width + outOfBounds)).contains(p.x),
              (-outOfBounds...(size.height + outOfBounds)).contains(p.y) else {
            throw JournalPlayAuthoringError.invalid(
                "\(label): (\(p.x), \(p.y)) is off the \(court.rawValue) court (x 0–\(Int(size.width)), y 0–\(Int(size.height)), up to \(outOfBounds) m outside).")
        }
        return p
    }

    static func category(_ raw: Any?) throws -> JournalPlayCategory? {
        guard let text = raw as? String else { return nil }
        let key = text.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        let aliases: [String: JournalPlayCategory] = [
            "transition": .transition, "fastbreak": .transition, "halfcourt": .halfCourt,
            "baselineinbound": .baselineInbound, "blob": .baselineInbound, "sidelineinbound": .sidelineInbound,
            "slob": .sidelineInbound, "versusman": .versusMan, "againstman": .versusMan, "againstmantoman": .versusMan,
            "man": .versusMan, "other": .other,
        ]
        guard let category = aliases[key] else {
            throw JournalPlayAuthoringError.invalid("category \"\(text)\": transition, half_court, baseline_inbound, sideline_inbound, versus_man or other.")
        }
        return category
    }

    static func court(_ raw: Any?) throws -> JournalCourtKind? {
        guard let text = raw as? String else { return nil }
        switch text.lowercased() {
        case "half", "halfcourt", "half_court": return .half
        case "full", "fullcourt", "full_court": return .full
        default: throw JournalPlayAuthoringError.invalid("court \"\(text)\": half or full.")
        }
    }

    // MARK: - A diagram from its description

    /// `spec` applied to `base` (the step it carries over from). Returns the
    /// drawing and warnings (things that draw but are probably not meant).
    static func diagram(_ spec: [String: Any]?, base: JournalPlayDiagram, court: JournalCourtKind,
                        label: String) throws -> (JournalPlayDiagram, [String]) {
        var d = base
        var warnings: [String] = []
        guard let spec else { return (d, warnings) }

        if let offense = spec["offense"] {
            guard let list = offense as? [Any] else { throw JournalPlayAuthoringError.invalid("\(label).offense: a list of players.") }
            d.offense = try list.enumerated().map { i, item in
                guard let player = item as? [String: Any], let n = int(player["number"]), (1...99).contains(n) else {
                    throw JournalPlayAuthoringError.invalid("\(label).offense[\(i)]: {\"number\": 1–99, \"x\": …, \"y\": …}.")
                }
                return D.Player(number: n, at: try point(player, "\(label).offense[\(i)] (player \(n))", court: court))
            }
            let numbers = d.offense.map(\.number)
            if Set(numbers).count != numbers.count {
                throw JournalPlayAuthoringError.invalid("\(label).offense: each number once (got \(numbers)).")
            }
            if d.offense.isEmpty { throw JournalPlayAuthoringError.invalid("\(label).offense: at least one player.") }
            // Old lines started where the players were; new positions start fresh.
            if spec["actions"] == nil { d.actions = [] }
        }

        if let defense = spec["defense"] {
            guard let list = defense as? [Any] else { throw JournalPlayAuthoringError.invalid("\(label).defense: a list of defenders.") }
            d.defense = try list.enumerated().map { i, item in
                let at = try point(item, "\(label).defense[\(i)]", court: court)
                let read = ((item as? [String: Any])?["read"] as? NSNumber)?.boolValue ?? false
                return D.Defender(at: at, isRead: read)
            }
        }

        if let balls = spec["balls"] ?? spec["ball"] {
            let holders: [Int]
            if balls is NSNull { holders = [] }
            else if let one = int(balls) { holders = [one] }
            else if let list = balls as? [Any] {
                holders = try list.map {
                    guard let n = int($0) else { throw JournalPlayAuthoringError.invalid("\(label).balls: player numbers.") }
                    return n
                }
            } else { throw JournalPlayAuthoringError.invalid("\(label).balls: a list of player numbers.") }
            for n in holders where d.player(n) == nil {
                throw JournalPlayAuthoringError.invalid("\(label).balls: no player \(n) on the floor (players: \(d.offense.map(\.number))).")
            }
            if Set(holders).count != holders.count {
                throw JournalPlayAuthoringError.invalid("\(label).balls: one ball per player.")
            }
            d.balls = holders
        }

        if let notes = spec["notes"] {
            guard let list = notes as? [Any] else { throw JournalPlayAuthoringError.invalid("\(label).notes: a list.") }
            d.notes = try list.enumerated().map { i, item in
                guard let note = item as? [String: Any], let text = note["text"] as? String,
                      !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw JournalPlayAuthoringError.invalid("\(label).notes[\(i)]: {\"text\": …, \"x\": …, \"y\": …}.")
                }
                if text.count > 14 { warnings.append("\(label).notes[\(i)]: \"\(text)\" is long for the court; a word or two reads best.") }
                return D.Note(text: text, at: try point(note, "\(label).notes[\(i)]", court: court))
            }
        }

        if let actions = spec["actions"] {
            guard let list = actions as? [Any] else { throw JournalPlayAuthoringError.invalid("\(label).actions: a list.") }
            d.actions = []
            var holders = d.balls
            for (i, item) in list.enumerated() {
                let where_ = "\(label).actions[\(i)]"
                guard let a = item as? [String: Any], let kindText = a["kind"] as? String,
                      let kind = D.ActionKind(rawValue: kindText.lowercased()) else {
                    throw JournalPlayAuthoringError.invalid("\(where_).kind: cut, dribble, pass, handoff, shot or screen.")
                }
                guard let player = int(a["player"]), d.player(player) != nil else {
                    throw JournalPlayAuthoringError.invalid("\(where_).player: a number on the floor (players: \(d.offense.map(\.number))).")
                }
                // Where the player is now: after their moves so far.
                guard let from = JournalPlayMath.endPosition(of: player, in: d) else { continue }
                let action: D.Action
                switch kind {
                case .pass, .handoff:
                    guard let to = int(a["to"] ?? a["receiver"]), to != player, d.player(to) != nil,
                          let at = JournalPlayMath.endPosition(of: to, in: d) else {
                        throw JournalPlayAuthoringError.invalid("\(where_): a \(kind.rawValue) needs \"to\": a teammate's number (players: \(d.offense.map(\.number))).")
                    }
                    if from.distance(to: at) < JournalPlayMath.shortestAction {
                        throw JournalPlayAuthoringError.invalid("\(where_): \(player) and \(to) stand on the same spot; move one first.")
                    }
                    var start = from
                    if kind == .handoff, from.distance(to: at) > JournalPlayMath.handoffGap + 0.3 {
                        // A dribble hand-off: he dribbles over first, as in the editor.
                        let apart = from.distance(to: at)
                        let stop = JournalCourtPoint(at.x + (from.x - at.x) / apart * JournalPlayMath.handoffGap,
                                                     at.y + (from.y - at.y) / apart * JournalPlayMath.handoffGap)
                        d.actions.append(D.Action(kind: .dribble, player: player, path: [from, stop], shape: .straight))
                        start = stop
                        if !holders.contains(player), holders.count != 1 {
                            warnings.append("\(where_): \(player) dribbles without a ball (balls: \(holders)).")
                        }
                    }
                    action = D.Action(kind: kind, player: player, path: [start, at], receiver: to)
                case .shot:
                    let rim = court.baskets.min { $0.distance(to: from) < $1.distance(to: from) } ?? from
                    action = D.Action(kind: .shot, player: player, path: [from, rim])
                default:
                    guard let pathList = a["path"] as? [Any], !pathList.isEmpty else {
                        throw JournalPlayAuthoringError.invalid("\(where_): a \(kind.rawValue) needs \"path\": [[x, y]] (where they go), or bends then the end.")
                    }
                    var path = try pathList.enumerated().map { j, p in try point(p, "\(where_).path[\(j)]", court: court) }
                    // The line starts where the player is.
                    if path[0].distance(to: from) <= 0.6 { path[0] = from } else { path.insert(from, at: 0) }
                    guard JournalPlayMath.length(of: path) >= JournalPlayMath.shortestAction else {
                        throw JournalPlayAuthoringError.invalid("\(where_): the \(kind.rawValue) is shorter than \(JournalPlayMath.shortestAction) m; is the destination where the player already is?")
                    }
                    let shape: D.PathShape
                    switch (a["shape"] as? String)?.lowercased() {
                    case "straight": shape = .straight
                    case "curved": shape = .curved
                    case nil: shape = path.count > 2 ? .curved : .straight
                    case let other?: throw JournalPlayAuthoringError.invalid("\(where_).shape \"\(other)\": straight or curved.")
                    }
                    action = D.Action(kind: kind, player: player, path: path, shape: shape)
                    if kind == .dribble, !holders.contains(player) {
                        warnings.append("\(where_): \(player) dribbles without a ball (balls: \(holders)).")
                    }
                }
                if kind.throwsBall, !holders.contains(player), holders.count != 1 {
                    warnings.append("\(where_): \(player) \(kind == .shot ? "shoots" : "passes") without a ball at that moment (balls: \(holders)).")
                }
                if kind.throwsBall { JournalPlayMath.transfer(action, holders: &holders) }
                d.actions.append(action)
            }
        }

        // Auto defense: "defense_mode" matches the defenders here (man by
        // nearest; zones to their spots); without it a step carries the
        // previous step's mode, re-placed for where the offense now stands.
        if let raw = spec["defense_mode"] {
            if raw is NSNull || (raw as? String)?.lowercased() == "off" {
                d = JournalPlayMath.applyingDefense(nil, to: [d], court: court)[0]
            } else {
                let mode: D.DefenseMode
                switch (raw as? String)?.lowercased() {
                case "man": mode = .man
                case "2-3", "zone23": mode = .zone23
                case "3-2", "zone32": mode = .zone32
                default: throw JournalPlayAuthoringError.invalid("\(label).defense_mode: man, 2-3, 3-2 or off.")
                }
                d = JournalPlayMath.applyingDefense(mode, to: [d], court: court)[0]
            }
        } else {
            d = JournalPlayMath.placingDefense(d, court: court)
        }

        // Crowding: two players on the same spot read as one.
        for (i, a) in d.offense.enumerated() {
            for b in d.offense[(i + 1)...] where a.at.distance(to: b.at) < 0.9 {
                warnings.append("\(label): players \(a.number) and \(b.number) start less than a metre apart.")
            }
        }
        return (d, warnings)
    }

    /// A step's description: caption, text, diagram.
    struct StepPlan {
        var caption: String
        var text: String
        var diagram: JournalPlayDiagram
    }

    /// Steps from their descriptions, each carrying over from the one before.
    static func steps(_ specs: Any?, start: JournalPlayDiagram, court: JournalCourtKind,
                      label: String, required: Bool) throws -> ([StepPlan], [String]) {
        guard let list = specs as? [Any], !list.isEmpty else {
            if required { throw JournalPlayAuthoringError.invalid("\(label): at least one step.") }
            return ([], [])
        }
        var plans: [StepPlan] = []
        var warnings: [String] = []
        var base = start
        for (i, item) in list.enumerated() {
            guard let step = item as? [String: Any] else {
                throw JournalPlayAuthoringError.invalid("\(label)[\(i)]: {\"caption\", \"text\", \"diagram\"}.")
            }
            let (d, w) = try diagram(step["diagram"] as? [String: Any], base: base, court: court, label: "\(label)[\(i)]")
            plans.append(StepPlan(caption: (step["caption"] as? String ?? "").trimmed,
                                  text: (step["text"] as? String ?? "").trimmed, diagram: d))
            warnings += w
            base = JournalPlayMath.startOfNextStep(after: d, court: court)
        }
        return (plans, warnings)
    }

    // MARK: - Writing

    struct Result {
        let play: JournalPlay
        let warnings: [String]
    }

    /// A whole play: details, the concept's steps, wrinkles and variations.
    static func createPlay(_ spec: [String: Any], in context: ModelContext) throws -> Result {
        guard let name = (spec["name"] as? String)?.trimmed, !name.isEmpty else {
            throw JournalPlayAuthoringError.invalid("name: the play's name.")
        }
        let court = try court(spec["court"]) ?? .half
        let category = try category(spec["category"]) ?? .halfCourt
        let start = JournalPlayMath.defaultAlignment(court)
        let (conceptSteps, conceptWarnings) = try steps(spec["steps"], start: start, court: court,
                                                        label: "steps", required: true)
        // A part's first step starts from the concept's set, without its lines.
        var partStart = conceptSteps[0].diagram
        partStart.actions = []
        partStart.notes = []
        var parts: [(JournalPlayPartKind, String, String, [StepPlan])] = []
        var warnings = conceptWarnings
        for kind in [JournalPlayPartKind.wrinkle, .variation] {
            let key = kind == .wrinkle ? "wrinkles" : "variations"
            guard let list = spec[key] as? [Any] else { continue }
            for (i, item) in list.enumerated() {
                guard let part = item as? [String: Any], let partName = (part["name"] as? String)?.trimmed, !partName.isEmpty else {
                    throw JournalPlayAuthoringError.invalid("\(key)[\(i)]: {\"name\", \"notes\", \"steps\"}.")
                }
                let (plans, w) = try steps(part["steps"], start: partStart, court: court, label: "\(key)[\(i)].steps", required: true)
                parts.append((kind, partName, (part["notes"] as? String ?? "").trimmed, plans))
                warnings += w
            }
        }

        // Everything checked: write.
        let play = JournalPlay.create(name: name, category: category, court: court, in: context)
        play.situation = (spec["situation"] as? String ?? "").trimmed
        play.concept = (spec["concept"] as? String ?? "").trimmed
        play.source = (spec["source"] as? String ?? "").trimmed
        play.sourceURL = (spec["source_url"] as? String)?.trimmed.nilIfEmpty
        if let concept = play.conceptPart {
            if let conceptName = (spec["concept_name"] as? String)?.trimmed, !conceptName.isEmpty { concept.name = conceptName }
            write(conceptSteps, into: concept, in: context)
        }
        for (kind, partName, notes, plans) in parts {
            let part = play.addPart(kind, name: partName, in: context)
            part.notes = notes
            write(plans, into: part, in: context)
        }
        try context.save()
        return Result(play: play, warnings: warnings)
    }

    /// The part's steps become `plans` (a new part's one starting step is reused).
    private static func write(_ plans: [StepPlan], into part: JournalPlayPart, in context: ModelContext) {
        var existing = part.sortedSteps
        for (i, plan) in plans.enumerated() {
            let step: JournalPlayStep
            if !existing.isEmpty {
                step = existing.removeFirst()
            } else {
                step = JournalPlayStep(order: i)
                context.insert(step)
                part.steps?.append(step)
            }
            step.order = i
            step.caption = plan.caption
            step.text = plan.text
            step.diagram = plan.diagram
        }
    }

    /// A wrinkle or variation, at the end of its kind.
    static func addPart(to play: JournalPlay, _ spec: [String: Any], in context: ModelContext) throws -> (JournalPlayPart, [String]) {
        let kindText = (spec["kind"] as? String ?? "").lowercased()
        guard let kind = JournalPlayPartKind(rawValue: kindText), kind != .concept else {
            throw JournalPlayAuthoringError.invalid("kind: wrinkle or variation.")
        }
        guard let name = (spec["name"] as? String)?.trimmed, !name.isEmpty else {
            throw JournalPlayAuthoringError.invalid("name: the part's name.")
        }
        var start = play.conceptPart?.sortedSteps.first?.diagram ?? JournalPlayMath.defaultAlignment(play.court)
        start.actions = []
        start.notes = []
        let (plans, warnings) = try steps(spec["steps"], start: start, court: play.court, label: "steps", required: true)
        let part = play.addPart(kind, name: name, in: context)
        part.notes = (spec["notes"] as? String ?? "").trimmed
        write(plans, into: part, in: context)
        try context.save()
        return (part, warnings)
    }

    /// A step after `after` (1-based; default: the end), carrying over from it.
    static func addStep(to part: JournalPlayPart, after: Int?, _ spec: [String: Any],
                        in context: ModelContext) throws -> (JournalPlayStep, [String]) {
        let steps = part.sortedSteps
        let previous: JournalPlayStep?
        if let after {
            guard after == 0 || steps.indices.contains(after - 1) else {
                throw JournalPlayAuthoringError.invalid("after_step \(after): the part has \(steps.count) steps.")
            }
            previous = after == 0 ? nil : steps[after - 1]
        } else {
            previous = steps.last
        }
        let court = part.play?.court ?? .half
        let base = previous.map { JournalPlayMath.startOfNextStep(after: $0.diagram, court: court) } ?? JournalPlayMath.defaultAlignment(court)
        let (d, warnings) = try diagram(spec["diagram"] as? [String: Any], base: base, court: court, label: "diagram")
        let step: JournalPlayStep
        if let previous {
            step = part.addStep(after: previous, in: context)
        } else {
            // First place: everything moves down one.
            for later in steps { later.order += 1 }
            step = JournalPlayStep(order: 0)
            context.insert(step)
            part.steps?.append(step)
        }
        step.caption = (spec["caption"] as? String ?? "").trimmed
        step.text = (spec["text"] as? String ?? "").trimmed
        step.diagram = d
        try context.save()
        return (step, warnings)
    }

    /// A step's caption, text or drawing changed. The diagram's given fields
    /// replace the step's own; the rest stays.
    static func updateStep(_ step: JournalPlayStep, _ spec: [String: Any], in context: ModelContext) throws -> [String] {
        let court = step.part?.play?.court ?? .half
        let (d, warnings) = try diagram(spec["diagram"] as? [String: Any], base: step.diagram, court: court, label: "diagram")
        if let caption = spec["caption"] as? String { step.caption = caption.trimmed }
        if let text = spec["text"] as? String { step.text = text.trimmed }
        step.diagram = d
        try context.save()
        return warnings
    }

    /// The play's details; a court change turns every drawing to the new court.
    static func updatePlay(_ play: JournalPlay, _ spec: [String: Any], in context: ModelContext) throws {
        let category = try category(spec["category"])
        let court = try court(spec["court"])
        if let name = (spec["name"] as? String)?.trimmed {
            guard !name.isEmpty else { throw JournalPlayAuthoringError.invalid("name cannot be empty.") }
            play.name = name
        }
        if let category { play.category = category }
        if let situation = spec["situation"] as? String { play.situation = situation.trimmed }
        if let concept = spec["concept"] as? String { play.concept = concept.trimmed }
        if let source = spec["source"] as? String { play.source = source.trimmed }
        if let url = spec["source_url"] as? String { play.sourceURL = url.trimmed.nilIfEmpty }
        if let court { play.changeCourt(to: court) }
        try context.save()
    }

    // MARK: - Describing (the same format, filled in)

    private static func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    private static func xy(_ p: P) -> [Double] { [r(p.x), r(p.y)] }

    static func describe(_ d: JournalPlayDiagram) -> [String: Any] {
        var out: [String: Any] = [
            "offense": d.offense.map { ["number": $0.number, "x": r($0.at.x), "y": r($0.at.y)] },
            "defense": d.defense.map { def -> [String: Any] in
                var item: [String: Any] = ["x": r(def.at.x), "y": r(def.at.y)]
                if def.isRead { item["read"] = true }
                if let g = def.guards { item["guards"] = g }
                return item
            },
            "balls": d.balls,
            "actions": d.actions.map { a -> [String: Any] in
                var item: [String: Any] = ["kind": a.kind.rawValue, "player": a.player]
                switch a.kind {
                case .pass, .handoff: item["to"] = a.receiver ?? 0
                case .shot: break
                default:
                    item["path"] = a.path.dropFirst().map(xy)
                    item["shape"] = a.isStraight ? "straight" : "curved"
                }
                return item
            },
        ]
        if let mode = d.defenseMode { out["defense_mode"] = mode == .man ? "man" : mode == .zone23 ? "2-3" : "3-2" }
        if !d.notes.isEmpty { out["notes"] = d.notes.map { ["text": $0.text, "x": r($0.at.x), "y": r($0.at.y)] } }
        return out
    }

    static func categoryName(_ c: JournalPlayCategory) -> String {
        switch c {
        case .transition: "transition"
        case .halfCourt: "half_court"
        case .baselineInbound: "baseline_inbound"
        case .sidelineInbound: "sideline_inbound"
        case .versusMan: "versus_man"
        case .other: "other"
        }
    }

    static func brief(_ play: JournalPlay) -> [String: Any] {
        [
            "play_id": playID(play),
            "name": play.name,
            "category": categoryName(play.category),
            "court": play.court.rawValue,
            "situation": play.situation,
            "steps": play.conceptPart?.sortedSteps.count ?? 0,
            "wrinkles": play.parts(.wrinkle).count,
            "variations": play.parts(.variation).count,
        ]
    }

    static func describe(_ play: JournalPlay) -> [String: Any] {
        var out = brief(play)
        out["concept"] = play.concept
        out["source"] = play.source
        if let url = play.sourceURL { out["source_url"] = url }
        out["parts"] = play.sortedParts.enumerated().map { i, part -> [String: Any] in
            [
                "part": i + 1,
                "kind": part.kind.rawValue,
                "name": part.name,
                "notes": part.notes,
                "steps": part.sortedSteps.enumerated().map { j, step -> [String: Any] in
                    ["step": j + 1, "caption": step.caption, "text": step.text, "diagram": describe(step.diagram)]
                },
            ]
        }
        return out
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
