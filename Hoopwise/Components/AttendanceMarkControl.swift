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

/// The attendance control, used by every iOS attendance surface: THREE
/// positions. Left = excused, middle = not marked, right = present.
/// (October 2026, the coach's design; a sanctioned exception to the iOS UI
/// freeze, see CLAUDE.md.)
///
/// November 2026 (Luther: "they slow down the system and aren't responsive
/// right away … if there is a native iOS 3-position control, use it"): it is
/// now the system SEGMENTED control. The hand-built switch sat on a
/// zero-distance drag gesture inside a List row, so it fought the list's
/// scroll and swipe recognisers for every touch, and its knob only moved once
/// the store write had come back. The segmented control answers on touch-down
/// and shows the new position at once (`selection` is local); the write
/// follows.
///
/// There is no position for ABSENT. Absent is what the middle MEANS once roll
/// call has started: `AttendanceInference` shows every still-middle student
/// as absent as soon as anyone on the session is marked, and writes (charges)
/// those absences an hour after class. Callers pass the EFFECTIVE mark, so an
/// inferred or recorded absence sits in the middle with the row captioned
/// "Absent".
///
/// The control itself only ever writes present, excused or unmarked.
struct AttendanceMarkControl: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    /// -1 excused, 0 not marked (or absent), +1 present.
    @State private var selection: Int

    init(mark: AttendanceMark, onChange: @escaping (AttendanceMark) -> Void) {
        self.mark = mark
        self.onChange = onChange
        _selection = State(initialValue: Self.position(of: mark))
    }

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private static func position(of mark: AttendanceMark) -> Int {
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

    var body: some View {
        Picker(isChinese ? "考勤" : "Attendance", selection: $selection) {
            Image(systemName: "clock")
                .accessibilityLabel(AttendanceMark.excused.label(isChinese: isChinese))
                .tag(-1)
            Image(systemName: "minus")
                .accessibilityLabel(AttendanceMark.unmarked.label(isChinese: isChinese))
                .tag(0)
            Image(systemName: "checkmark")
                .accessibilityLabel(AttendanceMark.present.label(isChinese: isChinese))
                .tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 132)
        // The chosen side carries its meaning's colour (excused orange,
        // present green); the middle stays neutral.
        .tint(selection == 1 ? .green : (selection == -1 ? .orange : nil))
        .onChange(of: selection) { _, new in
            let next = Self.mark(at: new)
            // An absence (recorded or inferred) sits in the middle; landing on
            // the middle again is not a change.
            guard new != Self.position(of: mark) else { return }
            onChange(next)
        }
        // The store (or "All present") moved the mark: follow it.
        .onChange(of: mark) { _, new in
            let position = Self.position(of: new)
            if selection != position { selection = position }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("attendanceControl")
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
