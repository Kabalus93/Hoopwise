import SwiftUI

// GROUP FIT (25 Nov 2026, Luther, after the audit: grades promote themselves
// every September, but nothing noticed a child outgrowing a program — in age
// or in level). On the program page: who is OLDER than the group's age band,
// who is clearly above the group (the skill level's top — "could move up")
// and who is well behind (its bottom). A list to think about, never an alert
// and never shown to a child or parent. Group programs only.

enum GroupFit {
    enum Reason: Equatable { case older(AgeGroup), top, bottom }
    struct Signal: Identifiable, Equatable {
        let studentId: UUID
        let reasons: [Reason]
        var id: UUID { studentId }
    }

    private static let order: [AgeGroup] = [.u6, .u8, .u10, .u12, .u14, .u16, .u18, .adult]

    /// The band an age belongs in (the age on 1 September of the school
    /// year, so it does not flip on a birthday mid-season).
    static func band(forAge age: Int) -> AgeGroup {
        switch age {
        case ..<6: return .u6
        case 6...7: return .u8
        case 8...9: return .u10
        case 10...11: return .u12
        case 12...13: return .u14
        case 14...15: return .u16
        case 16...17: return .u18
        default: return .adult
        }
    }

    /// Older first, then the top of the group, then the bottom; members in
    /// the order given. An athlete playing UP (younger than the band) is the
    /// coach's choice and is not listed.
    static func signals(programAge: AgeGroup, members: [(id: UUID, age: Int?)],
                        tiers: [UUID: SkillTier]) -> [Signal] {
        let here = order.firstIndex(of: programAge) ?? 0
        var out: [Signal] = []
        for member in members {
            var reasons: [Reason] = []
            if let age = member.age {
                let theirs = band(forAge: age)
                if (order.firstIndex(of: theirs) ?? 0) > here { reasons.append(.older(theirs)) }
            }
            switch tiers[member.id] {
            case .best: reasons.append(.top)
            case .bottom: reasons.append(.bottom)
            default: break
            }
            if !reasons.isEmpty { out.append(Signal(studentId: member.id, reasons: reasons)) }
        }
        func rank(_ s: Signal) -> Int {
            if s.reasons.contains(where: { if case .older = $0 { return true } else { return false } }) { return 0 }
            return s.reasons.contains(.top) ? 1 : 2
        }
        return out.enumerated().sorted { a, b in
            rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }.map(\.element)
    }
}

struct GroupFitCard: View {
    @EnvironmentObject private var dataManager: DataManager
    let program: Program

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var signals: [GroupFit.Signal] {
        guard !SessionPrivacy.isPrivate(program) else { return [] }
        let members = program.enrolledStudentIds.compactMap { id in dataManager.students.first { $0.id == id } }
        return GroupFit.signals(programAge: program.ageGroup,
                                members: members.map { ($0.id, $0.ageAtSchoolYearStart()) },
                                tiers: dataManager.skillTiers.byProgram[program.id] ?? [:])
    }

    var body: some View {
        let signals = signals
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(isChinese ? "谁可能该换组" : "GROUP FIT").font(.caption.weight(.bold))
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down.circle").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text(isChinese ? "仅供教练参考" : "For the coach only").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(signals) { signal in
                        if let student = dataManager.students.first(where: { $0.id == signal.studentId }) {
                            NavigationLink(destination: StudentDetailView(student: student)) {
                                HStack(spacing: 12) {
                                    StudentAvatarView(student: student, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(student.primaryDisplayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(signal.reasons.map(text).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: icon(signal)).font(.subheadline.weight(.bold)).foregroundStyle(tint(signal))
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("program.groupFit.row")
                            if signal.id != signals.last?.id { Divider().padding(.leading, 50) }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("program.groupFit")
        }
    }

    private func text(_ reason: GroupFit.Reason) -> String {
        switch reason {
        case .older(let band):
            return isChinese ? "按年龄已到 \(band.rawValue)，高于本组的 \(program.ageGroup.rawValue)"
                             : "\(band.rawValue) by age — older than this \(program.ageGroup.rawValue) group"
        case .top: return isChinese ? "明显高于本组水平，可以考虑升组" : "Clearly above the group — could move up"
        case .bottom: return isChinese ? "明显落后，可能更适合低一级的组" : "Well behind the group — an easier group may fit better"
        }
    }

    private func icon(_ s: GroupFit.Signal) -> String { s.reasons.contains(.bottom) && s.reasons.count == 1 ? "arrow.down" : "arrow.up" }
    private func tint(_ s: GroupFit.Signal) -> Color { s.reasons.contains(.bottom) && s.reasons.count == 1 ? .purple : .orange }
}
