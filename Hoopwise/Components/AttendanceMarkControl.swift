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

/// The attendance control, used by every iOS attendance surface: a native
/// switch. ON = present. Switching OFF records ABSENT.
///
/// The model keeps all FOUR states. The switch shows only present vs not:
/// - A student nobody has touched stays UNMARKED (switch off). The switch
///   never writes absent on its own — it records absent only when the coach
///   flips a present student off. Unmarked is NOT absent; for a private
///   bundle an absence deducts a session, so inferring one would invent a
///   charge.
/// - Excused, Absent-without-flipping, and Clear (back to unmarked) live in
///   `AttendanceMarkMenu` (long-press on the row) and in the session tab's
///   swipe actions. A notified absence must stay recordable as EXCUSED, or
///   it would consume a session — the reason the old binary toggle was
///   removed in the first place.
///
/// Decided October 2026 by the coach: the four-button strip was replaced by
/// this switch (a sanctioned exception to the iOS UI freeze, see CLAUDE.md).
struct AttendanceMarkControl: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var isPresent: Binding<Bool> {
        Binding(
            get: { mark == .present },
            set: { isOn in
                let next: AttendanceMark = isOn ? .present : .absent
                guard next != mark else { return }
                onChange(next)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isPresent) {
            Text(AttendanceMark.present.label(isChinese: isChinese))
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(.green)
        .accessibilityValue(mark.label(isChinese: isChinese))
        .sensoryFeedback(.impact(weight: .light), trigger: mark)
    }
}

/// Every attendance state as menu items, for a row's long-press menu.
/// This is how a coach reaches Excused, Absent and Clear without the switch.
struct AttendanceMarkMenu: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        ForEach(AttendanceMark.allCases) { candidate in
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
