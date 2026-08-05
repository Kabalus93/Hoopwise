import AppKit
import Combine
import SwiftUI

// MARK: - Floating whistle bubble
//
// A small always-on-top, non-activating NSPanel with the whistle mascot.
// Draggable (position remembered), toggleable from Settings and ⌥Space
// (through the key-dispatch layer). Click opens a compact popover chat on the
// same conversation store as the page; Esc dismisses (transient popover).
// A badge dot appears when curation has a proactive note — it never opens
// itself, never plays sound, and respects Reduce Motion.

@MainActor
final class WhistleBubbleController {
    static let shared = WhistleBubbleController()

    private var panel: NSPanel?
    private var popover: NSPopover?
    private weak var engine: AssistantEngine?

    private static let originKey = "assistant.bubble.origin"

    func attach(engine: AssistantEngine) {
        self.engine = engine
        if UserDefaults.standard.object(forKey: "assistant.bubble") == nil
            || UserDefaults.standard.bool(forKey: "assistant.bubble") {
            show()
        }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "assistant.bubble")
        enabled ? show() : hide()
    }

    func show() {
        guard let engine else { return }
        if panel == nil {
            let size = NSSize(width: 64, height: 64)
            let origin = savedOrigin ?? defaultOrigin(for: size)
            let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                                styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView:
                WhistleBubbleContent(engine: engine) { [weak self] in self?.togglePopover() })
            self.panel = panel
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
                NotificationCenter.default.post(name: .whistleBubbleMoved, object: nil)
                Task { @MainActor in self.saveOrigin() }
            }
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        popover?.close()
        panel?.orderOut(nil)
    }

    private func togglePopover() {
        guard let panel, let engine, let contentView = panel.contentView else { return }
        if let popover, popover.isShown {
            popover.close()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient       // Esc and click-outside dismiss
        popover.contentSize = NSSize(width: 380, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: WhistlePopoverChat()
                .environmentObject(engine)
                .frame(width: 380, height: 460))
        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        engine.curationFresh = false        // note acknowledged
        self.popover = popover
    }

    private var savedOrigin: NSPoint? {
        guard let string = UserDefaults.standard.string(forKey: Self.originKey) else { return nil }
        let parts = string.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    private func saveOrigin() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        return NSPoint(x: screen.visibleFrame.maxX - size.width - 24,
                       y: screen.visibleFrame.minY + 96)
    }
}

// MARK: - Bubble content (mascot + restrained animation)

extension Notification.Name {
    static let whistleBubbleMoved = Notification.Name("whistleBubbleMoved")
}

private struct WhistleBubbleContent: View {
    @ObservedObject var engine: AssistantEngine
    let onTap: () -> Void

    @State private var completionAt: Date?     // one wiggle + air puffs
    @State private var bobAt: Date?            // idle micro-bob
    @State private var dragAt: Date?           // lanyard physics on drag
    @State private var wasStreaming = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func window(_ anchor: Date?, _ duration: TimeInterval, at now: Date) -> TimeInterval? {
        guard let anchor else { return nil }
        let dt = now.timeIntervalSince(anchor)
        return (0..<duration).contains(dt) ? dt : nil
    }

    private var animating: Bool {
        if reduceMotion { return false }
        let now = Date()
        return engine.isStreaming
            || window(completionAt, 0.34, at: now) != nil
            || window(bobAt, 0.9, at: now) != nil
            || window(dragAt, 1.1, at: now) != nil
    }

