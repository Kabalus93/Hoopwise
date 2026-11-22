import Foundation

// OFFENSE PRESETS (22 November 2026, Luther: "move [the steps button] in the
// side bar and replace it with offense option & preset"). The board's bottom
// left opens the common alignments, 1v1 to 5v5; a tap puts the set on the
// step on screen — the attackers where the set says, 1 with the ball, the
// step's lines gone (they were drawn from the old spots), cones, lanes and
// annotations kept, and the auto defense re-matched to the new attackers
// (by hand: defenders stay where they are). Pure, in half-court metres
// (basket (7.5, 1.575), baseline y = 0); a full court gets the set at the
// attacked end (JournalPlayMath.converted).

nonisolated struct OffensePreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let nameZh: String
    /// Numbered attackers in half-court metres; 1 has the ball.
    let spots: [Int: JournalCourtPoint]

    var players: Int { spots.count }
    func title(chinese: Bool) -> String { chinese ? nameZh : name }

    /// The set as a step: attackers only, 1 with the ball.
    func diagram(court: JournalCourtKind) -> JournalPlayDiagram {
        let half = JournalPlayDiagram(offense: spots.sorted { $0.key < $1.key }.map { .init(number: $0.key, at: $0.value) },
                                      ball: 1)
        return JournalPlayMath.converted(half, from: .half, to: court)
    }
}

nonisolated enum OffensePresets {
    typealias P = JournalCourtPoint

    // The floor's spots (half court, metres from the left sideline / baseline).
    // Top, wings and corners are the default alignment's, so 5-Out IS the
    // board's familiar start (and a drill drawing's).
    static let top = P(7.5, 9.6)
    static let leftSlot = P(4.6, 8.5), rightSlot = P(10.4, 8.5)
    static let leftWing = P(2.4, 6.6), rightWing = P(12.6, 6.6)
    static let leftCorner = P(1.1, 1.2), rightCorner = P(13.9, 1.2)
    static let leftElbow = P(5.2, 5.8), rightElbow = P(9.8, 5.8)
    static let leftBlock = P(5.5, 2.3), rightBlock = P(9.5, 2.3)
    static let highPost = P(7.5, 5.9)
    static let rightShortCorner = P(11.8, 1.2)

    static let all: [OffensePreset] = [
        // 5v5
        .init(id: "fiveOut", name: "5-Out", nameZh: "五外",
              spots: [1: top, 2: rightWing, 3: leftWing, 4: rightCorner, 5: leftCorner]),
        .init(id: "fourOutOneIn", name: "4-Out 1-In", nameZh: "四外一内",
              spots: [1: leftSlot, 2: rightSlot, 3: leftWing, 4: rightWing, 5: rightBlock]),
        .init(id: "horns", name: "Horns", nameZh: "牛角",
              spots: [1: top, 2: rightCorner, 3: leftCorner, 4: leftElbow, 5: rightElbow]),
        .init(id: "oneFourHigh", name: "1-4 High", nameZh: "1-4 高位",
              spots: [1: top, 2: rightWing, 3: leftWing, 4: leftElbow, 5: rightElbow]),
        .init(id: "oneFourLow", name: "1-4 Low", nameZh: "1-4 低位",
              spots: [1: top, 2: rightCorner, 3: leftCorner, 4: leftBlock, 5: rightBlock]),
        .init(id: "box", name: "Box", nameZh: "方框",
              spots: [1: top, 2: leftBlock, 3: rightBlock, 4: leftElbow, 5: rightElbow]),
        .init(id: "oneThreeOne", name: "1-3-1", nameZh: "1-3-1",
              spots: [1: top, 2: rightWing, 3: leftWing, 4: highPost, 5: rightShortCorner]),
        // 4v4
        .init(id: "fourOut", name: "4-Out", nameZh: "四外",
              spots: [1: leftSlot, 2: rightSlot, 3: leftCorner, 4: rightCorner]),
        .init(id: "threeOutOneIn", name: "3-Out 1-In", nameZh: "三外一内",
              spots: [1: top, 2: rightWing, 3: leftWing, 4: rightBlock]),
        // 3v3
        .init(id: "threeOut", name: "3-Out", nameZh: "三外",
              spots: [1: top, 2: rightWing, 3: leftWing]),
        .init(id: "twoOutOneIn", name: "2-Out 1-In", nameZh: "二外一内",
              spots: [1: leftSlot, 2: rightSlot, 3: rightBlock]),
        // 2v2
        .init(id: "twoMan", name: "Top and wing", nameZh: "弧顶与侧翼",
              spots: [1: top, 2: rightWing]),
        .init(id: "wingPost", name: "Wing and post", nameZh: "侧翼与低位",
              spots: [1: rightWing, 2: rightBlock]),
        // 1v1
        .init(id: "oneOnOne", name: "1v1 at the top", nameZh: "弧顶一对一",
              spots: [1: top]),
    ]

    /// The presets of one format, in the list's order.
    static func with(players: Int) -> [OffensePreset] { all.filter { $0.players == players } }

    /// The preset the step's attackers stand in (within 0.3 m each), if any.
    static func matching(_ diagram: JournalPlayDiagram, court: JournalCourtKind) -> OffensePreset? {
        all.first { preset in
            let set = preset.diagram(court: court).offense
            guard set.count == diagram.offense.count else { return false }
            return set.allSatisfy { p in diagram.offense.contains { $0.number == p.number && $0.at.distance(to: p.at) < 0.3 } }
        }
    }
}

nonisolated extension JournalPlayMath {
    /// The step with the preset's attackers: 1 with the ball, the lines gone
    /// (they started from the old spots), cones, lanes, notes and ink kept;
    /// an auto defense re-matched to the new attackers (by hand: kept).
    static func applying(_ preset: OffensePreset, to diagram: JournalPlayDiagram,
                         court: JournalCourtKind) -> JournalPlayDiagram {
        var out = diagram
        let set = preset.diagram(court: court)
        out.offense = set.offense
        out.balls = set.balls
        out.actions = []
        if let mode = out.defenseMode {
            out.defense = matched(mode, defense: out.defense, offense: out.offense,
                                  ball: out.balls.first.flatMap { out.player($0)?.at }, court: court)
            out = placingDefense(out, court: court)
        }
        return out
    }
}
