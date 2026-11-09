import SwiftUI

// MARK: - Live game stat entry (October 2026, Luther — field use)
//
// One team at a time, every player on screen with no scrolling. The player's
// ROW is the points target: tap = a basket at the selected value; press and
// DRAG to a teammate's row = the basket plus that teammate's assist (a line
// follows the finger; letting go anywhere else = the basket alone). Rebound,
// steal and block are fixed, colour-coded buttons on the right of the row.
// Mistakes are fixed with Undo (the last action, whatever it was) — a hold on
// the row would collide with starting a drag. REB/STL/BLK still remove one on
// a hold (StatPressButton).

/// One logged stat, so Undo can reverse exactly what was done.
struct GameStatAction: Equatable {
    enum Kind: Equatable {
        case points(Int)
        case rebound, steal, block
    }
    let playerId: UUID
    let teamId: UUID
    let kind: Kind
    /// The passer credited with an assist on a basket.
    var assistId: UUID? = nil

    private var stat: StatType {
        switch kind {
        case .points(let n): return .points(n)
        case .rebound: return .rebound
        case .steal: return .steal
        case .block: return .block
        }
    }

    func apply(to game: inout SessionGame) {
        game.addStat(stat, for: playerId, teamId: teamId)
        if let assistId { game.addStat(.assist, for: assistId, teamId: teamId) }
    }

    func undo(on game: inout SessionGame) {
        game.removeStat(stat, for: playerId, teamId: teamId)
        if let assistId { game.removeStat(.assist, for: assistId, teamId: teamId) }
    }
}

/// Where a drag from the scorer's row ended. Pure, so it can be tested.
enum AssistDrop {
    /// A press that moved less than this is a tap, not a drag.
    static let dragThreshold: CGFloat = 14

    /// The teammate credited with the assist: the row under `end`, if it is
    /// not the scorer's own. Nil = basket only.
    static func passer(scorer: UUID, travelled: CGFloat, end: CGPoint,
                       rows: [UUID: CGRect]) -> UUID? {
        guard travelled >= dragThreshold else { return nil }
        guard let hit = rows.first(where: { $0.value.contains(end) })?.key, hit != scorer else { return nil }
        return hit
    }
}

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// The selected team's players, each a full-width row sized so they all fit.
struct LiveTeamPanel: View {
    @Binding var game: SessionGame
    let team: GameTeam
    let students: [Student]
    /// The basket value a row tap scores (the strip above: +2 default).
    let pointValue: Int
    let onAction: (GameStatAction) -> Void

    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var dragFrom: (id: UUID, start: CGPoint)?
    @State private var dragTo: CGPoint?
    @State private var basketTick = 0

