import SwiftUI

/// Today's athletes as a cluster of photo bubbles, the Next Up widget's
/// roster (`RosterClusterView` in SAMWidgets) brought into the app (Luther,
/// November 2026). Same slots, same three sizes and the same deterministic
/// jitter seeded by the athlete's id, so the cluster never reshuffles: the
/// card's hero is the big ringed bubble, athletes who attend steadily the
/// small ones, everyone else in between. A tap on a bubble opens that
/// athlete; "+N" opens the whole list.
struct TodaysRosterCluster: View {
    struct Member: Identifiable {
        let student: Student
        /// 0 = the hero (largest, ringed), 1 = neutral, 2 = steady.
        let tier: Int
        var id: UUID { student.id }
    }

    let members: [Member]
    let total: Int
    /// 1 = the widget's own size (124 × 100 pt).
    var scale: CGFloat = 1.5
    var onSelect: (Student) -> Void
    var onMore: () -> Void

    static let slots: [CGPoint] = [
        CGPoint(x: 34, y: 26), CGPoint(x: 78, y: 18), CGPoint(x: 106, y: 44),
        CGPoint(x: 16, y: 58), CGPoint(x: 58, y: 52), CGPoint(x: 96, y: 74),
        CGPoint(x: 32, y: 84), CGPoint(x: 70, y: 88),
    ]
    static let tierSizes: [CGFloat] = [38, 28, 22]

    /// Hero first, then neutral before steady, then a stable id order —
    /// capped at the eight slots.
    static func members(hero: Student?, students: [Student], sessions: [SessionEvent]) -> [Member] {
        let all = students.map { student -> Member in
            if student.id == hero?.id { return Member(student: student, tier: 0) }
            let rate = AttendanceMath.rate(for: student.id, in: sessions)
            let steady = rate.of >= AttentionRules.attendanceMinSessions
                && rate.percent >= AttentionRules.steadyPercent
            return Member(student: student, tier: steady ? 2 : 1)
        }
        return Array(all.sorted {
            $0.tier != $1.tier ? $0.tier < $1.tier : $0.id.uuidString < $1.id.uuidString
        }.prefix(slots.count))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                bubble(member, slot: Self.slots[index % Self.slots.count])
            }
            if total > members.count {
                Button(action: onMore) {
                    Text("+\(total - members.count)")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .padding(.horizontal, 5 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .position(x: 108 * scale, y: 92 * scale)
                .accessibilityLabel(Text(LocalizationManager.shared.currentLanguage == .chinese
                                         ? "还有 \(total - members.count) 名学员" : "\(total - members.count) more athletes"))
            }
        }
        .frame(width: 124 * scale, height: 100 * scale)
    }

    private func bubble(_ member: Member, slot: CGPoint) -> some View {
        let size = Self.tierSizes[min(max(member.tier, 0), 2)] * scale
        // Deterministic jitter seeded by athlete id — no reshuffling.
        let seed = member.id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let dx = (CGFloat(seed % 7) - 3) * scale
        let dy = (CGFloat((seed / 7) % 7) - 3) * scale
        return Button { onSelect(member.student) } label: {
            StudentAvatarView(student: member.student, size: size)
                .overlay(Circle().stroke(member.tier == 0 ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.25),
                                         lineWidth: member.tier == 0 ? 2 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(x: slot.x * scale + dx, y: slot.y * scale + dy)
        .accessibilityLabel(Text(member.student.primaryDisplayName))
        .accessibilityIdentifier("today.cluster.athlete")
    }
}