    /// The character comes from motion: every layer's pose derived from
    /// the clock, stateless, so pausing simply freezes at rest.
    private func motion(at now: Date) -> WhistleMotionState {
        guard !reduceMotion else { return .rest }
        var m = WhistleMotionState()
        let t = now.timeIntervalSinceReferenceDate
        if engine.isStreaming {
            // Thinking: the pea rattles gently inside the window.
            m.peaOffset = CGSize(width: sin(t * 16) * 2.4,
                                 height: -abs(sin(t * 8)) * 1.5)
            m.wiggleDegrees = sin(t * 2.6) * 1.8
        }
        if let dt = window(completionAt, 0.34, at: now) {
            // Completion: one wiggle + air puffs, 300ms, gone.
            let progress = dt / 0.34
            m.wiggleDegrees += sin(progress * .pi * 2) * 9 * (1 - progress)
            m.puffProgress = progress
        }
        if let dt = window(bobAt, 0.9, at: now) {
            // Idle micro-bob; the lanyard settles with slight lag.
            let progress = dt / 0.9
            m.bobOffset = -sin(progress * .pi) * 3
            let lagged = max(0, progress - 0.14)
            m.lanyardSway = sin(lagged * .pi * 2) * 0.5 * (1 - progress)
        }
        if let dt = window(dragAt, 1.1, at: now) {
            // Dragging: damped pendulum sway.
            m.lanyardSway += CGFloat(sin(dt * 11) * exp(-dt * 3.0))
        }
        return m
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: !animating)) { timeline in
                WhistleIconView(proportions: .sporty,
                                motion: motion(at: timeline.date),
                                darkScheme: true)
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
            }
            if engine.curationFresh {
                Circle().fill(Color.red)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: -4, y: 4)
            }
        }
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        // Idle micro-bob every ~20s.
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion, !engine.isStreaming else { return }
            bobAt = Date()
        }
        .onChange(of: engine.isStreaming) { _, streaming in
            if streaming { wasStreaming = true }
            else if wasStreaming {
                wasStreaming = false
                if !reduceMotion { completionAt = Date() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whistleBubbleMoved)) { _ in
            if !reduceMotion { dragAt = Date() }
        }
    }
}

// MARK: - Compact popover chat

private struct WhistlePopoverChat: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                WhistleGlyph(size: 20)
                Text("The Whistle").font(.headline)
                Spacer()
                Button("Assistant page") {
                    NotificationCenter.default.post(name: .macSidebarSelection,
                                                    object: SidebarSection.assistant.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .controlSize(.small)
            }
            .padding(10)
            Divider()

            if !engine.curationCards.isEmpty && (engine.activeConversation?.messages.isEmpty ?? true) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Worth a look")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(engine.curationCards) { card in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.title).font(.callout.weight(.medium))
                                Text(card.reason).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quinary, in: .rect(cornerRadius: 8))
                        }
                    }
                    .padding(10)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(engine.activeConversation?.messages ?? []) { message in
                                if !message.plainText.isEmpty {
                                    Text(message.plainText)
                                        .font(.callout)
                                        .padding(8)
                                        .frame(maxWidth: .infinity,
                                               alignment: message.role == "user" ? .trailing : .leading)
                                        .background(message.role == "user"
                                                    ? Color.accentColor.opacity(0.12)
                                                    : Color(nsColor: .quaternarySystemFill),
                                                    in: .rect(cornerRadius: 9))
                                }
                            }
                            if engine.isStreaming && !engine.streamingText.isEmpty {
                                Text(engine.streamingText).font(.callout)
                                    .padding(8).opacity(0.85)
                            }
                            if !engine.pendingWrites.isEmpty {
                                Text("A change is waiting for confirmation on the Assistant page.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Color.clear.frame(height: 1).id("popover-bottom")
                        }
                        .padding(10)
                    }
                    .onChange(of: engine.streamingText) { _, _ in
                        proxy.scrollTo("popover-bottom", anchor: .bottom)
                    }
                }
            }

            Divider()
            HStack(spacing: 6) {
                TextField(engine.hasAPIKey ? "Ask…" : "Needs API key (Settings)", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !draft.isEmpty else { return }
                        if engine.activeConversation == nil { engine.newConversation() }
                        engine.send(draft)
                        draft = ""
                    }
                    .disabled(!engine.hasAPIKey || engine.isStreaming)
            }
            .padding(10)
        }
    }
}
