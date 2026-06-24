import SwiftUI
import Combine
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private func notesBoardCompressJPEG(_ data: Data) -> Data? {
    #if canImport(UIKit)
    guard let img = UIImage(data: data) else { return nil }
    return img.jpegData(compressionQuality: 0.75)
    #else
    guard let img = NSImage(data: data),
          let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    #endif
}

private func notesBoardImage(_ data: Data) -> Image? {
    #if canImport(UIKit)
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
    #else
    guard let img = NSImage(data: data) else { return nil }
    return Image(nsImage: img)
    #endif
}

// MARK: - Note Phase (before/during/after relative to session time)
enum NotePhase: String, Codable, Hashable {
    case before
    case during
    case after

    var label: String {
        switch self {
        case .before: return "Before Session"
        case .during: return "During Session"
        case .after:  return "After Session"
        }
    }
    var labelChinese: String {
        switch self {
        case .before: return "课前"
        case .during: return "课中"
        case .after:  return "课后"
        }
    }
    var color: Color {
        switch self {
        case .before: return .blue
        case .during: return .orange
        case .after:  return .green
        }
    }
}

// MARK: - Activity Target
enum ActivityTarget: Codable, Equatable {
    case student(id: UUID, name: String)
    case game(number: Int)
    case statusChange(from: String, to: String)
    case scheduleEdit(detail: String)
    case attendance(studentName: String, present: Bool)
    case score(gameNumber: Int, detail: String)
    case generic(label: String)

    var displayText: String {
        switch self {
        case .student(_, let name): return "#\(name)"
        case .game(let n): return "Game \(n)"
        case .statusChange(_, let to): return to
        case .scheduleEdit(let d): return d
        case .attendance(let name, _): return "#\(name)"
        case .score(let n, let d): return "Game \(n) · \(d)"
        case .generic(let l): return l
        }
    }

    var isStudent: Bool {
        if case .student = self { return true }
        if case .attendance = self { return true }
        return false
    }
}

// MARK: - Session Note Type
enum SessionNoteType: Codable, Equatable {
    case humanPost
    case activityEvent(verb: String, target: ActivityTarget)

    var isActivity: Bool {
        if case .activityEvent = self { return true }
        return false
    }

    var sfSymbol: String {
        guard case .activityEvent(let verb, _) = self else { return "bubble.left" }
        switch verb {
        case _ where verb.contains("added") || verb.contains("joined"): return "person.badge.plus"
        case _ where verb.contains("removed") || verb.contains("left"): return "person.badge.minus"
        case _ where verb.contains("status"): return "arrow.triangle.2.circlepath"
        case _ where verb.contains("game"): return "sportscourt"
        case _ where verb.contains("schedule") || verb.contains("rescheduled"): return "calendar.badge.clock"
        case _ where verb.contains("attendance"): return "checkmark.circle"
        case _ where verb.contains("score"): return "number.circle"
        default: return "bolt.fill"
        }
    }
}

// MARK: - Board Note Model
struct BoardNote: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionId: UUID
    let authorId: UUID
    let authorName: String
    let authorImageUrl: String?
    var body: String
    var mentionedCoachIds: [UUID]
    var taggedStudentIds: [UUID]
    var attachmentImageData: Data?
    var authorImageData: Data?
    let timestamp: Date
    let phase: NotePhase
    var noteType: SessionNoteType

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        authorId: UUID,
        authorName: String,
        authorImageUrl: String? = nil,
        authorImageData: Data? = nil,
        body: String,
        mentionedCoachIds: [UUID] = [],
        taggedStudentIds: [UUID] = [],
        attachmentImageData: Data? = nil,
        timestamp: Date = Date(),
        phase: NotePhase,
        noteType: SessionNoteType = .humanPost
    ) {
        self.id = id
        self.sessionId = sessionId
        self.authorId = authorId
        self.authorName = authorName
        self.authorImageUrl = authorImageUrl
        self.authorImageData = authorImageData
        self.body = body
        self.mentionedCoachIds = mentionedCoachIds
        self.taggedStudentIds = taggedStudentIds
        self.attachmentImageData = attachmentImageData
        self.timestamp = timestamp
        self.phase = phase
        self.noteType = noteType
    }

    /// Convenience factory for activity events
    static func activity(
        sessionId: UUID,
        actorId: UUID,
        actorName: String,
        verb: String,
        target: ActivityTarget,
        phase: NotePhase
    ) -> BoardNote {
        BoardNote(
            sessionId: sessionId,
            authorId: actorId,
            authorName: actorName,
            body: "\(verb) \(target.displayText)",
            phase: phase,
            noteType: .activityEvent(verb: verb, target: target)
        )
    }
}

