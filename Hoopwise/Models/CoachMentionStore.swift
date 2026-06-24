import Foundation
import Combine

// MARK: - Coach Mention / Activity Event Model

enum CoachMentionEventType: String, Codable, Equatable {
    case mention
    case sessionCreated
    case programAdded
}

struct CoachMention: Identifiable, Codable, Equatable {
    let id: UUID
    let eventType: CoachMentionEventType
    let coachId: UUID
    let coachName: String
    let sessionName: String
    let sessionId: UUID
    let taggerName: String
    let programId: UUID?
    let programName: String?
    let createdAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        eventType: CoachMentionEventType = .mention,
        coachId: UUID,
        coachName: String,
        sessionName: String,
        sessionId: UUID,
        taggerName: String,
        programId: UUID? = nil,
        programName: String? = nil,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.eventType = eventType
        self.coachId = coachId
        self.coachName = coachName
        self.sessionName = sessionName
        self.sessionId = sessionId
        self.taggerName = taggerName
        self.programId = programId
        self.programName = programName
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

// MARK: - Coach Mention Store
/// Lightweight in-memory + UserDefaults store for @coach mentions in session notes.
/// Persists across app launches. The dashboard reads unread mentions for the logged-in coach.
@MainActor
class CoachMentionStore: ObservableObject {
    static let shared = CoachMentionStore()

    @Published private(set) var mentions: [CoachMention] = []

    private let storageKey = "hoopwise_coach_mentions"

    private init() {
        load()
    }

    // MARK: - Public API

    func addMention(coachId: UUID, coachName: String, sessionName: String, sessionId: UUID, taggerName: String) {
        let mention = CoachMention(
            eventType: .mention,
            coachId: coachId,
            coachName: coachName,
            sessionName: sessionName,
            sessionId: sessionId,
            taggerName: taggerName
        )
        insert(mention)
    }

    func addSessionCreatedEvent(sessionId: UUID, sessionName: String, programId: UUID?, programName: String?, createdByCoachId: UUID, createdByCoachName: String) {
        let event = CoachMention(
            eventType: .sessionCreated,
            coachId: createdByCoachId,
            coachName: createdByCoachName,
            sessionName: sessionName,
            sessionId: sessionId,
            taggerName: createdByCoachName,
            programId: programId,
            programName: programName
        )
        insert(event)
    }

    func addProgramAddedEvent(programId: UUID, programName: String, createdByCoachId: UUID, createdByCoachName: String) {
        let event = CoachMention(
            eventType: .programAdded,
            coachId: createdByCoachId,
            coachName: createdByCoachName,
            sessionName: programName,
            sessionId: programId,
            taggerName: createdByCoachName,
            programId: programId,
            programName: programName
        )
        insert(event)
    }

    private func insert(_ event: CoachMention) {
        mentions.insert(event, at: 0)
        // Keep only last 100 events
        if mentions.count > 100 { mentions = Array(mentions.prefix(100)) }
        save()
    }

    /// Unread @mention events for a specific coach
    func unreadMentions(for coachId: UUID) -> [CoachMention] {
        mentions.filter { $0.coachId == coachId && !$0.isRead && $0.eventType == .mention }
    }

    /// All unread activity feed events (mentions + session/program events) for a specific coach
    func unreadFeedEvents(for coachId: UUID) -> [CoachMention] {
        mentions.filter { $0.coachId == coachId && !$0.isRead }
    }

    /// All activity feed events for a specific coach
    func allFeedEvents(for coachId: UUID) -> [CoachMention] {
        mentions.filter { $0.coachId == coachId }
    }

    /// All mentions for a specific coach
    func allMentions(for coachId: UUID) -> [CoachMention] {
        mentions.filter { $0.coachId == coachId && $0.eventType == .mention }
    }

    func markAsRead(_ mentionId: UUID) {
        if let idx = mentions.firstIndex(where: { $0.id == mentionId }) {
            mentions[idx].isRead = true
            save()
        }
    }

    func markAllRead(for coachId: UUID) {
        for idx in mentions.indices where mentions[idx].coachId == coachId {
            mentions[idx].isRead = true
        }
        save()
    }

    func deleteMention(_ mentionId: UUID) {
        mentions.removeAll { $0.id == mentionId }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(mentions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CoachMention].self, from: data) else { return }
        mentions = decoded
    }
}
