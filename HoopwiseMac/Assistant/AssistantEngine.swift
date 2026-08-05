import Combine
import Foundation
import os
import SwiftUI

// MARK: - Conversation model

struct AssistantConversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String = "New Conversation"
    var createdAt = Date()
    var messages: [AssistantMessage] = []
    /// "live" | "scripted" — a conversation is bound to the transport it
    /// began under; scripted transcripts are never sent to the live API.
    var transport: String? = "live"
}

/// A write the model wants to make, awaiting the user's click.
struct PendingWrite: Identifiable, Equatable {
    let id: String              // tool_use id
    let toolName: String
    let inputJSON: String
    let previewLines: [String]
    let category: AssistantToolCategory
}

struct CurationCard: Identifiable, Codable, Equatable {
    var id: String
    var kind: String            // bundleLow | attendance | session | setup
    var title: String
    var reason: String
    var athleteId: UUID?
    var curated: Bool           // false = deterministic fallback ordering
}

// MARK: - Engine

@MainActor
final class AssistantEngine: ObservableObject {
    static let chatModel = "claude-sonnet-5"
    static let curationModel = "claude-haiku-4-5"

    @Published var conversations: [AssistantConversation] = []
    @Published var activeConversationId: UUID?
    @Published var streamingText = ""
    @Published var isStreaming = false
    @Published var pendingWrites: [PendingWrite] = []
    @Published var expiredWriteIds: Set<String> = []
    @Published var lastError: String?
    @Published var curationCards: [CurationCard] = []
    @Published var curationFresh = false      // drives the bubble badge dot

    private var dataManager: DataManager?
    private var registry: AssistantToolRegistry?
    private var transport: AssistantTransport = AnthropicClient()
    /// Tool results already gathered this turn, waiting for pending writes.
    private var gatheredResults: [AssistantBlock] = []

    var hasAPIKey: Bool { AssistantSecrets.apiKey != nil }

    private var transportKind: String { transport is AnthropicClient ? "live" : "scripted" }

