import SwiftUI

/// A list view for browsing and managing phases (micro cycles) with multi-selection support
struct PhasesListView: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program

    @State private var selectedPhases: Set<UUID> = []
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var showingDeleteConfirmation = false
    @State private var showingAddPhase = false
    @State private var showingGenerateConfirmation = false
    @State private var searchText = ""
    
    var microCycles: [MicroCycle] {
        dataManager.microCycles.filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }
    
    var filteredPhases: [MicroCycle] {
        if searchText.isEmpty {
            return microCycles
        }
        return microCycles.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.focus.map { $0.rawValue }.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        Group {
            if filteredPhases.isEmpty {
                emptyStateView
            } else {
                phasesList
            }
        }
        .navigationTitle(isChinese ? "训练阶段" : "Training Phases")
        .searchable(text: $searchText, prompt: isChinese ? "搜索阶段" : "Search phases")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddPhase = true }) {
                    Label(isChinese ? "添加阶段" : "Add Phase", systemImage: "plus")
                }
            }

            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }

            if editMode.isEditing && !selectedPhases.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .sheet(isPresented: $showingAddPhase) {
            AddPhaseOnboardingView(program: program, nextPhaseNumber: microCycles.count + 1)
                .environmentObject(dataManager)
        }
        .alert(isChinese ? "删除阶段" : "Delete Phases", isPresented: $showingDeleteConfirmation) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                deleteSelectedPhases()
            }
        } message: {
            Text(isChinese ? "确定要删除 \(selectedPhases.count) 个阶段吗？此操作无法撤销。" : "Are you sure you want to delete \(selectedPhases.count) phase(s)? This action cannot be undone.")
        }
        .confirmationDialog(
            isChinese ? "应用 FEB 模板？" : "Apply FEB template?",
            isPresented: $showingGenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button(isChinese ? "生成 \(suggestedTemplateCount) 个阶段" : "Generate \(suggestedTemplateCount) phases") {
                generatePhasesFromTemplate()
            }
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
        } message: {
            Text(isChinese
                 ? "将基于 \(program.ageGroup.rawValue) 推荐的 FEB 周期为本计划生成完整阶段。你之后仍可编辑每个阶段。"
                 : "We'll seed this program with the FEB-recommended phase chain for \(program.ageGroup.rawValue). You can edit each phase afterwards.")
        }
    }

    private var suggestedTemplateCount: Int {
        PhaseTemplateStore.shared.defaultPhases(for: program.ageGroup).count
    }

    private func generatePhasesFromTemplate() {
        let templates = PhaseTemplateStore.shared.defaultPhases(for: program.ageGroup)
        guard !templates.isEmpty else { return }

        let cal = Calendar.current
        var cursor: Date = program.startDate ?? cal.startOfDay(for: Date())

        for (i, template) in templates.enumerated() {
            let endDate = cal.date(byAdding: .day, value: template.weeks * 7, to: cursor) ?? cursor
            let phase = template.instantiate(
                programId: program.id,
                phaseNumber: microCycles.count + i + 1,
                startingOn: cursor
            )
            dataManager.addMicroCycle(phase)
            // Materialize sessions on the program's recurring weekday(s).
            dataManager.materializeSessions(for: phase)
            cursor = cal.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
    }
    
    private var emptyStateView: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let templateCount = suggestedTemplateCount
        return ContentUnavailableView {
            Label(isChinese ? "暂无阶段" : "No Phases", systemImage: "square.stack.3d.up")
        } description: {
            Text(isChinese
                 ? "添加训练阶段以组织你的训练计划，或基于 \(program.ageGroup.rawValue) 一键生成 FEB 周期。"
                 : "Build the season by hand, or generate a FEB-recommended phase chain for \(program.ageGroup.rawValue).")
        } actions: {
            VStack(spacing: 10) {
                if templateCount > 0 {
                    Button {
                        showingGenerateConfirmation = true
                    } label: {
                        Label(isChinese ? "生成 \(templateCount) 个阶段" : "Generate \(templateCount) phases",
                              systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(isChinese ? "添加阶段" : "Add Phase") { showingAddPhase = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var phasesList: some View {
        // The list uses native `.onMove` so dragging swaps positions; the
        // reorder handler walks the new order through DataManager which
        // re-anchors phase startDate/endDate and shifts all sessions inside
        // each phase by Δ. Calendar order can't drift out of sync with the
        // visual list — they're recomputed from the same source.
        List(selection: $selectedPhases) {
            ForEach(filteredPhases) { phase in
                NavigationLink(destination: MicroCycleDetailView(microCycle: phase, program: program)) {
                    PhaseRowView(phase: phase, accentColor: Color(hex: program.colorHex))
                }
                .tag(phase.id)
            }
            .onMove(perform: reorderPhases)
            .onDelete(perform: deletePhases)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
    }

    private func reorderPhases(from source: IndexSet, to destination: Int) {
        // Reorder is only meaningful when no search filter is active —
        // otherwise the indices we're handed don't map cleanly back to the
        // canonical phase chain, and we'd silently shift the wrong phases.
        guard searchText.isEmpty else { return }
        dataManager.reorderPhases(in: program.id, oldIndices: source, newOffset: destination)
    }
    
    #if os(iOS)
    private func toggleEditMode() {
        withAnimation {
            editMode = editMode.isEditing ? .inactive : .active
            if !editMode.isEditing {
                selectedPhases.removeAll()
            }
        }
    }
    #endif
    
    private func deletePhases(at offsets: IndexSet) {
        for index in offsets {
            let phase = filteredPhases[index]
            dataManager.deleteMicroCycle(phase)
        }
    }
    
    private func deleteSelectedPhases() {
        for phaseId in selectedPhases {
            if let phase = microCycles.first(where: { $0.id == phaseId }) {
                dataManager.deleteMicroCycle(phase)
            }
        }
        selectedPhases.removeAll()
        #if os(iOS)
        editMode = .inactive
        #endif
    }
}

struct PhaseRowView: View {
    let phase: MicroCycle
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\(phase.phaseNumber)")
                        .font(.headline)
                        .foregroundColor(accentColor)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(phase.title)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Label("\(phase.durationWeeks)w", systemImage: "calendar")
                    
                    if !phase.focus.isEmpty {
                        Text(phase.focus.prefix(2).map { $0.rawValue.capitalized }.joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
