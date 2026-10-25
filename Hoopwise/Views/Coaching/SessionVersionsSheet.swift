import SwiftUI

// MARK: - Restore an earlier version of a session (October 2026)
//
// Built after games and attendance vanished from a class in progress (Luther,
// 25 October 2026). Every field-level write (each attendance mark, each game
// stat, the roll-call photo) and every whole-record write that would erase
// games or marks keeps a copy of the session first (SDEntityRevision, the
// last 10 per session). This lists them with what each one holds — games,
// stat lines, present / excused / absent — so the coach picks the version
// that still has the class, and restores it. Restoring keeps a copy of the
// current state too, so it can be undone the same way.

struct SessionVersionsSheet: View {
    let sessionId: UUID
    let students: [Student]
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [(id: UUID, createdAt: Date, actor: String?, event: SessionEvent)] = []
    @State private var pending: UUID?
    @State private var restored = false
    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            List {
                if let current = dataManager.sessionEvents.first(where: { $0.id == sessionId }) {
                    Section(zh ? "现在" : "Now") { summary(current, date: nil, actor: nil) }
                }
                Section {
                    if versions.isEmpty {
                        Text(zh ? "这节课还没有保存的版本。" : "No saved versions of this session yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(versions, id: \.id) { v in
                        Button { pending = v.id } label: { summary(v.event, date: v.createdAt, actor: v.actor) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text(zh ? "早前版本 · 点按恢复" : "Earlier versions · tap to restore")
                } footer: {
                    Text(zh ? "每次点名、比赛记录或覆盖前都会自动保存一份（最近 10 份）。恢复前会先保存当前版本。"
                            : "A copy is kept before every attendance mark, game change or overwrite (the last 10). Restoring keeps the current version first, so it can be undone.")
                }
            }
            .navigationTitle(zh ? "恢复早前版本" : "Restore Earlier Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "完成" : "Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .alert(zh ? "恢复这个版本？" : "Restore this version?", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button(zh ? "取消" : "Cancel", role: .cancel) { pending = nil }
                Button(zh ? "恢复" : "Restore") {
                    if let id = pending, dataManager.restoreSession(toRevisionId: id) {
                        restored = true
                        HapticFeedback.notification(.success)
                    }
                    pending = nil
                    load()
                }
            } message: {
                Text(zh ? "比赛、点名和照片会恢复成这个版本的内容。" : "Games, attendance and the photo go back to what this version holds.")
            }
            .overlay(alignment: .bottom) {
                if restored {
                    Text(zh ? "已恢复" : "Restored")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 24)
                }
            }
        }
        .accessibilityIdentifier("session.versions")
    }

    private func load() { versions = dataManager.sessionRevisions(for: sessionId) }

    private func summary(_ e: SessionEvent, date: Date?, actor: String?) -> some View {
        let stats = e.games.reduce(0) { $0 + $1.playerStats.count }
        let points = e.games.flatMap(\.playerStats).reduce(0) { $0 + $1.points }
        return VStack(alignment: .leading, spacing: 4) {
            if let date {
                HStack {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()
                        .locale(Locale(identifier: zh ? "zh_CN" : "en_GB"))))
                        .font(.subheadline.weight(.semibold))
                    if let actor, actor == "Before overwrite" {
                        Text(zh ? "覆盖前" : "before overwrite")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack(spacing: 14) {
                label("sportscourt", zh ? "\(e.games.count) 场比赛" : "\(e.games.count) games")
                label("chart.bar", zh ? "\(stats) 条数据 · \(points) 分" : "\(stats) stat lines · \(points) pts")
            }
            HStack(spacing: 14) {
                label("checkmark.circle", zh ? "出勤 \(e.actualAttendeeIds.count)" : "\(e.actualAttendeeIds.count) present")
                label("hand.raised", zh ? "请假 \(e.excusedAbsences.count)" : "\(e.excusedAbsences.count) excused")
                label("xmark.circle", zh ? "缺席 \(e.unexcusedAbsences.count)" : "\(e.unexcusedAbsences.count) absent")
                if e.attendancePhotoPath != nil { label("camera", zh ? "照片" : "photo") }
            }
        }
        .padding(.vertical, 2)
    }

    private func label(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    }
}
