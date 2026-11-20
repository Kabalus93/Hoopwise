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
    /// The basket's entry in the game's log (points only), so Undo removes
    /// exactly the one it added.
    var basketId = UUID()

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
        if case .points(let n) = kind {
            game.baskets.append(GameBasket(id: basketId, scorerId: playerId, assisterId: assistId,
                                           points: n, teamId: teamId))
        }
    }

    func undo(on game: inout SessionGame) {
        game.removeStat(stat, for: playerId, teamId: teamId)
        if let assistId { game.removeStat(.assist, for: assistId, teamId: teamId) }
        game.baskets.removeAll { $0.id == basketId }
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
    @Environment(\.colorScheme) private var colorScheme

    private static let space = "liveTeamPanel"
    private var teamColor: Color { team.displayColor(for: colorScheme) }
    /// ON THE FLOOR (20 Nov 2026, Luther: "only the starters, with subs
    /// coming from the bench, seamless"): the team's first `starters`
    /// players; a game set up before starters existed has everyone on.
    private var players: [Student] {
        Array(team.playerIds.prefix(onCourtCount)).compactMap { id in students.first { $0.id == id } }
    }
    private var bench: [Student] {
        Array(team.playerIds.dropFirst(onCourtCount)).compactMap { id in students.first { $0.id == id } }
    }
    private var onCourtCount: Int {
        min(team.starters ?? team.playerIds.count, team.playerIds.count)
    }

    /// A bench player being dragged toward the floor.
    @State private var subDrag: (id: UUID, at: CGPoint)?
    /// The bench player whose "in for whom?" popover is open.
    @State private var subChoosing: UUID?
    @State private var subTick = 0

    var body: some View {
        GeometryReader { proxy in
            let count = max(players.count, 5)
            let spacing: CGFloat = 8
            let benchHeight: CGFloat = bench.isEmpty ? 0 : 84
            // Tall enough for a thumb, never a slab (an iPad's height / 5).
            let rowHeight = min(150, max(56, (proxy.size.height - benchHeight - spacing * CGFloat(count - 1)) / CGFloat(count)))
            VStack(spacing: spacing) {
                ForEach(players) { student in
                    row(student, height: rowHeight)
                }
                Spacer(minLength: 0)
                if !bench.isEmpty { benchStrip }
            }
            .overlay { assistLine }
            .overlay { subGhost }
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
        .sensoryFeedback(.success, trigger: subTick)
    }

    // MARK: Bench — subs

    private var benchStrip: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "替补" : "BENCH")
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(.secondary)
            .frame(width: 44)
            ForEach(bench) { student in
                benchChip(student)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(teamColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.bench")
    }

    private func benchChip(_ student: Student) -> some View {
        let dragging = subDrag?.id == student.id
        return VStack(spacing: 3) {
            StudentAvatarView(student: student, size: 44)
                .overlay(Circle().strokeBorder(teamColor, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).padding(-2))
            Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 64)
        }
        .opacity(dragging ? 0.35 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    if moved >= AssistDrop.dragThreshold { subDrag = (student.id, value.location) }
                }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    if moved < AssistDrop.dragThreshold {
                        subChoosing = student.id
                    } else if let out = subTarget(at: value.location) {
                        substitute(in: student.id, out: out)
                    }
                    subDrag = nil
                }
        )
        .popover(isPresented: Binding(get: { subChoosing == student.id },
                                      set: { if !$0 { subChoosing = nil } })) {
            subChooser(for: student)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live.bench.player")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { subChoosing = student.id }
    }

    /// The floor player a bench drag is over — anywhere across his row's
    /// height (the stat buttons too), so the drop is easy to hit.
    private func subTarget(at point: CGPoint) -> UUID? {
        rowFrames.first { id, frame in
            players.contains { $0.id == id } && point.y >= frame.minY - 4 && point.y <= frame.maxY + 4
        }?.key
    }

    /// Tap on a bench player: who does he come in for?
    private func subChooser(for student: Student) -> some View {
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 0) {
            Text(zh ? "\(student.primaryDisplayName) 换下谁？" : "\(student.primaryDisplayName) in for…")
                .font(.headline)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(players) { out in
                Button {
                    subChoosing = nil
                    substitute(in: student.id, out: out.id)
                } label: {
                    HStack(spacing: 10) {
                        StudentAvatarView(student: out, size: 32)
                        Text(out.primaryDisplayName).foregroundStyle(.primary)
                        Spacer()
                        Text("\(game.stats(for: out.id)?.points ?? 0)")
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(teamColor)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live.sub.out")
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    /// The bench player takes the floor player's place; he goes to the
    /// bench in the other's spot. Stats stay with each player.
    private func substitute(in incoming: UUID, out outgoing: UUID) {
        guard let t = game.teams.firstIndex(where: { $0.id == team.id }),
              let a = game.teams[t].playerIds.firstIndex(of: incoming),
              let b = game.teams[t].playerIds.firstIndex(of: outgoing) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if game.teams[t].starters == nil { game.teams[t].starters = onCourtCount }
            game.teams[t].playerIds.swapAt(a, b)
            game.updatedAt = Date()
        }
        subTick += 1
    }

    /// The bench player following the finger while dragged.
    @ViewBuilder
    private var subGhost: some View {
        if let drag = subDrag, let s = students.first(where: { $0.id == drag.id }) {
            StudentAvatarView(student: s, size: 52)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 3))
                .shadow(radius: 6)
                .position(drag.at)
                .allowsHitTesting(false)
        }
    }

    // MARK: Row

    private func row(_ student: Student, height: CGFloat) -> some View {
        let stats = game.stats(for: student.id)
        let isSource = dragFrom?.id == student.id
        let isTarget = (dragTo.map { point in
            rowFrames[student.id]?.contains(point) == true && dragFrom?.id != student.id
        } ?? false) || (subDrag.map { subTarget(at: $0.at) == student.id } ?? false)
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
        let item = { (part: (String, Int)) in "\(part.1) \(part.0)" }
        // One line when it fits, else two even lines (REB · AST / STL · BLK)
        // — never cut off (Luther, November 2026: the iPad mini's narrower
        // rows showed "0 REB · 1 AST · 0 ST…").
        return ViewThatFits(in: .horizontal) {
            Text(parts.map(item).joined(separator: " · "))
                .fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.prefix(2).map(item).joined(separator: " · ")).fixedSize()
                Text(parts.suffix(2).map(item).joined(separator: " · ")).fixedSize()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
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

// MARK: - Team colour on screen

extension GameTeam {
    /// The team's colour as the live screen draws it: a black team is light
    /// grey in dark mode and a white team mid-grey in light mode (November
    /// 2026 — the black team's rows, points and score vanished in dark mode).
    func displayColor(for scheme: ColorScheme) -> Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else { return Color(hex: colorHex) }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if scheme == .dark && luminance < 0.18 { return Color(white: 0.78) }
        if scheme == .light && luminance > 0.85 { return Color(white: 0.45) }
        return Color(hex: colorHex)
    }
}