// MARK: - Board Notes Store
/// Lightweight UserDefaults-backed store for BoardNotes, keyed by sessionId.
final class BoardNotesStore: ObservableObject {
    static let shared = BoardNotesStore()
    @Published private(set) var notesBySession: [UUID: [BoardNote]] = [:]
    private let key = "session_notes_board_v1"

    /// Minimal patch payload for pushing board_notes_json to Supabase
    private struct BoardNotesPatch: Encodable {
        let boardNotesJson: String
        let updatedAt: Date
    }

    private init() { load() }

    func notes(for sessionId: UUID) -> [BoardNote] {
        (notesBySession[sessionId] ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    func add(_ note: BoardNote) {
        var list = notesBySession[note.sessionId] ?? []
        list.append(note)
        notesBySession[note.sessionId] = list
        save()
        pushToCloud(sessionId: note.sessionId)
    }

    func delete(_ note: BoardNote) {
        guard !note.noteType.isActivity else { return }
        notesBySession[note.sessionId]?.removeAll { $0.id == note.id }
        save()
        pushToCloud(sessionId: note.sessionId)
    }

    func update(_ note: BoardNote) {
        guard !note.noteType.isActivity else { return }
        if let idx = notesBySession[note.sessionId]?.firstIndex(where: { $0.id == note.id }) {
            notesBySession[note.sessionId]?[idx] = note
            save()
            pushToCloud(sessionId: note.sessionId)
        }
    }

    /// Replace all notes for a session (used by syncFromCloud merge)
    func replaceNotes(for sessionId: UUID, with notes: [BoardNote]) {
        notesBySession[sessionId] = notes
        save()
    }

    /// Append an activity event note — call this from any mutating session action
    func appendActivity(
        sessionId: UUID,
        actorId: UUID,
        actorName: String,
        verb: String,
        target: ActivityTarget,
        phase: NotePhase
    ) {
        let note = BoardNote.activity(
            sessionId: sessionId,
            actorId: actorId,
            actorName: actorName,
            verb: verb,
            target: target,
            phase: phase
        )
        add(note)
    }

    /// Pull notes for a session from Supabase and merge with local (cloud wins for non-conflicting notes)
    func loadFromCloud(sessionId: UUID) {
        Task {
            do {
                let rows: [SessionNotesRow] = try await SupabaseManager.shared.fetchWithFilter(
                    from: "session_events",
                    column: "id",
                    op: .eq,
                    value: sessionId.uuidString
                )
                guard let row = rows.first,
                      let jsonString = row.boardNotesJson,
                      let data = jsonString.data(using: .utf8),
                      let cloudNotes = try? JSONDecoder().decode([BoardNote].self, from: data) else { return }

                await MainActor.run {
                    // Merge: union by note ID, cloud wins on conflict
                    var merged: [UUID: BoardNote] = [:]
                    for note in (self.notesBySession[sessionId] ?? []) { merged[note.id] = note }
                    for note in cloudNotes { merged[note.id] = note }
                    self.notesBySession[sessionId] = Array(merged.values)
                    self.save()
                }
            } catch {
                debugLog("⚠️ BoardNotesStore: failed to load from cloud for \(sessionId): \(error)")
            }
        }
    }

    private func pushToCloud(sessionId: UUID) {
        let notes = notesBySession[sessionId] ?? []
        guard let jsonData = try? JSONEncoder().encode(notes),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let patch = BoardNotesPatch(boardNotesJson: jsonString, updatedAt: Date())
        Task {
            do {
                try await SupabaseManager.shared.update(
                    table: "session_events",
                    id: sessionId,
                    data: patch
                )
            } catch {
                debugLog("⚠️ BoardNotesStore: failed to push to cloud for \(sessionId): \(error)")
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notesBySession) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([UUID: [BoardNote]].self, from: data) else { return }
        notesBySession = decoded
    }
}

/// Minimal Supabase row for reading boardNotesJson from session_events
private struct SessionNotesRow: Decodable {
    let id: UUID
    let boardNotesJson: String?
}

// MARK: - Session Notes Board
struct SessionNotesBoard: View {
    @EnvironmentObject var dataManager: DataManager
    let session: SessionEvent
    let accessMode: SessionAccessMode
    let programColor: Color
    /// Optional note id to scroll to and highlight (deep link)
    let highlightNoteId: UUID?

    @StateObject private var store = BoardNotesStore.shared
    @State private var composerText = ""
    @State private var showMentionPicker = false
    @State private var showStudentPicker = false
    @State private var showPlusMenu = false
    @State private var mentionSearchText = ""
    @State private var studentSearchText = ""
    @State private var showPhotoPicker = false
    @State private var showReminderSheet = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingMentionCoachIds: [UUID] = []
    @State private var pendingTagStudentIds: [UUID] = []
    @State private var highlightOpacity: Double = 0
    @State private var highlightedNoteId: UUID? = nil
    @State private var editingNote: BoardNote? = nil
    @State private var editDraftText: String = ""
    @FocusState private var composerFocused: Bool
    @FocusState private var editFocused: Bool

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var currentCoachId: UUID {
        AuthManager.shared.currentUser?.id ?? dataManager.coach.id
    }
    private var currentCoachName: String {
        AuthManager.shared.currentUser?.name ?? dataManager.coach.name
    }
    private var currentCoachImageUrl: String? {
        // Prefer the StaffCoach cloud URL, fall back to Coach, then AuthManager
        if let sc = dataManager.staffCoaches.first(where: { $0.id == currentCoachId }),
           let url = sc.profileImageUrl, !url.isEmpty {
            return url
        }
        if let url = dataManager.coach.profileImageUrl, !url.isEmpty {
            return url
        }
        return AuthManager.shared.currentUser?.profileImageUrl
    }

    private var currentCoachImageData: Data? {
        // StaffCoach by direct currentCoachId match
        if let sc = dataManager.staffCoaches.first(where: { $0.id == currentCoachId }),
           let data = sc.profileImageData, !data.isEmpty {
            return data
        }
        // StaffCoach by loggedInCoachId (may differ from AuthManager UUID)
        if let loggedInId = dataManager.loggedInCoachId,
           let sc = dataManager.staffCoaches.first(where: { $0.id == loggedInId }),
           let data = sc.profileImageData, !data.isEmpty {
            return data
        }
        // Fallback: main Coach profile
        if let data = dataManager.coach.profileImageData, !data.isEmpty {
            return data
        }
        // Fallback: AuthManager UserAccount
        return AuthManager.shared.currentUser?.profileImageData
    }

    private var notes: [BoardNote] {
        store.notes(for: session.id)
    }

    private var enrolledStudents: [Student] {
        guard let programId = session.programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
            return dataManager.students.filter { session.attendeeIds.contains($0.id) }
        }
        return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }

    private var activeCoaches: [StaffCoach] {
        dataManager.staffCoaches.filter { $0.isActive }
    }

    // Group notes by phase, preserving order
    private var groupedByPhase: [(phase: NotePhase, notes: [BoardNote])] {
        let allPhases: [NotePhase] = [.before, .during, .after]
        return allPhases.compactMap { phase in
            let group = notes.filter { $0.phase == phase }
            guard !group.isEmpty else { return nil }
            return (phase, group)
        }
    }

    // MARK: - Creation Info (synthetic, computed from session metadata)
    private var creationInfoRow: some View {
        let creatorName: String = {
            if let coachId = session.createdByCoachId,
               let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                return coach.name
            }
            return isChinese ? "教练" : "Coach"
        }()
        let programName: String? = {
            guard let pid = session.programId,
                  let program = dataManager.programs.first(where: { $0.id == pid }) else { return nil }
            return program.displayName
        }()
        let dateStr = session.createdAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())

        return HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 2)
                .clipShape(Capsule())

