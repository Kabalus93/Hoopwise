import SwiftUI

// STORED, NEVER SHOWN (25 Nov 2026, Luther, after the audit). Medical notes,
// the second guardian and the parent contact log were in the store with no
// screen to enter or read them (the contact log only through the Claude
// connector). Medical notes now show WHERE THE CHILD IS: the roster row and
// the top of the Quick Peep and profile; the contact log is a card on the
// profile and the peep, and a shared progress report is logged in it.

/// The red cross beside a name on the roster: this athlete has a medical note.
struct MedicalFlag: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID
    var body: some View {
        if dataManager.medicalNote(for: studentId) != nil {
            Image(systemName: "cross.case.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .accessibilityLabel(LocalizationManager.shared.currentLanguage == .chinese ? "有健康备注" : "Has a medical note")
                .accessibilityIdentifier("athlete.medicalFlag")
        }
    }
}

/// The note itself, at the top of the peep and the profile.
struct MedicalNoteBanner: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID
    var body: some View {
        if let note = dataManager.medicalNote(for: studentId) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cross.case.fill").font(.subheadline.weight(.bold)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "健康与安全" : "HEALTH AND SAFETY")
                        .font(.caption2.weight(.bold)).foregroundStyle(.red)
                    Text(note).font(.subheadline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("athlete.medicalNote")
        }
    }
}

/// Contacts with the family: the last few, and a way to log one.
struct ParentContactCard: View {
    @EnvironmentObject private var dataManager: DataManager
    let studentId: UUID
    @State private var logging: ParentalTouchpoint.TouchpointType?
    @State private var note = ""
    @State private var showingAll = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var contacts: [ParentalTouchpoint] {
        (dataManager.students.first { $0.id == studentId }?.parentalTouchpoints ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        let all = contacts
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(isChinese ? "与家长的联系" : "CONTACT WITH THE FAMILY").font(.caption.weight(.bold))
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.caption).foregroundStyle(Color.accentColor)
                }
                Spacer()
                Menu {
                    ForEach(ParentalTouchpoint.TouchpointType.allCases, id: \.self) { type in
                        Button { note = ""; logging = type } label: { Label(Self.title(type, chinese: isChinese), systemImage: type.icon) }
                    }
                } label: {
                    Label(isChinese ? "记录" : "Log", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
                .accessibilityIdentifier("contact.log")
            }
            if all.isEmpty {
                Text(isChinese ? "还没有记录。打电话、发消息或面谈后记一笔，就知道上次联系是什么时候。"
                               : "Nothing logged yet. Log a call, a message or a talk and you will know when you last spoke.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(showingAll ? all : Array(all.prefix(3))) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: c.type.icon).font(.caption).foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.title(c.type, chinese: isChinese) + " · " + c.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.footnote.weight(.semibold))
                            if let n = c.notes, !n.isEmpty {
                                Text(n).font(.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("contact.row")
                }
                if all.count > 3 {
                    Button(showingAll ? (isChinese ? "收起" : "Show fewer") : (isChinese ? "全部 \(all.count) 条" : "All \(all.count)")) {
                        withAnimation { showingAll.toggle() }
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contact.card")
        .alert(logging.map { Self.title($0, chinese: isChinese) } ?? "", isPresented: Binding(get: { logging != nil }, set: { if !$0 { logging = nil } })) {
            TextField(isChinese ? "说了什么（可不填）" : "What was said (optional)", text: $note)
            Button(isChinese ? "保存" : "Save") {
                if let type = logging { dataManager.logParentContact(studentId: studentId, type: type, note: note) }
                logging = nil
            }
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { logging = nil }
        }
    }

    static func title(_ type: ParentalTouchpoint.TouchpointType, chinese: Bool) -> String {
        switch type {
        case .call: return chinese ? "电话" : "Phone call"
        case .message: return chinese ? "消息 / 微信" : "Message / WeChat"
        case .inPerson: return chinese ? "当面" : "In person"
        case .email: return chinese ? "邮件" : "Email"
        case .reportCard: return chinese ? "发了报告" : "Report sent"
        case .meeting: return chinese ? "家长会" : "Parent meeting"
        }
    }
}

extension SwiftDataManager {
    /// The athlete's medical note, when there is one.
    func medicalNote(for studentId: UUID) -> String? {
        let note = players.first { $0.studentId == studentId }?.medicalNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? nil : note
    }

    /// One contact with the family, onto the STORED athlete.
    func logParentContact(studentId: UUID, type: ParentalTouchpoint.TouchpointType, note: String, at date: Date = Date()) {
        guard var student = students.first(where: { $0.id == studentId }) else { return }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        student.parentalTouchpoints.append(ParentalTouchpoint(date: date, type: type, notes: text.isEmpty ? nil : text))
        student.lastParentContact = date
        student.updatedAt = Date()
        updateStudent(student)
    }
}