    private static let space = "liveTeamPanel"
    private var teamColor: Color {
        team.colorHex == "#F5F5F5" ? .gray : Color(hex: team.colorHex)
    }
    private var players: [Student] {
        team.playerIds.compactMap { id in students.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { proxy in
            let count = max(players.count, 5)
            let spacing: CGFloat = 8
            // Tall enough for a thumb, never a slab (an iPad's height / 5).
            let rowHeight = min(150, max(56, (proxy.size.height - spacing * CGFloat(count - 1)) / CGFloat(count)))
            VStack(spacing: spacing) {
                ForEach(players) { student in
                    row(student, height: rowHeight)
                }
                Spacer(minLength: 0)
            }
            .overlay { assistLine }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(RowFrameKey.self) { frames in
            rowFrames = frames
            #if DEBUG
            // HOOPWISE_LIVE_ASSIST_DEMO=1: a pass held from the second row
            // onto the first, frozen, for screenshots of the assist line.
            if ProcessInfo.processInfo.environment["HOOPWISE_LIVE_ASSIST_DEMO"] == "1",
               dragFrom == nil, players.count >= 2,
               let a = frames[players[1].id], let b = frames[players[0].id] {
                dragFrom = (players[1].id, CGPoint(x: a.minX + 40, y: a.midY))
                dragTo = CGPoint(x: b.minX + 120, y: b.midY)
            }
            #endif
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: basketTick)
    }

    // MARK: Row

    private func row(_ student: Student, height: CGFloat) -> some View {
        let stats = game.stats(for: student.id)
        let isSource = dragFrom?.id == student.id
        let isTarget = dragTo.map { point in
            rowFrames[student.id]?.contains(point) == true && dragFrom?.id != student.id
        } ?? false
        let avatar = min(56, height - 16)
        return HStack(spacing: 8) {
            // POINTS target — the whole left part of the row.
            HStack(spacing: 10) {
                StudentAvatarView(student: student, size: avatar)
                VStack(alignment: .leading, spacing: 1) {
                    // Pinyin/English AND Chinese, Chinese first in Chinese.
                    Text(student.primaryDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let secondary = student.secondaryNameLine {
                        Text(secondary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statLine(stats)
                }
                Spacer(minLength: 4)
                Text("\(stats?.points ?? 0)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(teamColor)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("live.points")
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(teamColor.opacity(isSource ? 0.2 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isTarget ? Color.accentColor : teamColor.opacity(0.22),
                                  lineWidth: isTarget ? 2 : 0.75)
            )
            .scaleEffect(isTarget ? 1.015 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isTarget)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(GeometryReader { geo in
                Color.clear.preference(key: RowFrameKey.self,
                                       value: [student.id: geo.frame(in: .named(Self.space))])
            })
            .gesture(scoreGesture(for: student))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("live.row")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                score(student, assist: nil)
            }

            // Rebound is the most frequent, so it is the big one.
            VStack(spacing: 4) {
                statButton(.rebound, student)
                    .frame(height: (height - 4) * 0.58)
                HStack(spacing: 4) {
                    statButton(.steal, student)
                    statButton(.block, student)
                }
            }
            .frame(width: 118, height: height)
        }
    }

    private func statLine(_ stats: SessionPlayerStats?) -> some View {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        let parts: [(String, Int)] = [
            (zh ? "板" : "REB", stats?.rebounds ?? 0), (zh ? "助" : "AST", stats?.assists ?? 0),
            (zh ? "断" : "STL", stats?.steals ?? 0), (zh ? "帽" : "BLK", stats?.blocks ?? 0)]
        return Text(parts.map { "\($0.1) \($0.0)" }.joined(separator: " · "))
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func statButton(_ kind: GameStatAction.Kind, _ student: Student) -> some View {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        let (label, color, icon): (String, Color, String) = {
            switch kind {
            case .rebound: return (zh ? "篮板" : "REB", .purple, "arrow.down.to.line")
            case .steal: return (zh ? "抢断" : "STL", .orange, "hand.raised.fill")
            case .block: return (zh ? "盖帽" : "BLK", .teal, "hand.raised.slash.fill")
            case .points: return ("", .clear, "")
            }
        }()
        let action = GameStatAction(playerId: student.id, teamId: team.id, kind: kind)
        return StatPressButton(label: label, color: color,
                               add: { onAction(action) },
                               remove: { action.undo(on: &game) },
                               fillsHeight: true,
                               font: .system(size: kind == .rebound ? 15 : 12, weight: .bold),
                               icon: icon)
    }

    // MARK: Score / assist gesture

    private func scoreGesture(for student: Student) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragFrom == nil { dragFrom = (student.id, value.startLocation) }
                let moved = hypot(value.translation.width, value.translation.height)
                dragTo = moved >= AssistDrop.dragThreshold ? value.location : nil
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                let passer = AssistDrop.passer(scorer: student.id, travelled: moved,
                                               end: value.location, rows: rowFrames)
                // A drag that ends back on its own row is a cancelled assist,
                // not a cancelled basket: the basket counts either way.
                score(student, assist: passer)
                dragFrom = nil
                dragTo = nil
            }
    }

    private func score(_ student: Student, assist: UUID?) {
        basketTick += 1
        onAction(GameStatAction(playerId: student.id, teamId: team.id,
                                kind: .points(pointValue), assistId: assist))
    }

    /// The pass being drawn: one red line with an arrowhead, from where
    /// the finger went down to where it is now (Luther, November 2026 — a
    /// line that jumped to photos did not follow the hand).
    @ViewBuilder
    private var assistLine: some View {
        if let from = dragFrom, let to = dragTo {
            ZStack {
                Path { path in
                    path.move(to: from.start)
                    // The line stops where the arrowhead's base begins.
                    path.addLine(to: Self.moved(to, toward: from.start, by: 9))
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Self.arrowHead(at: to, from: from.start)
                    .fill(Color.red)
            }
            .allowsHitTesting(false)
        }
    }

    static func moved(_ p: CGPoint, toward q: CGPoint, by d: CGFloat) -> CGPoint {
        let dx = q.x - p.x, dy = q.y - p.y
        let length = hypot(dx, dy)
        guard length > d else { return p }
        return CGPoint(x: p.x + dx / length * d, y: p.y + dy / length * d)
    }

    static func arrowHead(at tip: CGPoint, from control: CGPoint) -> Path {
        let dx = tip.x - control.x, dy = tip.y - control.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let l: CGFloat = 12, w: CGFloat = 6.5
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - ux * l - uy * w, y: tip.y - uy * l + ux * w))
        path.addLine(to: CGPoint(x: tip.x - ux * l + uy * w, y: tip.y - uy * l - ux * w))
        path.closeSubpath()
        return path
    }
}
