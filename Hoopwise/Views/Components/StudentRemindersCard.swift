import SwiftUI

/// An athlete's open reminders — every reminder that tags them, wherever it
/// was written (a session's Reminders with "@", the reminder sheet, here) —
/// with the class it came from, and a one-line add that tags them
/// (14 November 2026, Luther: "@ should tag the student and attach the
/// reminder to their profile"). On the athlete profile and the quick peep.
struct StudentRemindersCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    /// Both the profile and the quick peep show it always, with its add line
    /// (Luther, 17 Nov 2026: add a reminder from the peep).
    var showWhenEmpty = true

    @State private var newTitle = ""
    @State private var editing: Reminder?
    @FocusState private var addFocused: Bool

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let open = dataManager.openReminders(taggedWith: student.id)
        if showWhenEmpty || !open.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label {
                        Text(isChinese ? "提醒" : "REMINDERS").font(.caption2.weight(.bold)).monospaced()
                    } icon: {
                        Image(systemName: "bell").font(.caption).foregroundStyle(.orange)
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    if !open.isEmpty {
                        Text("\(open.count)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                ForEach(open) { reminder in
                    row(reminder)
                    if reminder.id != open.last?.id { Divider().padding(.leading, 34) }
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    TextField(isChinese ? "给\(student.primaryDisplayName)加个提醒" : "Remind me about \(student.primaryDisplayName)…",
                              text: $newTitle)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("athlete.reminders.add")
                }
                .padding(.top, open.isEmpty ? 0 : 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.filmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sheet(item: $editing) { reminder in
                // Hand the store on explicitly: inside the quick peep (itself a
                // sheet) the environment object did not reach this sheet and
                // AddReminderSheet trapped on reading it (Mac, 15 Nov 2026).
                AddReminderSheet(sessionId: reminder.sessionId ?? UUID(), programId: reminder.programId,
                                 existingReminder: reminder)
                    .environmentObject(dataManager)
            }
            .accessibilityIdentifier("athlete.reminders")
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dataManager.toggleReminderCompletion(reminder)
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.statusColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title).font(.body)
                if let note = reminder.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Label(reminder.relativeTimeString, systemImage: "calendar")
                        .foregroundStyle(reminder.statusColor)
                    if let source = dataManager.reminderSource(reminder) {
                        Text(source).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = reminder }
        .contextMenu {
            Button { editing = reminder } label: { Label(isChinese ? "编辑" : "Edit", systemImage: "pencil") }
            Button(role: .destructive) { dataManager.deleteReminder(reminder) } label: {
                Label(isChinese ? "删除" : "Delete", systemImage: "trash")
            }
        }
    }

    /// Due tomorrow at 09:00, tagged with this athlete; no class attached.
    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let cal = Calendar.current
        let due = cal.date(bySettingHour: 9, minute: 0, second: 0,
                           of: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
        dataManager.addReminder(Reminder(title: title, dueDate: due, taggedStudentIds: [student.id]))
        newTitle = ""
        addFocused = true
    }
}
