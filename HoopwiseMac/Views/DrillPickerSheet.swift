import SwiftUI

// MARK: - Drill Picker
/// Edit a session's curriculum: add/remove drills per phase, adjust phase
/// minutes. Saves through `dataManager.updateSessionEvent`. Robust against
/// concurrent mutations — operates on a working copy until the user commits.
struct DrillPickerSheet: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var workingCurriculum: SessionCurriculum
    @State private var search: String = ""
    @State private var category: DrillCategory? = nil
    @State private var difficulty: DifficultyLevel? = nil
    @State private var activePhase: Phase = .skills

    enum Phase: String, CaseIterable, Identifiable {
        case warmup, skills, games
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .warmup: return "flame.fill"
            case .skills: return "figure.basketball"
            case .games: return "trophy.fill"
            }
        }
        var tint: Color {
            switch self {
            case .warmup: return .orange
            case .skills: return .blue
            case .games: return .purple
            }
        }
    }

    init(session: SessionEvent) {
        self.session = session
        _workingCurriculum = State(initialValue: session.curriculum)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                librarySide.frame(minWidth: 360, idealWidth: 420)
                Divider()
                planSide.frame(minWidth: 380)
            }
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 580)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Session Plan").font(.title2.weight(.semibold))
                Text(session.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Text("\(workingCurriculum.totalDrillCount) drills · \(workingCurriculum.totalMinutes) min")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save Plan") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(workingCurriculum == session.curriculum)
        }
        .padding(16)
    }

    // MARK: - Library side

    private var librarySide: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search library", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(12)

            HStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    Text("All").tag(DrillCategory?.none)
                    ForEach(DrillCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(Optional(c))
                    }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small)
                Picker("Level", selection: $difficulty) {
                    Text("Any").tag(DifficultyLevel?.none)
                    ForEach(DifficultyLevel.allCases, id: \.self) { d in
                        Text(d.displayName).tag(Optional(d))
                    }
                }
                .pickerStyle(.menu).labelsHidden().controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 12)

            Divider().padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredLibrary) { drill in
                        LibraryRow(
                            drill: drill,
                            inActivePhase: drillsInPhase(activePhase).contains(drill.id),
                            onAdd: { add(drill) }
                        )
                    }
                    if filteredLibrary.isEmpty {
                        Text("No drills match.").foregroundStyle(.secondary).padding(20)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredLibrary: [DrillItem] {
        var result = dataManager.cachedDrills
        if let category { result = result.filter { $0.category == category } }
        if let difficulty { result = result.filter { $0.difficulty == difficulty } }
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: - Plan side

    private var planSide: some View {
        VStack(spacing: 0) {
            Picker("Phase", selection: $activePhase) {
                ForEach(Phase.allCases) { p in
                    Label(p.label, systemImage: p.systemImage).tag(p)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    phaseEditor(for: .warmup)
                    Divider()
                    phaseEditor(for: .skills)
                    Divider()
                    phaseEditor(for: .games)
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func phaseEditor(for phase: Phase) -> some View {
        let ids = drillsInPhase(phase)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: phase.systemImage).foregroundStyle(phase.tint)
                Text(phase.label).font(.subheadline.weight(.semibold))
                Spacer()
                Stepper("\(minutes(for: phase))m", value: minutesBinding(for: phase), in: 0...180, step: 5)
                    .controlSize(.small)
                    .labelsHidden()
                Text("\(minutes(for: phase))m").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
            if ids.isEmpty {
                Text("No drills here yet. Tap a drill from the library to add.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(ids.enumerated()), id: \.element) { idx, id in
                        if let drill = dataManager.cachedDrills.first(where: { $0.id == id }) {
                            PlanRow(
                                drill: drill,
                                tint: phase.tint,
                                canMoveUp: idx > 0,
                                canMoveDown: idx < ids.count - 1,
                                onUp: { moveDrill(in: phase, at: idx, by: -1) },
                                onDown: { moveDrill(in: phase, at: idx, by: 1) },
                                onRemove: { remove(drillId: id, from: phase) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Curriculum mutation helpers

    private func drillsInPhase(_ phase: Phase) -> [UUID] {
        switch phase {
        case .warmup: return workingCurriculum.warmupDrillIds
        case .skills: return workingCurriculum.skillDrillIds
        case .games: return workingCurriculum.gameDrillIds
        }
    }

    private func minutes(for phase: Phase) -> Int {
        switch phase {
        case .warmup: return workingCurriculum.warmupMinutes
        case .skills: return workingCurriculum.skillsMinutes
        case .games: return workingCurriculum.gameMinutes
        }
    }

    private func minutesBinding(for phase: Phase) -> Binding<Int> {
        Binding(
            get: { minutes(for: phase) },
            set: { newValue in
                let clamped = max(0, min(180, newValue))
                switch phase {
                case .warmup: workingCurriculum.warmupMinutes = clamped
                case .skills: workingCurriculum.skillsMinutes = clamped
                case .games: workingCurriculum.gameMinutes = clamped
                }
            }
        )
    }

    private func add(_ drill: DrillItem) {
        // Prevent duplicates within the active phase
        switch activePhase {
        case .warmup:
            guard !workingCurriculum.warmupDrillIds.contains(drill.id) else { return }
            workingCurriculum.warmupDrillIds.append(drill.id)
        case .skills:
            guard !workingCurriculum.skillDrillIds.contains(drill.id) else { return }
            workingCurriculum.skillDrillIds.append(drill.id)
        case .games:
            guard !workingCurriculum.gameDrillIds.contains(drill.id) else { return }
            workingCurriculum.gameDrillIds.append(drill.id)
        }
    }

    private func remove(drillId: UUID, from phase: Phase) {
        switch phase {
        case .warmup: workingCurriculum.warmupDrillIds.removeAll { $0 == drillId }
        case .skills: workingCurriculum.skillDrillIds.removeAll { $0 == drillId }
        case .games: workingCurriculum.gameDrillIds.removeAll { $0 == drillId }
        }
    }

    private func moveDrill(in phase: Phase, at index: Int, by delta: Int) {
        var ids = drillsInPhase(phase)
        let target = index + delta
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        switch phase {
        case .warmup: workingCurriculum.warmupDrillIds = ids
        case .skills: workingCurriculum.skillDrillIds = ids
        case .games: workingCurriculum.gameDrillIds = ids
        }
    }

    private func save() {
        var copy = session
        copy.curriculum = workingCurriculum
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy)
        dismiss()
    }
}

// MARK: - Library row

private struct LibraryRow: View {
    let drill: DrillItem
    let inActivePhase: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: drill.category.icon)
                .foregroundStyle(Color(hex: drill.category.color))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(drill.name).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(drill.category.displayName).font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(drill.durationMinutes)m").font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(drill.difficulty.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: inActivePhase ? "checkmark" : "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(inActivePhase)
            .help(inActivePhase ? "Already in this phase" : "Add to active phase")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let drill: DrillItem
    let tint: Color
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint).frame(width: 3, height: 24)
            Text(drill.name).font(.caption.weight(.medium)).lineLimit(1)
            Spacer()
            Text("\(drill.durationMinutes)m").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button(action: onUp) { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).controlSize(.mini).disabled(!canMoveUp)
            Button(action: onDown) { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).controlSize(.mini).disabled(!canMoveDown)
            Button(role: .destructive, action: onRemove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.borderless).controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
