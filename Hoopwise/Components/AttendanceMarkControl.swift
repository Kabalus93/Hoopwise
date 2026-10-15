import SwiftUI

/// The four attendance states, as the coach sees them.
///
/// Two of these consume a prepaid session and two do not, so the control must
/// make the difference obvious at a glance — this gets used courtside, quickly,
/// and a mis-tap costs the price of a session.
enum AttendanceMark: String, CaseIterable, Identifiable {
    /// Attendance not taken yet. Consumes nothing.
    case unmarked
    /// Attended. Consumes a session.
    case present
    /// Notified in advance. Session preserved.
    case excused
    /// Unexcused absence — no-show, or notice too late. Consumes a session
    /// under clause 4 of the training agreement.
    case absent

    var id: String { rawValue }

    /// Whether choosing this state charges the client a prepaid session.
    var consumesSession: Bool {
        switch self {
        case .present, .absent:   return true
        case .unmarked, .excused: return false
        }
    }

    var icon: String {
        switch self {
        case .unmarked: return "circle.dashed"
        case .present:  return "checkmark"
        case .excused:  return "clock"
        case .absent:   return "xmark"
        }
    }

    var tint: Color {
        switch self {
        case .unmarked: return .secondary
        case .present:  return .green
        case .excused:  return .orange
        case .absent:   return .red
        }
    }

    func label(isChinese: Bool) -> String {
        switch self {
        case .unmarked: return isChinese ? "未记录" : "Not marked"
        case .present:  return isChinese ? "出席"   : "Present"
        case .excused:  return isChinese ? "请假"   : "Excused"
        case .absent:   return isChinese ? "缺席"   : "Absent"
        }
    }

    /// Shown under the control so the money consequence is never implicit.
    func consequence(isChinese: Bool) -> String {
        switch self {
        case .unmarked: return isChinese ? "不扣课时" : "No session deducted"
        case .present:  return isChinese ? "扣除 1 课时" : "Deducts 1 session"
        case .excused:  return isChinese ? "不扣课时" : "No session deducted"
        case .absent:   return isChinese ? "扣除 1 课时" : "Deducts 1 session"
        }
    }
}

/// The attendance control, used by every iOS attendance surface: a
/// THREE-POSITION switch. Left = excused, middle = not marked, right =
/// present. (October 2026, the coach's design; a sanctioned exception to the
/// iOS UI freeze, see CLAUDE.md.)
///
/// There is no position for ABSENT. Absent is what the middle MEANS once roll
/// call has started: `AttendanceInference` shows every still-middle student
/// as absent as soon as anyone on the session is marked, and writes (charges)
/// those absences an hour after class. Callers pass the EFFECTIVE mark, so an
/// inferred or recorded absence sits in the middle with the row captioned
/// "Absent".
///
/// The control itself only ever writes present, excused or unmarked.
/// Tap a side to move there, tap the middle to return to not marked, or drag
/// the knob; VoiceOver adjusts it with increment / decrement.
struct AttendanceMarkControl: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    @State private var dragOffset: CGFloat?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private static let width: CGFloat = 84
    private static let height: CGFloat = 32
    private static let knob: CGFloat = 28
    /// Knob travel from the middle to either side.
    private static let travel: CGFloat = (width - 4 - knob) / 2

    /// -1 excused, 0 not marked (or absent), +1 present.
    private var position: Int {
        switch mark {
        case .present:            return 1
        case .excused:            return -1
        case .unmarked, .absent:  return 0
        }
    }

    private static func mark(at position: Int) -> AttendanceMark {
        switch position {
        case 1:  return .present
        case -1: return .excused
        default: return .unmarked
        }
    }

    private var trackTint: Color {
        switch position {
        case 1:  return .green
        case -1: return .orange
        default: return Color(.tertiarySystemFill)
        }
    }

    private func move(to newPosition: Int) {
        let clamped = max(-1, min(1, newPosition))
        let next = Self.mark(at: clamped)
        // An absence (recorded or inferred) sits in the middle; landing on the
        // middle again is not a change.
        guard clamped != position else { return }
        onChange(next)
    }

    var body: some View {
        let knobX = dragOffset ?? CGFloat(position) * Self.travel

        ZStack {
            Capsule()
                .fill(trackTint)
            HStack {
                Image(systemName: "clock")
                    .opacity(position == -1 ? 0 : 0.55)
                Spacer()
                Image(systemName: "checkmark")
                    .opacity(position == 1 ? 0 : 0.55)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(position == 0 ? Color.secondary : Color.white)
            .padding(.horizontal, 9)

            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .frame(width: Self.knob, height: Self.knob)
                .offset(x: knobX)
        }
        .frame(width: Self.width, height: Self.height)
        .contentShape(Capsule())
        .animation(.snappy(duration: 0.2), value: position)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard abs(value.translation.width) > 4 else { return }
                    let start = CGFloat(position) * Self.travel
                    dragOffset = max(-Self.travel, min(Self.travel, start + value.translation.width))
                }
                .onEnded { value in
                    defer { dragOffset = nil }
                    if abs(value.translation.width) <= 4 {
                        // A tap: left third, middle third, right third.
                        let x = value.location.x
                        let third = Self.width / 3
                        move(to: x < third ? -1 : (x > third * 2 ? 1 : 0))
                    } else {
                        let landed = (dragOffset ?? 0) / Self.travel
                        move(to: Int(landed.rounded()))
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: mark)
        .accessibilityElement()
        .accessibilityIdentifier("attendanceControl")
        .accessibilityLabel(isChinese ? "考勤" : "Attendance")
        .accessibilityValue(mark.label(isChinese: isChinese))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: position + 1)
            case .decrement: move(to: position - 1)
            @unknown default: break
            }
        }
    }
}