            (Text(creatorName)
                .foregroundColor(.blue)
                .fontWeight(.medium)
            + Text(isChinese ? " 创建了此课程" : " created this session")
                .foregroundColor(AppTheme.textTertiary)
            + (programName.map { name in
                Text(isChinese ? " · 项目 " : " · Program ")
                    .foregroundColor(AppTheme.textTertiary)
                + Text(name)
                    .foregroundColor(programColor)
                    .fontWeight(.medium)
            } ?? Text(""))
            )
            .font(.system(size: 12))

            Spacer()

            Text(dateStr)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // Always show creation info as the first entry
                        creationInfoRow

                        if notes.isEmpty {
                            emptyState
                        } else {
                            ForEach(groupedByPhase, id: \.phase) { group in
                                // Phase divider
                                phaseDivider(group.phase)

                                ForEach(group.notes) { note in
                                    Group {
                                        if case .activityEvent = note.noteType {
                                            activityRow(note)
                                        } else {
                                            noteRow(note)
                                        }
                                    }
                                    .id(note.id)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue, lineWidth: 1.5)
                                            .opacity(highlightedNoteId == note.id ? highlightOpacity : 0)
                                            .padding(.horizontal, 8)
                                    )
                                }
                            }
                        }
                        // Bottom padding so last message clears the composer
                        Color.clear.frame(height: 72)
                    }
                }
                .onAppear {
                    // Pull latest notes from Supabase so all devices stay in sync
                    store.loadFromCloud(sessionId: session.id)

                    if let id = highlightNoteId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            highlightedNoteId = id
                            highlightOpacity = 1.0
                            withAnimation(.easeOut(duration: 2)) {
                                highlightOpacity = 0
                            }
                        }
                    } else {
                        // Scroll to bottom on appear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let last = notes.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: notes.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if let last = notes.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            // Glass composer bar (fixed at bottom)
            composerBar
        }
        .background(AppTheme.background)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = notesBoardCompressJPEG(data) else { return }
                await MainActor.run {
                    let phase = computePhase()
                    let note = BoardNote(
                        sessionId: session.id,
                        authorId: currentCoachId,
                        authorName: currentCoachName,
                        authorImageUrl: currentCoachImageUrl,
                        authorImageData: currentCoachImageData,
                        body: isChinese ? "[照片]" : "[Photo]",
                        attachmentImageData: jpeg,
                        phase: phase
                    )
                    store.add(note)
                    selectedPhotoItem = nil
                    HapticFeedback.impact(.light)
                }
            }
        }
        .sheet(isPresented: $showReminderSheet) {
            QuickReminderSheet(
                session: session,
                programColor: programColor,
                onSave: { reminder in
                    dataManager.addReminder(reminder)
                    HapticFeedback.notification(.success)
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text(isChinese ? "还没有笔记" : "No notes yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Text(isChinese ? "在下方输入框发送第一条笔记" : "Post your first note below")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Phase Divider
    private func phaseDivider(_ phase: NotePhase) -> some View {
        HStack {
            VStack { Divider() }
            Text(isChinese ? phase.labelChinese : phase.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(phase.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(phase.color.opacity(0.1))
                .clipShape(Capsule())
            VStack { Divider() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Human Post Row
    private func noteRow(_ note: BoardNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            authorAvatar(note)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(timeString(note.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                }

                // Edit in-place overlay
                if editingNote?.id == note.id {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Edit note…", text: $editDraftText, axis: .vertical)
                            .font(.system(size: 14))
                            .lineLimit(1...6)
                            .focused($editFocused)
                            .padding(8)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack(spacing: 12) {
                            Button("Cancel") { editingNote = nil }
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textTertiary)
                            Spacer()
                            Button("Save") {
                                var updated = note
                                updated.body = editDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.update(updated)
                                editingNote = nil
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(programColor)
                            .disabled(editDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    styledBody(note.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if let data = note.attachmentImageData, let img = notesBoardImage(data) {
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contextMenu {
            if note.authorId == currentCoachId && accessMode.canAddNotes {
                Button {
                    editDraftText = note.body
                    editingNote = note
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { editFocused = true }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    store.delete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Activity Event Row
    private func activityRow(_ note: BoardNote) -> some View {
        guard case .activityEvent(let verb, let target) = note.noteType else {
            return AnyView(EmptyView())
        }
        return AnyView(
            HStack(alignment: .center, spacing: 8) {
                // 2pt left accent border
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 2)
                    .clipShape(Capsule())

                // @actorName verb #target timestamp
                (Text(note.authorName)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                + Text(" \(verb) ")
                    .foregroundColor(AppTheme.textTertiary)
                + Text(target.displayText)
                    .foregroundColor(target.isStudent ? .orange : AppTheme.textTertiary)
                    .fontWeight(target.isStudent ? .medium : .regular)
                )
                .font(.system(size: 12))

                Spacer()

                Text(timeString(note.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
        )
    }

    // MARK: - Author Avatar
    @ViewBuilder
    private func authorAvatar(_ note: BoardNote) -> some View {
        // 1. Snapshot data stored on the note (most reliable, offline-safe)
        // 2. Live StaffCoach record (updated when org photo changes)
        // 3. Main Coach profile data
        // 4. Remote URL via CachedImageView
        // 5. Initials fallback
        let liveData: Data? = {
            // Try direct StaffCoach match by note.authorId
            if let sc = dataManager.staffCoaches.first(where: { $0.id == note.authorId }),
               let d = sc.profileImageData, !d.isEmpty { return d }
            // note.authorId may be AuthManager.currentUser.id while StaffCoach uses loggedInCoachId —
            // if this note belongs to the currently logged-in coach, check both IDs
            let isCurrentCoach = note.authorId == currentCoachId
                || note.authorId == (dataManager.loggedInCoachId ?? currentCoachId)
            if isCurrentCoach {
                // Try StaffCoach by loggedInCoachId
                if let loggedInId = dataManager.loggedInCoachId,
                   let sc = dataManager.staffCoaches.first(where: { $0.id == loggedInId }),
                   let d = sc.profileImageData, !d.isEmpty { return d }
                // Fallback to main Coach profile
                if let d = dataManager.coach.profileImageData, !d.isEmpty { return d }
            }
            return nil
        }()
        let imageData = liveData ?? note.authorImageData

        if let data = imageData, !data.isEmpty, let img = notesBoardImage(data) {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else if let url = note.authorImageUrl, !url.isEmpty {
            CachedImageView(
                id: "coach_avatar_\(note.authorId.uuidString)",
                urlString: url,
                placeholder: initialsAvatar(note.authorName)
            )
            .scaledToFill()
            .clipShape(Circle())
        } else {
            initialsAvatar(note.authorName)
        }
    }

    private func initialsAvatar(_ name: String) -> some View {
        ZStack {
            Circle()
                .fill(programColor.opacity(0.18))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(programColor)
        }
    }

    // MARK: - Styled Body Text
    /// Renders body with @CoachName in blue and #StudentName in orange as inline Text
    private func styledBody(_ text: String) -> some View {
        let tokens = text.components(separatedBy: " ")
        var result = Text("")
        for (i, token) in tokens.enumerated() {
            let space = i < tokens.count - 1 ? " " : ""
            let clean = token.trimmingCharacters(in: .punctuationCharacters)
            if token.hasPrefix("@"), clean.count > 1 {
                result = result
                    + Text(token).font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
                    + Text(space).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary)
            } else if token.hasPrefix("#"), clean.count > 1 {
                result = result
                    + Text(token).font(.system(size: 14, weight: .semibold)).foregroundColor(.orange)
                    + Text(space).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary)
            } else {
                result = result
                    + Text(token + space).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary)
            }
        }
        return result
    }

    // MARK: - Composer Bar
    private var composerBar: some View {
        ZStack(alignment: .bottomLeading) {
            // Anchored plus popup — shown above the + button
            if showPlusMenu {
                plusPopup
                    .padding(.leading, 12)
                    .padding(.bottom, 64)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                    .zIndex(10)
            }
            // Anchored mention popup — shown above the @ button
            if showMentionPicker {
                mentionPopup
                    .padding(.leading, 52)
                    .padding(.bottom, 64)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                    .zIndex(10)
            }
            // Anchored student tag popup — shown above the # button
            if showStudentPicker {
                studentPopup
                    .padding(.leading, 92)
                    .padding(.bottom, 64)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                    .zIndex(10)
            }

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // + attachment popup trigger
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        showPlusMenu.toggle()
                    }
                    HapticFeedback.impact(.light)
                }) {
                    Image(systemName: showPlusMenu ? "xmark" : "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(showPlusMenu ? programColor : AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .animation(.easeInOut(duration: 0.15), value: showPlusMenu)
                }
                .buttonStyle(.plain)

                // @ coach mention
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        showMentionPicker.toggle()
                        if showMentionPicker { showStudentPicker = false; showPlusMenu = false }
                    }
                    HapticFeedback.impact(.light)
                }) {
                    Image(systemName: "at")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(pendingMentionCoachIds.isEmpty ? AppTheme.textSecondary : .blue)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // # student tag
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        showStudentPicker.toggle()
                        if showStudentPicker { showMentionPicker = false; showPlusMenu = false }
                    }
                    HapticFeedback.impact(.light)
                }) {
                    Image(systemName: "number")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(pendingTagStudentIds.isEmpty ? AppTheme.textSecondary : .orange)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Text input
                TextField(isChinese ? "记录笔记…" : "Jot something down", text: $composerText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .disabled(!accessMode.canAddNotes)

                // Send button
                Button(action: submitNote) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? AppTheme.textTertiary : programColor)
                }
                .buttonStyle(.plain)
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !accessMode.canAddNotes)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(AppTheme.cardBackground)
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(AppTheme.background)
        .overlay(Divider(), alignment: .top)
        .padding(.bottom, 0)
        } // ZStack
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                showPlusMenu = false
                showMentionPicker = false
                showStudentPicker = false
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - Mention Popup
    private var mentionPopup: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                TextField(isChinese ? "搜索教练" : "Search coaches", text: $mentionSearchText)
                    .font(.system(size: 13))
                if !mentionSearchText.isEmpty {
                    Button { mentionSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.background.opacity(0.6))

            Divider()

            let filtered = activeCoaches.filter {
                mentionSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(mentionSearchText)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(filtered) { coach in
                        Button(action: {
                            let token = "@\(coach.name)"
                            if !composerText.contains(token) {
                                composerText += (composerText.isEmpty ? "" : " ") + token
                            }
                            if !pendingMentionCoachIds.contains(coach.id) {
                                pendingMentionCoachIds.append(coach.id)
                            }
                            withAnimation(.easeOut(duration: 0.15)) { showMentionPicker = false }
                            mentionSearchText = ""
                        }) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.12)).frame(width: 26, height: 26)
                                    Text(String(coach.name.prefix(1)).uppercased())
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(.blue)
                                }
                                Text(coach.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if pendingMentionCoachIds.contains(coach.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if coach.id != filtered.last?.id { Divider().padding(.leading, 46) }
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .frame(width: 220)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - Student Tag Popup
    private var studentPopup: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                TextField(isChinese ? "搜索学员" : "Search athletes", text: $studentSearchText)
                    .font(.system(size: 13))
                if !studentSearchText.isEmpty {
                    Button { studentSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.background.opacity(0.6))

            Divider()

            let filtered = enrolledStudents.filter {
                studentSearchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(studentSearchText)
                || ($0.chineseName?.localizedCaseInsensitiveContains(studentSearchText) ?? false)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(filtered) { student in
                        Button(action: {
                            let token = "#\(student.displayName)"
                            if !composerText.contains(token) {
                                composerText += (composerText.isEmpty ? "" : " ") + token
                            }
                            if !pendingTagStudentIds.contains(student.id) {
                                pendingTagStudentIds.append(student.id)
                            }
                            withAnimation(.easeOut(duration: 0.15)) { showStudentPicker = false }
                            studentSearchText = ""
                        }) {
                            HStack(spacing: 8) {
                                StudentAvatarView(student: student, size: 26)
                                Text(student.displayName)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if pendingTagStudentIds.contains(student.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if student.id != filtered.last?.id { Divider().padding(.leading, 46) }
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .frame(width: 220)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - Plus Popup
    private var plusPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Add Photo
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) { showPlusMenu = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showPhotoPicker = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                    Text(isChinese ? "添加照片" : "Add Photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 14)

            // Add Reminder
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) { showPlusMenu = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showReminderSheet = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Circle())
                    Text(isChinese ? "添加提醒" : "Add Reminder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private var pendingChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pendingMentionCoachIds, id: \.self) { id in
                    if let coach = activeCoaches.first(where: { $0.id == id }) {
                        chipView("@\(coach.name)", color: .blue) {
                            pendingMentionCoachIds.removeAll { $0 == id }
                        }
                    }
                }
                ForEach(pendingTagStudentIds, id: \.self) { id in
                    if let student = enrolledStudents.first(where: { $0.id == id }) {
                        chipView("#\(student.displayName)", color: .orange) {
                            pendingTagStudentIds.removeAll { $0 == id }
                        }
                    }
                }
            }
        }
    }

    private func chipView(_ label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Submit
    private func submitNote() {
        let body = buildBody()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let phase = computePhase()
        let note = BoardNote(
            sessionId: session.id,
            authorId: currentCoachId,
            authorName: currentCoachName,
            authorImageUrl: currentCoachImageUrl,
            authorImageData: currentCoachImageData,
            body: body,
            mentionedCoachIds: pendingMentionCoachIds,
            taggedStudentIds: pendingTagStudentIds,
            phase: phase
        )
        store.add(note)

        // Notify mentioned coaches
        for coachId in pendingMentionCoachIds {
            if let coach = activeCoaches.first(where: { $0.id == coachId }) {
                CoachMentionStore.shared.addMention(
                    coachId: coach.id,
                    coachName: coach.name,
                    sessionName: session.title,
                    sessionId: session.id,
                    taggerName: currentCoachName
                )
            }
        }

        composerText = ""
        pendingMentionCoachIds = []
        pendingTagStudentIds = []
        HapticFeedback.impact(.light)
    }

    /// Injects pending @mention and #tag tokens into the body text
    private func buildBody() -> String {
        var parts: [String] = []

        for id in pendingMentionCoachIds {
            if let coach = activeCoaches.first(where: { $0.id == id }) {
                if !composerText.contains("@\(coach.name)") {
                    parts.append("@\(coach.name)")
                }
            }
        }
        for id in pendingTagStudentIds {
            if let student = enrolledStudents.first(where: { $0.id == id }) {
                if !composerText.contains("#\(student.displayName)") {
                    parts.append("#\(student.displayName)")
                }
            }
        }

        let prefix = parts.isEmpty ? "" : parts.joined(separator: " ") + " "
        return prefix + composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func computePhase() -> NotePhase {
        let now = Date()
        if now < session.startTime { return .before }
        if now <= session.endTime { return .during }
        return .after
    }

    // MARK: - Helpers
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Coach Mention Picker Sheet
struct CoachMentionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let coaches: [StaffCoach]
    @Binding var selectedIds: [UUID]
    @Binding var composerText: String
    @State private var searchText = ""

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var filtered: [StaffCoach] {
        guard !searchText.isEmpty else { return coaches }
        return coaches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { coach in
                Button(action: { toggle(coach) }) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 34, height: 34)
                            Text(String(coach.name.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        Text(coach.name)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        if selectedIds.contains(coach.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: isChinese ? "搜索教练" : "Search coaches")
            #else
            .searchable(text: $searchText, prompt: isChinese ? "搜索教练" : "Search coaches")
            #endif
            .navigationTitle(isChinese ? "@提及教练" : "Mention Coach")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        // Inject @CoachName tokens into composer
                        for id in selectedIds {
                            if let coach = coaches.first(where: { $0.id == id }) {
                                let token = "@\(coach.name)"
                                if !composerText.contains(token) {
                                    composerText += (composerText.isEmpty ? "" : " ") + token
                                }
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ coach: StaffCoach) {
        if let idx = selectedIds.firstIndex(of: coach.id) {
            selectedIds.remove(at: idx)
        } else {
            selectedIds.append(coach.id)
        }
    }
}

// MARK: - Student Tag Picker Sheet
struct StudentTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let students: [Student]
    @Binding var selectedIds: [UUID]
    @Binding var composerText: String
    @State private var searchText = ""

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var filtered: [Student] {
        guard !searchText.isEmpty else { return students }
        return students.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.chineseName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { student in
                Button(action: { toggle(student) }) {
                    HStack {
                        StudentAvatarView(student: student, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(student.displayName)
                                .font(.system(size: 15))
                                .foregroundColor(AppTheme.textPrimary)
                            if let cn = student.chineseName {
                                Text(cn)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        Spacer()
                        if selectedIds.contains(student.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: isChinese ? "搜索学员" : "Search athletes")
            #else
            .searchable(text: $searchText, prompt: isChinese ? "搜索学员" : "Search athletes")
            #endif
            .navigationTitle(isChinese ? "#标记学员" : "Tag Athlete")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        for id in selectedIds {
                            if let student = students.first(where: { $0.id == id }) {
                                let token = "#\(student.displayName)"
                                if !composerText.contains(token) {
                                    composerText += (composerText.isEmpty ? "" : " ") + token
                                }
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ student: Student) {
        if let idx = selectedIds.firstIndex(of: student.id) {
            selectedIds.remove(at: idx)
        } else {
            selectedIds.append(student.id)
        }
    }
}

// MARK: - Quick Reminder Sheet
struct QuickReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionEvent
    let programColor: Color
    let onSave: (Reminder) -> Void

    @State private var title = ""
    @State private var dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title input
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "提醒内容" : "Remind me to…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    TextField(isChinese ? "输入提醒…" : "Add a reminder…", text: $title)
                        .font(.system(size: 17))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                Divider().padding(.horizontal, 20)

                // Date picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "时间" : "WHEN")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    DatePicker("", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        #endif
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                        .padding(.horizontal, 8)
                }

                Spacer()
            }
            .background(AppTheme.cardBackground)
            .navigationTitle(isChinese ? "添加提醒" : "Add Reminder")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        let reminder = Reminder(
                            title: clean,
                            note: nil,
                            dueDate: dueDate,
                            priority: .medium,
                            sessionId: session.id,
                            programId: session.programId,
                            coachId: AuthManager.shared.currentUser?.id ?? UUID(),
                            creatorCoachId: AuthManager.shared.currentUser?.id ?? UUID()
                        )
                        onSave(reminder)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

