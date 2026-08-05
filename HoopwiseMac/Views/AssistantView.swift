import SwiftUI

// MARK: - The Whistle — Assistant page

struct AssistantView: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var draft = ""
    @State private var search = ""
    @State private var expandedChips: Set<String> = []

    var body: some View {
        HSplitView {
            conversationList
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
            chatPane
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Assistant")
    }

    // MARK: Conversation list

    private var conversationList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations").font(.headline)
                Spacer()
                Button {
                    engine.newConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
            .padding(12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            List(selection: $engine.activeConversationId) {
                ForEach(filteredConversations) { conversation in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conversation.title)
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(conversation.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            engine.deleteConversation(conversation.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var filteredConversations: [AssistantConversation] {
        guard !search.isEmpty else { return engine.conversations }
        return engine.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.messages.contains { $0.plainText.localizedCaseInsensitiveContains(search) }
        }
    }

    // MARK: Chat pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            if let conversation = engine.activeConversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(conversation.messages) { message in
                                messageView(message, in: conversation)
                            }
                            if engine.isStreaming && !engine.streamingText.isEmpty {
                                assistantBubble(engine.streamingText, streaming: true)
                            }
                            if engine.isStreaming && engine.streamingText.isEmpty
                                && engine.pendingWrites.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.leading, 4)
                            }
                            if !engine.pendingWrites.isEmpty {
                                confirmationCard
                            }
                            if let error = engine.lastError {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(error, systemImage: "exclamationmark.triangle.fill")
                                        .font(.callout).foregroundStyle(.orange)
                                    Button("Repair & Retry") { engine.repairAndRetry() }
                                        .controlSize(.small)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(16)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: engine.streamingText) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: conversation.messages.count) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            } else {
                emptyState
            }
            Divider()
            inputBar
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhistleGlyph(size: 44)
            Text("The Whistle").font(.title2.weight(.semibold))
            Text("Ask about athletes, sessions, attendance, or contracts — 中文 or English.\nIt reads and edits the same records your phone sees.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !engine.hasAPIKey {
                Label("Add an Anthropic API key in Settings → Assistant to start.",
                      systemImage: "key")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Message rendering

    @ViewBuilder
    private func messageView(_ message: AssistantMessage,
                             in conversation: AssistantConversation) -> some View {
        ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .text(let text):
                if message.role == "user" {
                    HStack {
                        Spacer(minLength: 60)
                        Text(text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    assistantBubble(text, streaming: false)
                }
            case .toolUse(let id, let name, let inputJSON):
                toolChip(id: id, name: name, inputJSON: inputJSON, in: conversation)
            case .toolResult:
                EmptyView()   // surfaced inside the matching chip
            }
        }
    }

    private func assistantBubble(_ text: String, streaming: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            WhistleGlyph(size: 20)
                .padding(.top, 6)
            Text(text.isEmpty ? " " : text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(streaming ? 0.85 : 1)
            Spacer(minLength: 40)
        }
    }

    /// Tool-call transparency: every action renders as a quiet chip,
    /// expandable to the payload — you should never wonder what it did.
    private func toolChip(id: String, name: String, inputJSON: String,
                          in conversation: AssistantConversation) -> some View {
        let info = engine.chipInfo(for: id, in: conversation)
        let expanded = expandedChips.contains(id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if expanded { expandedChips.remove(id) } else { expandedChips.insert(id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: info?.isError == true
                          ? "exclamationmark.circle" : "wrench.and.screwdriver")
                        .font(.caption2)
                    Text(chipLabel(name: name, info: info))
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(info?.isError == true ? Color.orange : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("input  \(inputJSON)")
                    if let info { Text("result \(info.summary)") }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: .rect(cornerRadius: 8))
                .padding(.leading, 28)
            }
        }
    }

    private func chipLabel(name: String, info: (summary: String, isError: Bool)?) -> String {
        guard let info else { return "\(name) · running" }
        if info.summary.hasPrefix("Not confirmed") { return "\(name) · expired — not written" }
        if info.summary.hasPrefix("Interrupted") { return "\(name) · interrupted — not written" }
        if info.isError { return "\(name) — \(info.summary)" }
        return info.summary == "done" ? "\(name) ✓" : "\(name) · \(info.summary)"
    }

    // MARK: Confirmation card

    /// Compact preview of every write in this batch — one click confirms,
    /// executes as one undo group.
    private var confirmationCard: some View {
        let categories = Set(engine.pendingWrites.map(\.category))
        let allowEligible = categories.count == 1 && categories.first!.supportsAlwaysAllow
        return VStack(alignment: .leading, spacing: 10) {
            Label(engine.pendingWrites.count == 1
                  ? "The Whistle wants to make a change"
                  : "The Whistle wants to make \(engine.pendingWrites.count) changes",
                  systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            ForEach(engine.pendingWrites) { write in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(write.previewLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(index == 0 ? .callout.weight(.medium) : .caption)
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6),
                            in: .rect(cornerRadius: 8))
            }
            HStack {
                if allowEligible, let category = categories.first {
                    Button("Always allow \(category.rawValue) changes") {
                        engine.resolvePending(confirmed: true, alwaysAllow: true)
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button("Cancel") { engine.resolvePending(confirmed: false) }
                Button("Confirm") { engine.resolvePending(confirmed: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.accentColor.opacity(0.3)))
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(engine.hasAPIKey
                      ? "Ask the whistle — 蔡一铭's attendance, Saturday's roster, anything…"
                      : "Chat needs an API key — Settings → Assistant",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { submit() }
                .disabled(!inputEnabled)
            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputEnabled && !draft.isEmpty
                                     ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!inputEnabled || draft.isEmpty)
        }
        .padding(12)
    }

    private var inputEnabled: Bool {
        (engine.hasAPIKey || engineIsScripted) && !engine.isStreaming
    }

    private var engineIsScripted: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["HOOPWISE_DEMO_ASSISTANT"] == "script"
        #else
        return false
        #endif
    }

    private func submit() {
        guard inputEnabled, !draft.isEmpty else { return }
        engine.send(draft)
        draft = ""
    }
}

// MARK: - Whistle mascot glyph (static — the bubble carries the motion)

struct WhistleGlyph: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WhistleIconView(proportions: .sporty, motion: .rest,
                        darkScheme: colorScheme == .dark)
            .frame(width: size, height: size)
    }
}
