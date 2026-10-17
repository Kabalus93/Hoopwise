import SwiftUI

// MARK: - AthletePickerSheet
/// The single source of truth for "pick athletes" surfaces across the app.
/// Used by:
///   - Session attendance → enroll new athletes into the program
///   - Edit Enrolled Students (program detail)
///   - Create Program / Create Session splash flows
///
/// Designed so every entry point shares the same affordances:
///   * Profile photo (real photo via `StudentAvatarView`, fallback to a
///     colored-initials avatar baked into the same component).
///   * Multi-select with a count chip at the top.
///   * Search by Latin name OR Chinese name.
///   * Filter chips: most recently added · A→Z · by age.
///   * Optional info banner (e.g. "Sessions count from here") set by the
///     caller without subclassing.
struct AthletePickerSheet: View {
    enum SortMode: Hashable, CaseIterable, Identifiable {
        case recentlyAdded
        case byName
        case byAge

        var id: SortMode { self }

        func localizedLabel(isChinese: Bool) -> String {
            switch self {
            case .recentlyAdded: return isChinese ? "最近加入" : "Recent"
            case .byName:        return isChinese ? "字母" : "A→Z"
            case .byAge:         return isChinese ? "年龄" : "Age"
            }
        }

        var iconName: String {
            switch self {
            case .recentlyAdded: return "clock"
            case .byName:        return "textformat"
            case .byAge:         return "person.crop.rectangle.stack"
            }
        }
    }

    /// Configuration for the optional banner above the search bar.
    struct Banner {
        let title: String
        let subtitle: String
        let icon: String       // SF Symbol, default = "info.circle.fill"
        let tint: Color        // background tint + icon color

        init(title: String, subtitle: String, icon: String = "info.circle.fill", tint: Color) {
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.tint = tint
        }
    }

    let title: String
    /// Pool the user is choosing from. Caller is responsible for any pre-
    /// filtering (e.g. excluding already-enrolled students).
    let students: [Student]
    /// Initial selection. Returned via `onConfirm` when the user taps Done.
    let initialSelection: Set<UUID>
    /// Accent color — typically the parent program's color so the selection
    /// state visually matches what the picker is feeding into.
    let accentColor: Color
    /// Optional banner shown above the search bar.
    let banner: Banner?
    /// Label for the confirm button ("Add", "Done", etc.). The count is
    /// appended automatically when more than 1 row is selected.
    let confirmLabel: String
    /// Show the "X athletes selected" counter row. Off for single-action
    /// "add" flows that already show the count in the toolbar button.
    let showSelectionCounter: Bool

    let onConfirm: ([UUID]) -> Void

    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .recentlyAdded

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    // MARK: - Init
    init(
        title: String,
        students: [Student],
        initialSelection: Set<UUID> = [],
        accentColor: Color = .purple,
        banner: Banner? = nil,
        confirmLabel: String? = nil,
        showSelectionCounter: Bool = true,
        onConfirm: @escaping ([UUID]) -> Void
    ) {
        self.title = title
        self.students = students
        self.initialSelection = initialSelection
        self.accentColor = accentColor
        self.banner = banner
        self.confirmLabel = confirmLabel
            ?? (LocalizationManager.shared.currentLanguage == .chinese ? "完成" : "Done")
        self.showSelectionCounter = showSelectionCounter
        self.onConfirm = onConfirm
    }

    // MARK: - Derived
    /// Search + sort applied. We keep this as a computed view so any of
    /// `students` / `searchText` / `sortMode` changing reactively rebuilds
    /// the list.
    private var visibleStudents: [Student] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        let filtered: [Student] = students.filter { student in
            if needle.isEmpty { return true }
            return student.name.localizedStandardContains(needle)
                || (student.chineseName ?? "").localizedStandardContains(needle)
        }
        switch sortMode {
        case .recentlyAdded:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .byName:
            return filtered.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .byAge:
            // Older first (higher age). Students with unknown age sink to
            // the bottom so the sort still produces a stable order.
            return filtered.sorted { lhs, rhs in
                switch (lhs.age, rhs.age) {
                case let (l?, r?): return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none):
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
            }
        }
    }

    private var confirmButtonTitle: String {
        let count = selected.count
        if count <= 1 { return confirmLabel }
        return "\(confirmLabel) (\(count))"
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner {
                    bannerView(banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                searchBar
                sortChips

                if showSelectionCounter {
                    selectionCounter
                }

                if visibleStudents.isEmpty {
                    emptyState
                } else {
                    listView
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        // Preserve on-screen order — callers can rely on
                        // `[UUID]` matching the visible list, not insertion
                        // order from the Set.
                        let ordered = visibleStudents.map(\.id).filter { selected.contains($0) }
                        // Append any selected IDs that filtered/searched out
                        // of the visible list so they don't get dropped.
                        let extras = selected.subtracting(ordered)
                        onConfirm(ordered + extras)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor.accessibleText)
                    .disabled(selected.isEmpty && initialSelection.isEmpty)
                }
            }
            .onAppear {
                if selected.isEmpty { selected = initialSelection }
            }
        }
    }

    // MARK: - Banner
    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 12) {
            Image(systemName: banner.icon)
                .font(.system(size: 18))
                .foregroundColor(banner.tint.accessibleText)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(banner.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(banner.tint.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textTertiary)
            TextField(isChinese ? "搜索学员..." : "Search athletes...", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Sort chips
    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases) { mode in
                    sortChip(mode)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
    }

    private func sortChip(_ mode: SortMode) -> some View {
        let isSelected = mode == sortMode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                sortMode = mode
            }
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(mode.localizedLabel(isChinese: isChinese))
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : AppTheme.textSecondary)
            .background(
                Capsule().fill(
                    isSelected
                        ? accentColor
                        : Color(.tertiarySystemFill)
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection counter
    private var selectionCounter: some View {
        HStack {
            Text(isChinese ? "已选择 \(selected.count) 名学员" : "\(selected.count) athletes selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            if !selected.isEmpty {
                Button(isChinese ? "清除" : "Clear") {
                    selected.removeAll()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(visibleStudents) { student in
                    row(student)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    private func row(_ student: Student) -> some View {
        let isSelected = selected.contains(student.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected { selected.remove(student.id) }
                else          { selected.insert(student.id) }
            }
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 12) {
                // Multi-select checkmark
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : AppTheme.textTertiary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(accentColor.accessibleText)
                    }
                }

                // Avatar — real photo when available, colored initials
                // fallback. `StudentAvatarView` already encapsulates both
                // branches so we don't have to duplicate the placeholder
                // here.
                StudentAvatarView(student: student, size: 44)

                // Name block
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    HStack(spacing: 8) {
                        if let chinese = student.secondaryNameLine {
                            Text(chinese)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        if let age = student.age {
                            Text(isChinese ? "\(age) 岁" : "Age \(age)")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? accentColor.opacity(0.10) : AppTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textTertiary)
            Text(emptyMessage)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return isChinese ? "没有找到匹配的学员" : "No matching students found"
        }
        return isChinese ? "暂无可选学员" : "No available students"
    }
}
