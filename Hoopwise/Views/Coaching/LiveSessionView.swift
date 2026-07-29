import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit
#endif

// MARK: - Live Session View
/// A real-time session execution view that displays drills chronologically with
/// timers. State lives in `LiveSessionEngine.shared` so the screen can be
/// dismissed without ending the run — the timer keeps ticking and a banner
/// elsewhere in the app lets the coach return.
struct LiveSessionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    @ObservedObject private var engine = LiveSessionEngine.shared

    /// Called when the live run actually ends (Save & End).
    let onEnd: () -> Void

    @State private var showingEndConfirmation = false
    @State private var showingAttendance = false
    @State private var showingNotes = false
    @State private var showingDrillDetail: DrillItem?
    @State private var showingRollCallSheet = false
    @State private var sessionNotes: String = ""
    /// Index into the current drill's media when the viewer is open.
    @State private var liveViewerMedia: LiveViewerTarget?

    /// Pairs a drill ID with an index so SwiftUI can rebuild the cover when
    /// either changes (e.g. jumping to the next drill while the viewer is up).
    fileprivate struct LiveViewerTarget: Identifiable, Hashable {
        let drillId: UUID
        let index: Int
        var id: String { "\(drillId.uuidString)#\(index)" }
    }

    private var session: SessionEvent? { engine.session }
    private var drills: [LiveDrillItem] { engine.drills }
    private var current: LiveDrillItem? { engine.currentDrill }
    private var programColor: Color { Color(hex: engine.programColorHex) }

    private var enrolledStudents: [Student] {
        guard let s = session else { return [] }
        if let pid = s.programId,
           let p = dataManager.programs.first(where: { $0.id == pid }) {
            return dataManager.students.filter { p.enrolledStudentIds.contains($0.id) }
        }
        return dataManager.students.filter { s.attendeeIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if let s = session {
                VStack(spacing: 0) {
                    liveHeader(session: s)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // When there's no current drill (i.e. the
                            // session has run through everything) we skip
                            // the celebratory "All Drills Complete!" card —
                            // the timeline + quick actions + End Session
                            // button below are the actually useful UI for
                            // wrapping up.
                            if let item = current {
                                currentDrillCard(item)
                            }
                            drillTimeline
                            quickActions(session: s)
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }

                    bottomControls
                }
            } else {
                TimeoutSpinner(
                    label: LocalizationManager.shared.currentLanguage == .chinese ? "无法恢复课程" : "Couldn't resume session"
                )
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .onAppear {
            sessionNotes = engine.session?.coachNotes ?? ""
        }
        .onChange(of: engine.rollCallPromptPending) { _, pending in
            if pending { showingRollCallSheet = true }
        }
        .sheet(isPresented: $showingAttendance) {
            if let s = session {
                LiveAttendanceSheet(
                    session: bindingForEngineSession(),
                    students: enrolledStudents,
                    programColor: programColor,
                    onSave: persist
                )
                .onDisappear { _ = s }  // keep s referenced
            }
        }
        .sheet(isPresented: $showingNotes) {
            LiveNotesSheet(notes: $sessionNotes, programColor: programColor) {
                if var s = engine.session {
                    s.coachNotes = sessionNotes.isEmpty ? nil : sessionNotes
                    engine.session = s
                    persist()
                }
            }
        }
        .sheet(item: $showingDrillDetail) { drill in
            NavigationStack { DrillDetailView(drill: drill) }
        }
        .fullScreenCover(item: $liveViewerMedia) { target in
            // Resolve the drill fresh each time the cover presents — the
            // engine may have advanced and we want the carousel to match
            // what's on the live card. LiveDrillItem.id is its own UUID;
            // match on the inner drill's id.
            if let item = drills.first(where: { $0.drill.id == target.drillId }) {
                DrillMediaViewer(media: item.drill.media, initialIndex: target.index)
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showingRollCallSheet, onDismiss: {
            engine.dismissRollCallPrompt()
        }) {
            RollCallPhotoSheet(programColor: programColor) { image in
                #if os(iOS)
                if let s = engine.session,
                   let path = PhotoCaptureManager.shared.saveAttendancePhoto(image, for: s.id) {
                    var updated = s
                    updated.attendancePhotoPath = path
                    engine.session = updated
                    persist()
                }
                #endif
                engine.dismissRollCallPrompt()
            }
        }
        .alert("End Session?", isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Session", role: .destructive) { performEnd() }
        } message: {
            Text("This will complete the session. Make sure to take attendance first.")
        }
    }

    // MARK: - Header

    private func liveHeader(session: SessionEvent) -> some View {
        VStack(spacing: 12) {
            HStack {
                // Closes the screen but keeps the run going.
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.isPaused ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.red))
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse, options: .repeating, isActive: !engine.isPaused)
                    Text(engine.isPaused ? "PAUSED" : "LIVE")
                        .font(.caption.weight(.bold))
                        .monospaced()
                }
                .foregroundStyle(engine.isPaused ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.red))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())

                Spacer()

                Button {
                    engine.togglePause()
                } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(Color.accentColor)
                .sensoryFeedback(.impact, trigger: engine.isPaused)
            }

            VStack(spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // BIG: time remaining. Small: elapsed (the inverse of the
                // previous design). The countdown is the action coaches care
                // about during the session.
                Text(formatTime(engine.sessionRemainingSeconds))
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())

                ProgressView(value: engine.sessionProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)

                Text("\(formatTime(engine.sessionElapsedSeconds)) elapsed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: - Current Drill Card

    private func currentDrillCard(_ item: LiveDrillItem) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(item.section.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Spacer()
                Text("Drill \(engine.currentDrillIndex + 1) of \(drills.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(item.drill.name)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 12).frame(width: 160, height: 160)
                Circle().trim(from: 0, to: drillProgress(for: item))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: drillProgress(for: item))
                VStack(spacing: 4) {
                    Text(formatTime(drillRemaining(for: item)))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("remaining")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !item.drill.description.isEmpty {
                Text(item.drill.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            // Drill visuals during the live session — diagrams, photos,
            // videos, YouTube refs. Tap to open the full-screen viewer.
            // Compact tile size keeps the timer + controls visible.
            if !item.drill.media.isEmpty {
                DrillMediaCarousel(
                    media: item.drill.media,
                    tileSize: 84,
                    horizontalPadding: 0,
                    onTap: { _, index in
                        HapticFeedback.impact(.light)
                        liveViewerMedia = LiveViewerTarget(drillId: item.drill.id, index: index)
                    },
                    onAdd: nil
                )
            }

            HStack(spacing: 12) {
                Button { engine.previousDrill() } label: {
                    Label("Previous", systemImage: "backward.fill").font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(.secondary)
                .disabled(engine.currentDrillIndex == 0)

                Button { engine.nextDrill() } label: {
                    Label("Next", systemImage: "forward.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color.accentColor)
                .sensoryFeedback(.impact, trigger: engine.currentDrillIndex)
            }

            Button {
                showingDrillDetail = item.drill
            } label: {
                Label("Drill details", systemImage: "info.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    // MARK: - Timeline

    private var drillTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DRILL TIMELINE")
                .font(.caption2.weight(.bold))
                .monospaced()
                .foregroundStyle(.tertiary)
            VStack(spacing: 0) {
                ForEach(Array(drills.enumerated()), id: \.element.id) { index, item in
                    LiveTimelineDrillRow(
                        item: item,
                        index: index,
                        currentIndex: engine.currentDrillIndex,
                        isLast: index == drills.count - 1
                    ) {
                        // Tap on a drill row → open its detail. Long-press
                        // (handled below in the row) jumps to it.
                        showingDrillDetail = item.drill
                    } onJumpTo: {
                        engine.jump(to: index)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Quick Actions

    private func quickActions(session: SessionEvent) -> some View {
        HStack(spacing: 12) {
            quickAction(icon: "person.2.fill",
                        label: "Attendance",
                        badge: "\(session.actualAttendeeIds.count)/\(enrolledStudents.count)",
                        active: session.actualAttendeeIds.count > 0) {
                showingAttendance = true
            }

            quickAction(icon: "note.text",
                        label: "Notes",
                        badge: sessionNotes.isEmpty ? "Add" : "Edit",
                        active: !sessionNotes.isEmpty) {
                showingNotes = true
            }
        }
    }

    private func quickAction(icon: String, label: String, badge: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.headline).foregroundStyle(Color.accentColor)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showingEndConfirmation = true
            } label: {
                Label("End Session", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(.red)
            .padding(16)
            .background(.regularMaterial)
        }
    }

    // MARK: - Helpers

    private func drillProgress(for item: LiveDrillItem) -> Double {
        guard item.durationSeconds > 0 else { return 0 }
        return min(Double(engine.drillElapsedSeconds) / Double(item.durationSeconds), 1.0)
    }

    private func drillRemaining(for item: LiveDrillItem) -> Int {
        max(item.durationSeconds - engine.drillElapsedSeconds, 0)
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func bindingForEngineSession() -> Binding<SessionEvent> {
        Binding(
            get: { engine.session ?? SessionEvent(title: "", date: Date(), startTime: Date(), endTime: Date()) },
            set: { engine.session = $0 }
        )
    }

    private func persist() {
        if var s = engine.session {
            s.updatedAt = Date()
            engine.session = s
            dataManager.updateSessionEvent(s)
        }
    }

    private func performEnd() {
        if var s = engine.session {
            for item in drills where !s.drillsCompleted.contains(item.drill.id) {
                s.drillsCompleted.append(item.drill.id)
            }
            s.status = .completed
            s.coachNotes = sessionNotes.isEmpty ? nil : sessionNotes
            engine.session = s
            dataManager.updateSessionEvent(s)
        }
        engine.end()
        onEnd()
        dismiss()
    }
}

// MARK: - Roll Call Photo Sheet
struct RollCallPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let programColor: Color
    let onCaptured: (PlatformImage) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var loadedImage: PlatformImage?
    #if os(iOS)
    @State private var showingCamera = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                Text("Roll-call photo")
                    .font(.title2.weight(.semibold))

                Text("5 minutes left in this session. Snap a quick group photo to record who was there — it'll be saved to this session's notes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let img = loadedImage {
                    #if os(iOS)
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    #else
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    #endif
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    #if os(iOS)
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    #endif

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if loadedImage != nil {
                        Button {
                            if let img = loadedImage { onCaptured(img); dismiss() }
                        } label: {
                            Label("Save to session", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Roll Call")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = PlatformImage(data: data) {
                        await MainActor.run { loadedImage = img }
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: Binding(
                    get: { loadedImage },
                    set: { loadedImage = $0 }
                ))
            }
            #endif
        }
    }
}
