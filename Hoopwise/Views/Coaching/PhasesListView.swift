import SwiftUI

/// A list view for browsing and managing phases (micro cycles) with multi-selection support
struct PhasesListView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    let program: Program
    
    @State private var selectedPhases: Set<UUID> = []
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var showingDeleteConfirmation = false
    @State private var showingAddPhase = false
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
            // Only show Add Phase button if user has permission
            if authManager.canCreatePhases {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddPhase = true }) {
                        Label(isChinese ? "添加阶段" : "Add Phase", systemImage: "plus")
                    }
                }
            }
            
            #if os(iOS)
            if authManager.canDeletePhases {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            #endif
            
            #if os(iOS)
            if editMode.isEditing && !selectedPhases.isEmpty && authManager.canDeletePhases {
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
            AddPhaseView(program: program, nextPhaseNumber: microCycles.count + 1)
        }
        .alert(isChinese ? "删除阶段" : "Delete Phases", isPresented: $showingDeleteConfirmation) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                deleteSelectedPhases()
            }
        } message: {
            Text(isChinese ? "确定要删除 \(selectedPhases.count) 个阶段吗？此操作无法撤销。" : "Are you sure you want to delete \(selectedPhases.count) phase(s)? This action cannot be undone.")
        }
    }
    
    private var emptyStateView: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ContentUnavailableView {
            Label(isChinese ? "暂无阶段" : "No Phases", systemImage: "square.stack.3d.up")
        } description: {
            Text(isChinese ? "添加训练阶段以组织你的训练计划" : "Add training phases to organize your program")
        } actions: {
            Button(action: { showingAddPhase = true }) {
                Text(isChinese ? "添加阶段" : "Add Phase")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var phasesList: some View {
        List(selection: $selectedPhases) {
            ForEach(filteredPhases) { phase in
                NavigationLink(destination: MicroCycleDetailView(microCycle: phase, program: program)) {
                    PhaseRowView(phase: phase, accentColor: Color(hex: program.colorHex))
                }
                .tag(phase.id)
            }
            .onDelete(perform: deletePhases)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
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