    var activeConversation: AssistantConversation? {
        get { conversations.first { $0.id == activeConversationId } }
        set {
            guard let newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id })
            else { return }
            conversations[index] = newValue
        }
    }

    func configure(dataManager: DataManager) {
        guard self.dataManager == nil else { return }
        self.dataManager = dataManager
        registry = AssistantToolRegistry(dataManager: dataManager)
        loadConversations()
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOOPWISE_DEMO_ASSISTANT"] == "script" {
            transport = ScriptedTransport()
        }
        #endif
    }

    // MARK: Conversations

    func newConversation() {
        var conversation = AssistantConversation()
        conversation.transport = transportKind
        conversations.insert(conversation, at: 0)
        activeConversationId = conversation.id
        pendingWrites = []
        gatheredResults = []
        persist()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id { activeConversationId = conversations.first?.id }
        persist()
    }

    // MARK: Chat loop

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        // A new message while a confirmation card is pending voids the
        // write: the turn is closed with "superseded" tool_results BEFORE
        // the message is appended, so no tool_use ever dangles.
        if !pendingWrites.isEmpty { voidPendingWrites() }
        // Scripted transcripts never reach the live API — open fresh.
        if let active = activeConversation,
           (active.transport ?? "live") != transportKind {
            newConversation()
        }
        if activeConversation == nil { newConversation() }
        guard var conversation = activeConversation else { return }
        conversation.messages.append(AssistantMessage(role: "user", blocks: [.text(trimmed)]))
        if conversation.title == "New Conversation" {
            conversation.title = String(trimmed.prefix(48))
        }
        activeConversation = conversation
        persist()
        Task { await runLoop() }
    }

    /// The agent loop: stream a turn; execute reads immediately; pause on
    /// writes for confirmation; loop until the model stops calling tools.
    private func runLoop() async {
        repairActiveConversation()
        guard let registry else { return }
        guard var conversation = activeConversation else { return }
        lastError = nil
        isStreaming = true
        defer { isStreaming = false }

        while true {
            streamingText = ""
            let result: (blocks: [AssistantBlock], stopReason: String)
            do {
                result = try await transport.streamTurn(
                    system: systemBlocks(),
                    messages: conversation.messages,
                    tools: registry.wireTools,
                    model: Self.chatModel,
                    onTextDelta: { [weak self] delta in self?.streamingText += delta })
            } catch {
                lastError = error.localizedDescription
                streamingText = ""
                return
            }
            streamingText = ""
            conversation.messages.append(AssistantMessage(role: "assistant", blocks: result.blocks))
            activeConversation = conversation
            persist()

            guard result.stopReason == "tool_use" else { return }

            var results: [AssistantBlock] = []
            var writes: [PendingWrite] = []
            for block in result.blocks {
                guard let toolUse = block.toolUseInfo,
                      let tool = registry.tool(named: toolUse.name) else { continue }
                let alwaysAllowed = tool.category.supportsAlwaysAllow
                    && UserDefaults.standard.bool(forKey: tool.category.allowKey)
                if tool.category.isWrite && !alwaysAllowed {
                    let args = (try? AssistantToolRegistry.decode(toolUse.inputJSON)) ?? [:]
                    writes.append(PendingWrite(
                        id: toolUse.id, toolName: toolUse.name, inputJSON: toolUse.inputJSON,
                        previewLines: tool.preview?(args) ?? [toolUse.name],
                        category: tool.category))
                } else {
                    let outcome = registry.execute(name: toolUse.name, argumentsJSON: toolUse.inputJSON)
                    results.append(.toolResult(id: toolUse.id, content: outcome.payload,
                                               isError: outcome.isError))
                }
            }

            if !writes.isEmpty {
                // Pause: card in the chat; resolvePending() resumes the loop.
                gatheredResults = results
                pendingWrites = writes
                return
            }
            conversation.messages.append(AssistantMessage(role: "user", blocks: results))
            activeConversation = conversation
            persist()
        }
    }

    /// Close a pending confirmation without executing: every dangling
    /// tool_use gets a superseded tool_result so the transcript stays valid.
    private func voidPendingWrites() {
        guard var conversation = activeConversation, !pendingWrites.isEmpty else { return }
        var results = gatheredResults
        for write in pendingWrites {
            results.append(.toolResult(
                id: write.id,
                content: "Not confirmed — superseded by the user's next message. Nothing was written.",
                isError: true))
        }
        expiredWriteIds.formUnion(pendingWrites.map(\.id))
        pendingWrites = []
        gatheredResults = []
        conversation.messages.append(AssistantMessage(role: "user", blocks: results))
        activeConversation = conversation
        persist()
        #if DEBUG
        auditStore(context: "voided")
        #endif
    }

    /// Transcript invariant: every tool_use is closed by a tool_result
    /// before any later message. Dangling calls (crash, kill, old bug) get
    /// a synthetic "interrupted" result. Run at load and before every
    /// request — defense in depth.
    static func repaired(_ conversation: AssistantConversation) -> AssistantConversation {
        var repaired = conversation
        let resultIds = Set(conversation.messages.flatMap(\.blocks).compactMap { block -> String? in
            if case .toolResult(let id, _, _) = block { return id }
            return nil
        })
        var index = 0
        while index < repaired.messages.count {
            let message = repaired.messages[index]
            if message.role == "assistant" {
                let dangling = message.blocks.compactMap(\.toolUseInfo).filter { !resultIds.contains($0.id) }
                if !dangling.isEmpty {
                    let synthetic = dangling.map { AssistantBlock.toolResult(
                        id: $0.id,
                        content: "Interrupted — the app closed before this ran. Nothing was written.",
                        isError: true) }
                    repaired.messages.insert(
                        AssistantMessage(role: "user", blocks: synthetic), at: index + 1)
                    index += 1
                }
            }
            index += 1
        }
        // Trailing hygiene: the transcript must start with a user message.
        while let first = repaired.messages.first, first.role != "user" {
            repaired.messages.removeFirst()
        }
        return repaired
    }

    private func repairActiveConversation() {
        guard let conversation = activeConversation else { return }
        let repaired = Self.repaired(conversation)
        if repaired != conversation {
            activeConversation = repaired
            persist()
        }
    }

    /// A 400 must not dead-end the chat: repair the transcript and re-send.
    func repairAndRetry() {
        lastError = nil
        pendingWrites = []
        gatheredResults = []
        repairActiveConversation()
        Task { await runLoop() }
    }

    /// One click confirms (or declines) every previewed write, executes as a
    /// batch, then resumes the loop.
    func resolvePending(confirmed: Bool, alwaysAllow: Bool = false) {
        guard let registry, var conversation = activeConversation, !pendingWrites.isEmpty else { return }
        var results = gatheredResults
        for write in pendingWrites {
            if confirmed {
                if alwaysAllow, write.category.supportsAlwaysAllow {
                    UserDefaults.standard.set(true, forKey: write.category.allowKey)
                }
                let outcome = registry.execute(name: write.toolName, argumentsJSON: write.inputJSON)
                results.append(.toolResult(id: write.id, content: outcome.payload,
                                           isError: outcome.isError))
            } else {
                results.append(.toolResult(id: write.id,
                                           content: "The user declined this change.", isError: true))
            }
        }
        pendingWrites = []
        gatheredResults = []
        conversation.messages.append(AssistantMessage(role: "user", blocks: results))
        activeConversation = conversation
        persist()
        Task { await runLoop() }
    }

    /// Summary text for a tool_use block's chip, joined with its result.
    func chipInfo(for toolUseId: String, in conversation: AssistantConversation)
        -> (summary: String, isError: Bool)?
    {
        for message in conversation.messages {
            for block in message.blocks {
                if case .toolResult(let id, let content, let isError) = block, id == toolUseId {
                    // Prefer a compact summary over raw payload.
                    let summary = isError ? content : (content.count > 80 ? "done" : content)
                    return (summary, isError)
                }
            }
        }
        return nil
    }

    // MARK: System prompt

    /// Stable identity + rules first (cached), volatile snapshot after the
    /// cache breakpoint — context by retrieval, not by dump.
    private func systemBlocks() -> [[String: Any]] {
        let stable = """
        You are The Whistle, the in-app assistant of Hoopwise — a basketball coaching \
        management app used by one coach running youth programs in China. You have READ \
        and WRITE tools over the app's real data: athletes, sessions, programs, contracts.

        Rules:
        - The roster is bilingual. Athletes have English and 中文 names; queries may come \
        in either or in pinyin. The search tools handle all three — never ask the user to \
        romanize a name.
        - Retrieve, don't guess: answer questions about data by calling read tools. If a \
        name is ambiguous, search first and ask which match the user means.
        - Writes are previewed to the user by the app before they run; you don't need to \
        ask permission yourself, but state clearly what you are about to change. If a tool \
        refuses (a business rule), relay the actual rule to the user.
        - Data minimization may be on: guardian contacts and money amounts are then \
        redacted from your view. Refer the user to the record in the app instead of \
        guessing — use open_in_app so they land on it.
        - After acting, summarize what changed, mention that ⌘Z undoes it, and use \
        open_in_app when seeing the record helps.
        - Keep responses short and concrete. Real names, real numbers, no filler.
        """
        var blocks: [[String: Any]] = [
            ["type": "text", "text": stable, "cache_control": ["type": "ephemeral"]],
        ]
        if let snapshot = snapshotText() {
            blocks.append(["type": "text", "text": snapshot])
        }
        return blocks
    }

    /// Small standing snapshot: counts, today's sessions, alerts.
    private func snapshotText() -> String? {
        guard let dataManager else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        var lines = ["Snapshot (\(formatter.string(from: Date()))):"]
        lines.append("- \(dataManager.students.count) athletes, \(dataManager.programs.count) programs, \(dataManager.sessionEvents.count) sessions on record")
        let calendar = Calendar.current
        let today = dataManager.sessionEvents
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.startTime < $1.startTime }
        if today.isEmpty {
            lines.append("- No sessions today")
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            for session in today.prefix(6) {
                lines.append("- Today \(timeFormatter.string(from: session.startTime)): \(session.title) [\(session.status.rawValue)] id=\(session.id.uuidString)")
            }
        }
        let bundleLow = dataManager.cachedContracts.filter {
            $0.kind == .privateBundle && $0.status == .active
                && ($0.bundleRedemptionsRemaining ?? 99) <= 3
        }
        for contract in bundleLow.prefix(5) {
            if let student = dataManager.students.first(where: { $0.id == contract.studentId }) {
                lines.append("- Bundle low: \(student.displayName) has \(contract.bundleRedemptionsRemaining ?? 0) sessions left")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Homescreen curation (cheap model, deterministic fallback)

    func runCuration(force: Bool = false) async {
        guard let dataManager,
              UserDefaults.standard.object(forKey: "assistant.curation") == nil
                || UserDefaults.standard.bool(forKey: "assistant.curation") else { return }
        let facts = curationFacts(dataManager: dataManager)
        guard !facts.isEmpty else { curationCards = []; return }

        // Deterministic fallback first — curation is an enhancement, never
        // a dependency. Offline/keyless still renders.
        let muted = Set((UserDefaults.standard.string(forKey: "assistant.mutedCardKinds") ?? "")
            .split(separator: ",").map(String.init))
        var cards = facts.filter { !muted.contains($0.kind) }

        if hasAPIKey, transport is AnthropicClient {
            let catalog = cards.map { "\($0.id) | \($0.kind) | \($0.title) | \($0.reason)" }
                .joined(separator: "\n")
            let prompt = """
            Rank the most important coaching attention items (max 6) and write one short, \
            human reason each (in the coach's working language, English). Items:
            \(catalog)
            Reply ONLY with JSON: [{"id": "...", "reason": "..."}]
            """
            if let text = try? await AnthropicClient.completeOnce(
                system: "You curate a basketball coach's home screen. Terse, concrete, no filler.",
                user: prompt, model: Self.curationModel, maxTokens: 600),
               let ranked = Self.parseCurationJSON(text) {
                var curated: [CurationCard] = []
                for entry in ranked {
                    if var card = cards.first(where: { $0.id == entry.id }) {
                        card.reason = entry.reason
                        card.curated = true
                        curated.append(card)
                    }
                }
                if !curated.isEmpty { cards = curated }
            }
        }
        curationCards = Array(cards.prefix(6))
        if force || !curationCards.isEmpty { curationFresh = true }
    }

    static func parseCurationJSON(_ text: String) -> [(id: String, reason: String)]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") else { return nil }
        let json = String(text[start...end])
        guard let array = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        else { return nil }
        return array.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            return (id, entry["reason"] as? String ?? "")
        }
    }

    /// The same alert-shaped queries the app already surfaces, as ranked-card
    /// candidates with templated fallback reasons.
    private func curationFacts(dataManager: DataManager) -> [CurationCard] {
        var facts: [CurationCard] = []
        let calendar = Calendar.current

        for contract in dataManager.cachedContracts where contract.kind == .privateBundle
            && contract.status == .active && (contract.bundleRedemptionsRemaining ?? 99) <= 3 {
            guard let student = dataManager.students.first(where: { $0.id == contract.studentId })
            else { continue }
            let left = contract.bundleRedemptionsRemaining ?? 0
            facts.append(CurationCard(
                id: "bundle-\(contract.id.uuidString.prefix(8))", kind: "bundleLow",
                title: "\(student.displayName) — \(left) session\(left == 1 ? "" : "s") left",
                reason: "Bundle nearly used up — time to talk renewal.",
                athleteId: student.id, curated: false))
        }

        let sessionsToday = dataManager.sessionEvents.filter { calendar.isDateInToday($0.date) }
        for session in sessionsToday where session.status == .scheduled {
            facts.append(CurationCard(
                id: "session-\(session.id.uuidString.prefix(8))", kind: "session",
                title: session.title,
                reason: "On today's schedule.",
                athleteId: nil, curated: false))
        }

        // Attendance risk: three most-missed active athletes under 50%.
        var risk: [(Student, Int)] = []
        for student in dataManager.students {
            let relevant = dataManager.sessionEvents.filter {
                $0.date <= Date() && ($0.attendeeIds.contains(student.id)
                    || $0.actualAttendeeIds.contains(student.id))
            }
            guard relevant.count >= 4 else { continue }
            let attended = relevant.filter { $0.actualAttendeeIds.contains(student.id) }.count
            let percent = Int(Double(attended) / Double(relevant.count) * 100)
            if percent < 50 { risk.append((student, percent)) }
        }
        for (student, percent) in risk.sorted(by: { $0.1 < $1.1 }).prefix(3) {
            facts.append(CurationCard(
                id: "attend-\(student.id.uuidString.prefix(8))", kind: "attendance",
                title: "\(student.displayName) — \(percent)% attendance",
                reason: "Attendance is slipping — worth a message to the guardian.",
                athleteId: student.id, curated: false))
        }
        return facts
    }

    // MARK: Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HoopwiseAssistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversations.json")
    }

    private func loadConversations() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let stored = try? JSONDecoder().decode([AssistantConversation].self, from: data)
        else { return }
        conversations = stored.map { conversation in
            var repaired = Self.repaired(conversation)
            // Anything carrying scripted-demo tool ids is scripted, whatever
            // its tag claims — it must never reach the live API.
            let hasDemoIds = repaired.messages.flatMap(\.blocks).contains { block in
                if case .toolUse(let id, _, _) = block { return id.hasPrefix("demo_tool_") }
                if case .toolResult(let id, _, _) = block { return id.hasPrefix("demo_tool_") }
                return false
            }
            if hasDemoIds { repaired.transport = "scripted" }
            if repaired.transport == nil { repaired.transport = "live" }
            return repaired
        }
        activeConversationId = conversations.first?.id
        persist()
        #if DEBUG
        auditStore(context: "load")
        #endif
    }

    #if DEBUG
    /// Store invariant audit over the unified log (the container is
    /// sandbox-protected, so outside shells can't read the JSON directly).
    func auditStore(context: String) {
        let logger = Logger(subsystem: "hoopwise.demo", category: "assistant")
        for conversation in conversations {
            var uses: Set<String> = [], results: Set<String> = []
            for message in conversation.messages {
                for block in message.blocks {
                    if case .toolUse(let id, _, _) = block { uses.insert(id) }
                    if case .toolResult(let id, _, _) = block { results.insert(id) }
                }
            }
            let dangling = uses.subtracting(results).sorted().joined(separator: ",")
            let demoLive = (conversation.transport ?? "live") == "live"
                && uses.contains { $0.hasPrefix("demo_tool_") }
            logger.notice("AUDIT[\(context, privacy: .public)] transport=\(conversation.transport ?? "nil", privacy: .public) uses=\(uses.count) dangling=[\(dangling, privacy: .public)] demoInLive=\(demoLive)")
        }
    }
    #endif

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}
