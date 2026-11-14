import Foundation

// REMINDERS CARRY CONTEXT (14 November 2026, Luther: "using @ should tag the
// student and attach the reminder to their profile … make tagging work well
// throughout the app so that reminders and alerts are smart and carry
// context"). A reminder names its athletes (`taggedStudentIds`) and the class
// it came from (`sessionId`); this is the one place that turns those into
// words, and the one place "@" typing is understood. Coach tagging is gone
// from the UI (no other coaches use the app); stored coach tags are left
// alone.

enum ReminderMentions {

    /// The name being typed after an "@" at the end of the text — "@ma" →
    /// "ma", a bare "@" → "". nil when the caret is not in a mention (no
    /// "@", or a line break after it). The "@" must start the text or follow
    /// a space, so an email address is not a mention.
    static func activeQuery(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at != text.startIndex {
            let before = text[text.index(before: at)]
            guard before == " " || before == "\n" else { return nil }
        }
        let query = text[text.index(after: at)...]
        guard !query.contains("\n"), query.count <= 24 else { return nil }
        // Two words typed after the @ without a match is ordinary text again.
        guard query.split(separator: " ", omittingEmptySubsequences: false).count <= 2 else { return nil }
        return String(query)
    }

    /// The text with the trailing "@query" replaced by the athlete's name.
    static func inserting(_ name: String, into text: String) -> String {
        guard let at = text.lastIndex(of: "@") else { return text + name }
        return String(text[..<at]) + name + " "
    }

    /// Athletes the query finds (NameIndex: name, Chinese name, pinyin,
    /// initials), best first: those named in `preferred` (the
    /// session's roster) lead. An empty query lists `preferred`.
    @MainActor static func matches(_ query: String, in students: [Student], preferred: [UUID] = [], limit: Int = 6) -> [Student] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool: [Student]
        if q.isEmpty {
            pool = preferred.compactMap { id in students.first { $0.id == id } }
        } else {
            pool = students.filter { s in
                NameIndex.cached(name: s.name, secondary: s.chineseName).matches(q)
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: preferred.enumerated().map { ($1, $0) })
        return pool
            .sorted { (rank[$0.id] ?? Int.max, $0.primaryDisplayName) < (rank[$1.id] ?? Int.max, $1.primaryDisplayName) }
            .prefix(limit)
            .map { $0 }
    }
}

extension DataManager {

    /// Open reminders that name this athlete, soonest first.
    func openReminders(taggedWith studentId: UUID) -> [Reminder] {
        reminders.filter { !$0.isCompleted && $0.taggedStudentIds.contains(studentId) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    /// "from Elite U8 · Sat 26 Sep" — the class a reminder was written in.
    func reminderSource(_ reminder: Reminder) -> String? {
        guard let sessionId = reminder.sessionId,
              let session = cachedSessionEvents.first(where: { $0.id == sessionId }) else { return nil }
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let group = session.programId.flatMap { id in programs.first { $0.id == id }?.name } ?? session.title
        let day = session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return isChinese ? "来自 \(group) · \(day)" : "from \(group) · \(day)"
    }

    /// The athletes a reminder names, in display form.
    func reminderAthleteNames(_ reminder: Reminder) -> [String] {
        reminder.taggedStudentIds.compactMap { id in students.first { $0.id == id }?.primaryDisplayName }
    }

    /// One line of context for an alert: who, and which class.
    func reminderContext(_ reminder: Reminder) -> String? {
        let names = reminderAthleteNames(reminder)
        let who: String? = names.isEmpty ? nil : (names.count <= 2 ? names.joined(separator: ", ")
                                                                    : "\(names[0]) +\(names.count - 1)")
        let parts = [who, reminderSource(reminder)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
