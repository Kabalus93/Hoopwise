import Foundation

// DRILL SERIES (18 Nov 2026, Luther: "create series or evolutions of drills
// … level 1 stationary dribbling, level 2 dribbling while moving … increasing
// level of difficulty … when planning a phase … automatically spread the
// exercises per session with progression from easy to hard").
//
// A series is an ORDERED LIST OF DRILLS — each level stays a whole drill with
// its own drawing, minutes and skill ratings; library drills can be levels.
// Stored WITHOUT A SCHEMA CHANGE as one personal SDDrill tagged `kind:series`
// whose tags hold the levels in order (`series.level:<n>=<drill id>`) and the
// block it plans into (`series.block:warmup|skills`). The levels' own records
// are never touched — library drills are re-seeded every launch.

struct DrillSeries: Identifiable, Equatable {
    static let kindTag = "kind:series"
    static let levelPrefix = "series.level:"
    static let blockPrefix = "series.block:"

    let id: UUID
    var name: String
    var summary: String
    /// Drill ids, easiest first.
    var levels: [UUID]
    var block: PhaseDrillEditing.Block

    init(id: UUID = UUID(), name: String, summary: String = "", levels: [UUID] = [],
         block: PhaseDrillEditing.Block = .warmup) {
        self.id = id
        self.name = name
        self.summary = summary
        self.levels = levels
        self.block = block
    }

    /// The series a drill record holds; nil when it is an ordinary drill.
    init?(drill: DrillItem) {
        guard drill.tags.contains(Self.kindTag) else { return nil }
        id = drill.id
        name = drill.name
        summary = drill.description
        var numbered: [(Int, UUID)] = []
        for tag in drill.tags where tag.hasPrefix(Self.levelPrefix) {
            let body = tag.dropFirst(Self.levelPrefix.count).split(separator: "=", maxSplits: 1)
            guard body.count == 2, let n = Int(body[0]), let level = UUID(uuidString: String(body[1])) else { continue }
            numbered.append((n, level))
        }
        levels = numbered.sorted { $0.0 < $1.0 }.map(\.1)
        let blockTag = drill.tags.first { $0.hasPrefix(Self.blockPrefix) }?.dropFirst(Self.blockPrefix.count)
        block = blockTag.flatMap { PhaseDrillEditing.Block(rawValue: String($0)) } ?? .warmup
    }

    /// `drill` (a new record, or the stored one) carrying this series.
    func applied(to drill: DrillItem) -> DrillItem {
        var d = drill
        d.name = name
        d.description = summary
        d.tags = d.tags.filter { $0 != Self.kindTag && !$0.hasPrefix(Self.levelPrefix) && !$0.hasPrefix(Self.blockPrefix) }
        d.tags.append(Self.kindTag)
        d.tags.append(Self.blockPrefix + block.rawValue)
        for (i, level) in levels.enumerated() { d.tags.append("\(Self.levelPrefix)\(i + 1)=\(level.uuidString)") }
        return d
    }

    /// The level (1-based) `drillId` holds, if any.
    func level(of drillId: UUID) -> Int? { levels.firstIndex(of: drillId).map { $0 + 1 } }

    /// Every series in `drills`.
    static func all(in drills: [DrillItem]) -> [DrillSeries] {
        drills.compactMap(DrillSeries.init(drill:)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The series `drillId` is a level of, with its level.
    static func containing(_ drillId: UUID, in drills: [DrillItem]) -> [(series: DrillSeries, level: Int)] {
        all(in: drills).compactMap { s in s.level(of: drillId).map { (s, $0) } }
    }
}

extension DrillItem {
    /// A series record, not a drill to plan or list as one.
    var isSeries: Bool { tags.contains(DrillSeries.kindTag) }
}

/// Spreading a series over a phase's sessions, easiest first.
enum SeriesSpread {
    /// When there are more levels than sessions.
    enum Overflow: String, CaseIterable {
        /// One new level per session; the series stops where the phase does.
        case stop
        /// Two new levels in some sessions so the series finishes.
        case doubleUp
    }

    struct Slot: Equatable {
        /// The level met before (a short review), if any.
        var review: UUID?
        /// The level(s) taught in this session, easiest first.
        var teach: [UUID]
        var drills: [UUID] { (review.map { [$0] } ?? []) + teach }
    }

    /// One slot per session. EVEN PACING — the sessions are shared out over
    /// the levels, the early levels taking any extra (the foundation); NEVER
    /// MORE THAN ONE NEW LEVEL a session unless `overflow` is `.doubleUp`;
    /// the first session of a level from the second on opens with the
    /// previous level as a short REVIEW.
    static func plan(levels: [UUID], sessions: Int, overflow: Overflow = .stop) -> [Slot] {
        guard sessions > 0, !levels.isEmpty else { return [] }
        // Which levels each session teaches.
        var teach: [[UUID]] = []
        if levels.count <= sessions {
            let base = sessions / levels.count, extra = sessions % levels.count
            for (i, level) in levels.enumerated() {
                teach += Array(repeating: [level], count: base + (i < extra ? 1 : 0))
            }
        } else if overflow == .stop {
            teach = levels.prefix(sessions).map { [$0] }
        } else {
            // Pair up levels from the END so the early ones keep a session to
            // themselves; never more than two in one session.
            var groups = levels.map { [$0] }
            var i = groups.count - 1
            while groups.count > sessions, i > 0 {
                groups[i - 1] += groups[i]
                groups.remove(at: i)
                i -= 2
                if i < 1 { i = groups.count - 1 }
            }
            teach = Array(groups.prefix(sessions))
        }
        var slots: [Slot] = []
        var previous: UUID?
        var lastTaught: [UUID] = []
        for group in teach {
            let isNew = group != lastTaught
            slots.append(Slot(review: isNew ? previous : nil, teach: group))
            if isNew {
                previous = group.last
                lastTaught = group
            }
        }
        // The very first session has nothing to review.
        if !slots.isEmpty { slots[0].review = nil }
        return slots
    }

    /// The highest level a plan reaches (1-based).
    static func reached(_ slots: [Slot], levels: [UUID]) -> Int {
        let taught = Set(slots.flatMap(\.teach))
        return levels.lastIndex { taught.contains($0) }.map { $0 + 1 } ?? 0
    }

    /// A session's plan with the series laid in: every level of the series
    /// already there comes out first (re-spreading never doubles), then the
    /// slot's drills go at the end of `block` in order.
    static func applying(_ slot: Slot, series: DrillSeries, to curriculum: SessionCurriculum) -> SessionCurriculum {
        var c = curriculum
        for level in series.levels { c = PhaseDrillEditing.removing(level, from: c) }
        for drill in slot.drills { c = PhaseDrillEditing.adding(drill, to: c, block: series.block) }
        return c
    }
}