/// Every attendance state as menu items, for a row's long-press menu.
/// Present, Excused and Clear, for a coach who prefers the long-press menu.
struct AttendanceMarkMenu: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        // No explicit Absent: absent is what an unmarked student becomes once
        // roll call has started (AttendanceInference), not something chosen.
        ForEach([AttendanceMark.present, .excused, .unmarked]) { candidate in
            Button {
                onChange(candidate)
            } label: {
                Label(menuTitle(for: candidate), systemImage: candidate.icon)
            }
            .disabled(candidate == mark)
        }
    }

    /// "Clear" is the action that returns a row to UNMARKED; the money
    /// consequence is spelled out because two of the four states charge.
    private func menuTitle(for candidate: AttendanceMark) -> String {
        let name = candidate == .unmarked
            ? (isChinese ? "清除" : "Clear")
            : candidate.label(isChinese: isChinese)
        return "\(name) · \(candidate.consequence(isChinese: isChinese))"
    }
}

/// A student row with the shared control, plus the money consequence in words.
struct AttendanceStudentRow: View {
    let student: Student
    let mark: AttendanceMark
    /// Set when this session has already consumed one of the student's prepaid
    /// sessions, so the refund action can be offered.
    var isRedeemed: Bool = false
    var onChange: (AttendanceMark) -> Void
    var onRefund: (() -> Void)?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 5) {
                        Text(mark.label(isChinese: isChinese))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(mark.tint)
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(mark.consequence(isChinese: isChinese))
                            .font(.caption2)
                            .foregroundStyle(mark.consumesSession ? .secondary : .tertiary)
                    }
                }
                Spacer()
                AttendanceMarkControl(mark: mark, onChange: onChange)
            }

            // Only offered when a session was actually charged — an undo that
            // does nothing is worse than no undo.
            if isRedeemed, let onRefund {
                Button(role: .destructive) {
                    onRefund()
                } label: {
                    Label(isChinese ? "退回该课时" : "Return this session to the bundle",
                          systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(mark == .unmarked
                      ? AnyShapeStyle(HierarchicalShapeStyle.quinary)
                      : AnyShapeStyle(mark.tint.opacity(0.10)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(mark == .unmarked ? Color.secondary.opacity(0.25) : mark.tint.opacity(0.3),
                              style: StrokeStyle(lineWidth: 1,
                                                 dash: mark == .unmarked ? [4, 3] : []))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            AttendanceMarkMenu(mark: mark, onChange: onChange)
        }
    }
}
