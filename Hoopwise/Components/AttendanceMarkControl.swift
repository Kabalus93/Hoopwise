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

/// One four-state control, used by every attendance surface.
///
/// There used to be two: a binary present/absent toggle in the Take Attendance
/// sheet and a three-way control in the session detail tab. Which states could
/// be recorded depended on which screen was open — and the binary toggle could
/// not express "excused" at all, so a notified absence recorded there consumed
/// a session. Discovering that courtside is exactly when it costs money.
struct AttendanceMarkControl: View {
    let mark: AttendanceMark
    var onChange: (AttendanceMark) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AttendanceMark.allCases) { candidate in
                Button {
                    guard candidate != mark else { return }
                    onChange(candidate)
                } label: {
                    Image(systemName: candidate.icon)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 34, height: 30)
                        .background(background(for: candidate))
                        .foregroundStyle(candidate == mark ? .white : candidate.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(candidate.tint.opacity(candidate == mark ? 0 : 0.45),
                                              style: StrokeStyle(lineWidth: 1,
                                                                 dash: candidate == .unmarked ? [3, 2] : []))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label(isChinese: isChinese))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: mark)
    }

    private func background(for candidate: AttendanceMark) -> some ShapeStyle {
        candidate == mark
            ? AnyShapeStyle(candidate.tint)
            : AnyShapeStyle(Color.clear)
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
    }
}
