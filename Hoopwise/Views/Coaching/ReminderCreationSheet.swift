import SwiftUI
import UserNotifications

// MARK: - Reminder Creation Sheet
/// Slack-style reminder creation sheet with date + time picker
struct ReminderCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager

    let sessionId: UUID?
    let programId: UUID?
    let coachId: UUID
    let suggestedTitle: String
    let onSave: (Reminder) -> Void

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var selectedDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var selectedPreset: QuickReminderPreset? = nil
    @State private var priority: ReminderPriority = .medium
    @State private var showingDatePicker = false
    @State private var notificationPermissionDenied = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    // Quick time presets
    private var quickPresets: [(label: String, icon: String, date: Date)] {
        let now = Date()
        let cal = Calendar.current
        return [
            (isChinese ? "1小时后" : "In 1 hour",     "clock",              cal.date(byAdding: .hour, value: 1, to: now) ?? now),
            (isChinese ? "明天上午" : "Tomorrow 9am",  "sunrise",            tomorrowAt(9)),
            (isChinese ? "下周一" : "Next Monday",     "calendar",           nextMonday()),
            (isChinese ? "自定义" : "Custom time",     "calendar.badge.clock", selectedDate)
        ]
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "提醒内容" : "Reminder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        TextField(isChinese ? "提醒我…" : "Remind me to…", text: $title)
                            .font(.system(size: 17))
                            .padding(12)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(10)
                    }

                    // Note field
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "备注（可选）" : "Note (optional)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        TextField(isChinese ? "添加备注…" : "Add a note…", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(10)
                    }

                    // Quick time presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "提醒时间" : "Remind me at")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(quickPresets.enumerated()), id: \.offset) { idx, preset in
                                let isCustom = idx == quickPresets.count - 1
                                Button {
                                    if isCustom {
                                        withAnimation { showingDatePicker.toggle() }
                                    } else {
                                        selectedDate = preset.date
                                        withAnimation { showingDatePicker = false }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 13, weight: .medium))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(preset.label)
                                                .font(.system(size: 13, weight: .medium))
                                            if !isCustom {
                                                Text(preset.date.formatted(date: .omitted, time: .shortened))
                                                    .font(.system(size: 11))
                                                    .opacity(0.7)
                                            }
                                        }
                                        Spacer()
                                        if !isCustom && selectedDate == preset.date {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                        }
                                    }
                                    .foregroundColor(isSelected(preset: preset, idx: idx) ? .white : .primary)
                                    .padding(12)
                                    .background(isSelected(preset: preset, idx: idx) ? Color.blue : Color.gray.opacity(0.12))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Inline date + time picker
                        if showingDatePicker {
                            VStack(spacing: 0) {
                                DatePicker(
                                    "",
                                    selection: $selectedDate,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .padding(.horizontal, 4)
                            }
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Selected time summary
                        HStack(spacing: 6) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "优先级" : "Priority")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                        HStack(spacing: 8) {
                            ForEach(ReminderPriority.allCases, id: \.self) { p in
                                Button {
                                    priority = p
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: p.icon)
                                            .font(.system(size: 12))
                                        Text(p.displayName)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(priority == p ? .white : p.color)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(priority == p ? p.color : p.color.opacity(0.12))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if notificationPermissionDenied {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.slash.fill")
                                .foregroundColor(.orange)
                            Text(isChinese ? "通知权限已关闭，请在设置中开启" : "Notifications are off. Enable in Settings to be reminded.")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(20)
            }
        .navigationTitle(isChinese ? "设置提醒" : "Set Reminder")
        .navigationBarTitleDisplayModeCompat(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isChinese ? "保存" : "Save") {
                    saveReminder()
                }
                .fontWeight(.semibold)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if !suggestedTitle.isEmpty {
                title = suggestedTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(80)
                    .description
            }
            checkNotificationPermission()
        }
    }

    // MARK: - Helpers

    private func isSelected(preset: (label: String, icon: String, date: Date), idx: Int) -> Bool {
        let isCustom = idx == quickPresets.count - 1
        if isCustom { return showingDatePicker }
        return Calendar.current.isDate(selectedDate, equalTo: preset.date, toGranularity: .minute)
    }

    private func tomorrowAt(_ hour: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.day = (comps.day ?? 0) + 1
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func nextMonday() -> Date {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.weekday = 2 // Monday
        comps.hour = 9
        comps.minute = 0
        return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? Date()
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationPermissionDenied = settings.authorizationStatus == .denied
            }
        }
    }

    private func saveReminder() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let reminder = Reminder(
            title: cleanTitle,
            note: note.isEmpty ? nil : note,
            dueDate: selectedDate,
            priority: priority,
            sessionId: sessionId,
            programId: programId,
            coachId: coachId,
            creatorCoachId: coachId
        )

        onSave(reminder)
        scheduleLocalNotification(for: reminder)
        dismiss()
    }

    private func scheduleLocalNotification(for reminder: Reminder) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Hoopwise"
            content.body = reminder.title
            if let note = reminder.note { content.subtitle = note }
            content.sound = .default

            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.dueDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            let request = UNNotificationRequest(
                identifier: reminder.id.uuidString,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    debugLog("❌ Failed to schedule notification: \(error)")
                } else {
                    debugLog("🔔 Reminder notification scheduled for \(reminder.dueDate)")
                }
            }
        }
    }
}
