import Foundation

// "YOUR JOB" (23 Nov 2026, Luther: a play shared to one player "highlights what
// that player does in that play"). For one numbered player in one step, a
// short line worded from the drawing itself — never invented: what they draw
// (cut / dribble / pass / screen / shot / hand-off), what they catch, and where
// it takes them, named by the spot on the floor. Nothing drawn for them = "hold
// your spot". Pure, both languages.

nonisolated enum PlayRoleJob {
    /// The parts of a player's step, in drawing order.
    static func lines(for number: Int, in diagram: JournalPlayDiagram, court: JournalCourtKind,
                      name: (Int) -> String, chinese: Bool) -> [String] {
        guard diagram.player(number) != nil else { return [] }
        var out: [String] = []
        for action in diagram.actions {
            if action.player == number, let end = action.path.last {
                let spot = spotName(end, court: court, chinese: chinese)
                switch action.kind {
                case .cut:
                    out.append(chinese ? "切入到\(spot)" : "Cut to \(spot)")
                case .dribble:
                    out.append(chinese ? "运球到\(spot)" : "Dribble to \(spot)")
                case .pass:
                    let to = action.receiver.map(name) ?? (chinese ? "队友" : "a teammate")
                    out.append(chinese ? "传球给\(to)" : "Pass to \(to)")
                case .handoff:
                    let to = action.receiver.map(name) ?? (chinese ? "队友" : "a teammate")
                    out.append(chinese ? "手递手给\(to)" : "Hand off to \(to)")
                case .shot:
                    out.append(chinese ? "投篮" : "Shoot")
                case .screen:
                    if let mate = screened(by: action, in: diagram) {
                        out.append(chinese ? "在\(spot)为\(name(mate))掩护" : "Screen for \(name(mate)) at \(spot)")
                    } else {
                        out.append(chinese ? "在\(spot)掩护" : "Set a screen at \(spot)")
                    }
                }
            } else if action.receiver == number, action.kind == .pass || action.kind == .handoff {
                out.append(chinese ? "接\(name(action.player))的球" : "Catch from \(name(action.player))")
            }
        }
        if out.isEmpty {
            let at = diagram.player(number).map { spotName($0.at, court: court, chinese: chinese) } ?? ""
            out.append(chinese ? "在\(at)保持位置" : "Stay at \(at)")
        }
        return out
    }

    /// One sentence: "Cut to the left corner, then catch from 1."
    static func sentence(for number: Int, in diagram: JournalPlayDiagram, court: JournalCourtKind,
                         name: (Int) -> String, chinese: Bool) -> String {
        let parts = lines(for: number, in: diagram, court: court, name: name, chinese: chinese)
        guard let first = parts.first else { return "" }
        if chinese { return parts.joined(separator: "，然后") + "。" }
        let rest = parts.dropFirst().map { $0.prefix(1).lowercased() + $0.dropFirst() }
        return ([first] + rest).joined(separator: ", then ") + "."
    }

    /// The teammate a screen is set for: the one whose move drawn AFTER the
    /// screen passes nearest its spot (within 2.5 m), else the nearest
    /// teammate to the spot.
    static func screened(by screen: JournalPlayDiagram.Action, in diagram: JournalPlayDiagram) -> Int? {
        guard let spot = screen.path.last,
              let index = diagram.actions.firstIndex(of: screen) else { return nil }
        func distance(_ a: JournalCourtPoint, _ b: JournalCourtPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
        let later = diagram.actions[(index + 1)...].filter { $0.player != screen.player && $0.kind.movesPlayer }
        let users = later.compactMap { a -> (Int, Double)? in
            guard let near = a.path.map({ distance($0, spot) }).min(), near < 2.5 else { return nil }
            return (a.player, near)
        }
        if let best = users.min(by: { $0.1 < $1.1 }) { return best.0 }
        let mates = diagram.offense.filter { $0.number != screen.player }
            .map { ($0.number, distance($0.at, spot)) }
        return mates.min(by: { $0.1 < $1.1 }).flatMap { $0.1 < 3 ? $0.0 : nil }
    }

    // MARK: - Spots on the floor

    /// Where a point is, in a coach's words ("the left wing", "the rim").
    /// Left / right as the offense faces the basket — as the court is drawn.
    static func spotName(_ p: JournalCourtPoint, court: JournalCourtKind, chinese: Bool) -> String {
        // Work in half-court metres: rim at (7.5, 1.575), x across, y out.
        let h: (x: Double, y: Double)
        switch court {
        case .half: h = (p.x, p.y)
        case .full: h = (p.y, 28 - p.x)
        }
        if h.y > 14 { return chinese ? "后场" : "the backcourt" }
        if h.y > 11.5 { return chinese ? "中线附近" : "half court" }
        let rim = (x: 7.5, y: 1.575)
        let d = hypot(h.x - rim.x, h.y - rim.y)
        let left = h.x < rim.x
        let side = chinese ? (left ? "左" : "右") : (left ? "left " : "right ")
        let middle = abs(h.x - rim.x) < 1.6
        if d < 1.6 { return chinese ? "篮下" : "the rim" }
        let inLane = abs(h.x - rim.x) <= 2.45 && h.y <= 5.8
        let nearElbow = abs(abs(h.x - rim.x) - 2.45) < 1.3 && abs(h.y - 5.8) < 1.3
        if nearElbow && !middle { return chinese ? "\(side)肘区" : "the \(side)elbow" }
        if inLane {
            if h.y < 3.4 { return chinese ? (middle ? "篮下" : "\(side)低位") : (middle ? "the rim" : "the \(side)block") }
            return chinese ? "高位" : "the high post"
        }
        // The corners: deep along the baseline, at the arc or near it.
        if h.y < 3.0 && abs(h.x - rim.x) > 5.4 { return chinese ? "\(side)底角" : "the \(side)corner" }
        if d > 6.5 {
            if h.y < 3.0 { return chinese ? "\(side)底角" : "the \(side)corner" }
            if middle || abs(h.x - rim.x) < 2.6 { return chinese ? "弧顶" : "the top" }
            return chinese ? "\(side)侧翼" : "the \(side)wing"
        }
        if h.y < 3.0 { return chinese ? "\(side)底线" : "the \(side)short corner" }
        if abs(h.x - rim.x) < 2.6 { return chinese ? "罚球线" : "the free-throw line" }
        return chinese ? "\(side)中距离" : "the \(side)mid-range"
    }
}
