import SwiftUI

// Right-click menus on the Mac (Luther, November 2026). Mac Catalyst only —
// on iPhone and iPad these add nothing, so no long-press menu appears there.
// Every action goes through what the app's own screens use: the widget
// deep-link notifications to open a record, setStudentAttendanceStates for
// attendance (the one redemption authority), EditStudentView to edit.

extension Notification.Name {
    /// ⌘F: go to Athletes and focus its search.
    static let hoopwiseFindAthlete = Notification.Name("hoopwiseFindAthlete")
    static let hoopwiseFocusAthleteSearch = Notification.Name("hoopwiseFocusAthleteSearch")
    /// ⇧⌘N: go to Athletes and open Add Athlete.
    static let hoopwiseNewAthlete = Notification.Name("hoopwiseNewAthlete")
    static let hoopwiseOpenAddAthlete = Notification.Name("hoopwiseOpenAddAthlete")
    /// ⌘N: go to Sessions (calendar) and open Add Session.
    static let hoopwiseNewSessionCommand = Notification.Name("hoopwiseNewSessionCommand")
    static let hoopwiseNewSession = Notification.Name("hoopwiseNewSession")
    static let hoopwiseOpenAddSession = Notification.Name("hoopwiseOpenAddSession")
}

extension View {
    /// A session row's right-click menu (Mac only).
    func sessionMacMenu(_ session: SessionEvent) -> some View {
        modifier(SessionMacMenu(session: session))
    }

    /// An athlete row's right-click menu (Mac only).
    func athleteMacMenu(_ student: Student) -> some View {
        modifier(AthleteMacMenu(student: student))
    }
}

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

struct SessionMacMenu: ViewModifier {
    let session: SessionEvent
    @EnvironmentObject private var dataManager: DataManager
    @State private var confirmingAllPresent = false

    /// Expected, not yet present or excused — what "All present" marks.
    private var toMark: [UUID] {
        AttendanceMath.expectedIds(of: session, programs: dataManager.programs).filter {
            !session.actualAttendeeIds.contains($0) && !session.excusedAbsences.contains($0)
        }
    }

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .contextMenu {
                Button {
                    NotificationCenter.default.post(name: .hoopwiseOpenSessionRequest, object: session.id)
                } label: { Label(isChinese ? "打开" : "Open", systemImage: "arrow.up.forward.app") }
                Button {
                    confirmingAllPresent = true
                } label: { Label(isChinese ? "全部到场" : "Mark Everyone Present", systemImage: "checkmark.circle") }
                .disabled(toMark.isEmpty || SessionLifecycle.didNotHappen(session))
                Divider()
                Button {
                    UIPasteboard.general.string = details
                } label: { Label(isChinese ? "复制详情" : "Copy Details", systemImage: "doc.on.doc") }
            }
            .confirmationDialog(
                isChinese ? "将 \(toMark.count) 名学员标记为到场？" : "Mark \(toMark.count) present?",
                isPresented: $confirmingAllPresent, titleVisibility: .visible
            ) {
                Button(isChinese ? "全部到场" : "Mark all present") {
                    dataManager.setStudentAttendanceStates(
                        sessionId: session.id,
                        states: Dictionary(uniqueKeysWithValues: toMark.map { ($0, AttendanceTriState.present) }))
                }
            } message: {
                Text(isChinese
                     ? "每位到场学员扣除 1 课时（如有课时包）。请假的学员不变。"
                     : "Each present student uses 1 session from their balance, if they have one. Excused students stay excused.")
            }
        #else
        content
        #endif
    }

    private var details: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isChinese ? "zh_CN" : "en_GB")
        formatter.dateFormat = isChinese ? "M月d日 EEE HH:mm" : "EEE d MMM, HH:mm"
        let end = DateFormatter.localizedString(from: session.endTime, dateStyle: .none, timeStyle: .short)
        var parts = [session.title, "\(formatter.string(from: session.startTime))–\(end)"]
        if let location = session.location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }
}

struct AthleteMacMenu: ViewModifier {
    let student: Student
    @EnvironmentObject private var dataManager: DataManager
    @State private var editing = false

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .contextMenu {
                Button {
                    NotificationCenter.default.post(name: .hoopwiseOpenAthleteRequest, object: student.id)
                } label: { Label(isChinese ? "打开档案" : "Open Profile", systemImage: "person.crop.circle") }
                Button {
                    editing = true
                } label: { Label(isChinese ? "编辑" : "Edit", systemImage: "pencil") }
                Divider()
                Button {
                    UIPasteboard.general.string = [student.chineseName, student.name]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                } label: { Label(isChinese ? "复制姓名" : "Copy Name", systemImage: "doc.on.doc") }
            }
            .sheet(isPresented: $editing) {
                EditStudentView(student: student, player: dataManager.player(for: student.id))
            }
        #else
        content
        #endif
    }
}
