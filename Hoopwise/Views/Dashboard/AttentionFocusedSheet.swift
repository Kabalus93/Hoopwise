import SwiftUI

// MARK: - Focused Attention Sheet
/// Single-category drill-down for the dashboard's attention chips.
/// The catch-all `AllAttentionItemsSheet` still exists for the "see
/// everything" affordance — this sheet is for "I want to clear the
/// close-out queue right now" or "show me dormant clients" without
/// scrolling past unrelated cards.
struct AttentionFocusedSheet: View {
    let category: AttentionCategory
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager

    var onSelectStudent: (Student) -> Void
    var onSelectSession: (SessionEvent) -> Void
    var onSelectProgram: (Program) -> Void

    @State private var now = Date()

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var items: [AttentionItem] {
        AttentionInbox.compute(from: dataManager, now: now).items(in: category)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(category.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(isChinese ? "全部就绪" : "All clear", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        } description: {
            Text(emptyMessage)
        }
    }

    private var emptyMessage: String {
        switch category {
        case .closeOut:
            return isChinese
                ? "没有需要收尾的训练或提醒。"
                : "No sessions or reminders to close out."
        case .reEngage:
            return isChinese
                ? "所有私教学员近期都在出席。"
                : "All private clients have attended recently."
        case .plan:
            return isChinese
                ? "未来两周的课程都已排好。"
                : "Everything in the next two weeks is planned."
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for item: AttentionItem) -> some View {
        switch item.payload {
        case .session(let id):
            sessionRow(item: item, sessionId: id)
        case .student(let id):
            studentRow(item: item, studentId: id)
        case .program(let id):
            programRow(item: item, programId: id)
        case .reminder(let id):
            reminderRow(item: item, reminderId: id)
        }
    }

    /// Session row — used for both "close out" past sessions and "plan"
    /// unplanned sessions. Swipe actions are tailored per category.
    private func sessionRow(item: AttentionItem, sessionId: UUID) -> some View {
        let session = dataManager.sessionEvents.first { $0.id == sessionId }
        return Button {
            guard let session else { return }
            dismiss()
            onSelectSession(session)
        } label: {
            attentionRowContent(item: item)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if category == .closeOut, let session {
                // Through the state machine, not raw writes — a disallowed
                // transition (e.g. "complete" on an already auto-closed
                // session) is a silent no-op instead of a rule bypass.
                Button {
                    var updated = session
                    // A past scheduled session completes via the legal
                    // start→complete chain — coach-completed, no marker.
                    if updated.status == .scheduled {
                        SessionLifecycle.apply(.start, to: &updated)
                    }
                    if SessionLifecycle.apply(.complete, to: &updated) {
                        dataManager.updateSessionEvent(updated)
                        refresh()
                    }
                } label: {
                    Label(isChinese ? "完成" : "Mark complete", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)

                Button {
                    var updated = session
                    if SessionLifecycle.apply(.cancel, to: &updated) {
                        dataManager.updateSessionEvent(updated)
                        refresh()
                    }
                } label: {
                    Label(isChinese ? "取消" : "Cancel", systemImage: "xmark.circle.fill")
                }
                .tint(.orange)
            }
        }
    }

    private func studentRow(item: AttentionItem, studentId: UUID) -> some View {
        let student = dataManager.students.first { $0.id == studentId }
        return Button {
            guard let student else { return }
            dismiss()
            onSelectStudent(student)
        } label: {
            attentionRowContent(item: item)
        }
        .buttonStyle(.plain)
    }

    private func programRow(item: AttentionItem, programId: UUID) -> some View {
        let program = dataManager.programs.first { $0.id == programId }
        return Button {
            guard let program else { return }
            dismiss()
            onSelectProgram(program)
        } label: {
            attentionRowContent(item: item)
        }
        .buttonStyle(.plain)
    }

    private func reminderRow(item: AttentionItem, reminderId: UUID) -> some View {
        let reminder = dataManager.reminders.first { $0.id == reminderId }
        return Button {
            // Tapping the row toggles completion — that's the most likely
            // intent for an overdue reminder. Long-press to navigate would
            // be ideal but reminders don't have a detail page yet.
            if let reminder {
                dataManager.toggleReminderCompletion(reminder)
                refresh()
            }
        } label: {
            attentionRowContent(item: item, trailingIcon: "checkmark.circle")
        }
        .buttonStyle(.plain)
    }

    private func attentionRowContent(item: AttentionItem, trailingIcon: String = "chevron.right") -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityTint(item.severity).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(severityTint(item.severity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let ctx = item.timeContext {
                        if item.subtitle != nil {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(ctx)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: trailingIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func severityTint(_ severity: AttentionSeverity) -> Color {
        switch severity {
        case .urgent:    return .red
        case .attention: return .orange
        case .fyi:       return .blue
        }
    }

    /// Force the items list to recompute after a swipe action — `now` is
    /// just a trigger; the values come back through `attentionInbox`.
    private func refresh() {
        now = Date()
    }
}
