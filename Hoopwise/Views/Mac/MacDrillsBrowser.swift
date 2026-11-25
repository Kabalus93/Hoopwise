//
//  MacDrillsBrowser.swift
//  Hoopwise
//
//  The Mac's Drills page (25 Nov 2026, Luther: the pages "still scream iPad"):
//  the library on the left, the drill beside it — a row no longer replaces the
//  whole page with the drill. iPhone and iPad are untouched: the library only
//  behaves this way when the two environment values below are set.
//

import SwiftUI

private struct MacDrillSelectKey: EnvironmentKey {
    static let defaultValue: ((DrillItem) -> Void)? = nil
}
private struct MacDrillSelectedKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct MacDrillFilterPanelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by the Mac's browser when the window is wide: the library shows
    /// its filters as a panel beside the list instead of chips above it.
    var macDrillFilterPanel: Bool {
        get { self[MacDrillFilterPanelKey.self] }
        set { self[MacDrillFilterPanelKey.self] = newValue }
    }
    /// Set by the Mac's browser: a drill row calls it instead of pushing.
    var macDrillSelect: ((DrillItem) -> Void)? {
        get { self[MacDrillSelectKey.self] }
        set { self[MacDrillSelectKey.self] = newValue }
    }
    /// The drill open beside the list.
    var macDrillSelectedId: UUID? {
        get { self[MacDrillSelectedKey.self] }
        set { self[MacDrillSelectedKey.self] = newValue }
    }
}

struct MacDrillsBrowser: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedId: UUID?
    @State private var width: CGFloat = 0

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var selected: DrillItem? {
        selectedId.flatMap { id in dataManager.drills.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if width >= 900 {
                HStack(spacing: 0) {
                    // Three panes from 1000 pt: filters | drills | the drill.
                    NavigationStack { DrillsLibraryView() }
                        .environment(\.macDrillSelect) { selectedId = $0.id }
                        .environment(\.macDrillSelectedId, selectedId)
                        .environment(\.macDrillFilterPanel, width >= 1000)
                        .frame(width: width >= 1000 ? 241 + min(480, max(360, (width - 241) * 0.42))
                                                    : min(430, width * 0.42))
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityIdentifier("drills.macLayout")
            } else {
                NavigationStack { DrillsLibraryView() }
            }
        }
        .onGeometryChange(for: CGFloat.self) { ($0.size.width / 20).rounded() * 20 } action: { width = $0 }
    }

    @ViewBuilder private var detail: some View {
        if let drill = selected {
            NavigationStack {
                DrillDetailView(drill: drill)
                    .modifier(FilmRoomDestination())
            }
            .id(drill.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "figure.basketball")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(isChinese ? "选择一个训练" : "Choose a drill")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.secondary)
                Text(isChinese ? "\(dataManager.drills.filter { !$0.isSeries }.count) 个训练" : "\(dataManager.drills.filter { !$0.isSeries }.count) drills")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("drills.macEmpty")
        }
    }
}
