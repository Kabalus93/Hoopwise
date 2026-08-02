import SwiftUI
import AppKit

// MARK: - Directory pattern
//
// The Apple-Contacts skeleton: groups column → indexed list → detail card,
// three columns INSIDE the page, independent of the app's main sidebar.
// Entity-agnostic: the page instance (Athletes first, Sessions later) supplies
// groups, filtered+sorted items, a row, and a card; this view owns layout,
// the A–Z rail, group selection plumbing, and drag-to-group targets.
//
// Deliberately not over-abstracted: everything here is exercised by the
// Athletes instance. Generalize further only when a second page needs it.

/// One selectable group in the groups column.
struct DirectoryGroup: Identifiable, Hashable {
    let id: String
    var title: String
    var icon: String?
    var count: Int
    /// User-created: renamable, deletable, and a drag-in target.
    var isUserGroup = false
    /// Shows the rule-editor affordance (the smart-group threshold).
    var isEditableSmart = false
}

struct DirectoryGroupSection: Identifiable {
    let id: String
    var title: String?
    var groups: [DirectoryGroup]
}

struct DirectoryView<Item: Identifiable, RowContent: View, DetailContent: View>: View
where Item.ID == UUID {
    let groupSections: [DirectoryGroupSection]
    @Binding var selectedGroups: Set<String>
    /// Group-filtered, searched, SORTED items. Sections derive from
    /// `sectionKey` over this order — one ordering feeds list and rail.
    let items: [Item]
    let sectionKey: (Item) -> String
    @Binding var searchText: String
    var searchPrompt = "Search"
    @Binding var selection: UUID?
    /// Trailing accessory beside the count (the sort menu).
    let countLabel: String
    /// Groups-column persistence key prefix, one per directory page.
    let storageKey: String
    /// The A–Z rail fits name-collated pages; date-sectioned pages hide it.
    var showsIndexRail = true

    @ViewBuilder let row: (Item) -> RowContent
    @ViewBuilder let listAccessory: () -> AnyView
    @ViewBuilder let detail: () -> DetailContent

    /// Drag-in membership: item ids dropped on a user group.
    var onDropMembers: ((DirectoryGroup, [UUID]) -> Void)?
    var onCreateGroup: (() -> Void)?
    var onRenameGroup: ((DirectoryGroup, String) -> Void)?
    var onDeleteGroup: ((DirectoryGroup) -> Void)?
    var onEditSmartRule: ((DirectoryGroup) -> Void)?

    /// Search-field focus is driven by the keyboard layer (⌘F).
    var searchFocusToken: Int = 0

    @AppStorage private var groupsVisible: Bool
    @FocusState private var searchFocused: Bool
    @State private var renamingGroup: DirectoryGroup?
    @State private var renameDraft = ""

    init(groupSections: [DirectoryGroupSection],
         selectedGroups: Binding<Set<String>>,
         items: [Item],
         sectionKey: @escaping (Item) -> String,
         searchText: Binding<String>,
         searchPrompt: String = "Search",
         selection: Binding<UUID?>,
         countLabel: String,
         storageKey: String,
         showsIndexRail: Bool = true,
         searchFocusToken: Int = 0,
         onDropMembers: ((DirectoryGroup, [UUID]) -> Void)? = nil,
         onCreateGroup: (() -> Void)? = nil,
         onRenameGroup: ((DirectoryGroup, String) -> Void)? = nil,
         onDeleteGroup: ((DirectoryGroup) -> Void)? = nil,
         onEditSmartRule: ((DirectoryGroup) -> Void)? = nil,
         @ViewBuilder row: @escaping (Item) -> RowContent,
         @ViewBuilder listAccessory: @escaping () -> AnyView,
         @ViewBuilder detail: @escaping () -> DetailContent) {
        self.groupSections = groupSections
        self._selectedGroups = selectedGroups
        self.items = items
        self.sectionKey = sectionKey
        self._searchText = searchText
        self.searchPrompt = searchPrompt
        self._selection = selection
        self.countLabel = countLabel
        self.storageKey = storageKey
        self.showsIndexRail = showsIndexRail
        self.searchFocusToken = searchFocusToken
        self.onDropMembers = onDropMembers
        self.onCreateGroup = onCreateGroup
        self.onRenameGroup = onRenameGroup
        self.onDeleteGroup = onDeleteGroup
        self.onEditSmartRule = onEditSmartRule
        self.row = row
        self.listAccessory = listAccessory
        self.detail = detail
        self._groupsVisible = AppStorage(wrappedValue: true, "\(storageKey).groupsVisible")
    }

    var body: some View {
        // The resize contract, Contacts-style: detail gives space first
        // (flexible), the list compresses to its min, then the GROUPS column
        // collapses. Collapse derives from the page width the parent hands us
        // — a stable input, so no size→state→size feedback — and the user's
        // groupsVisible preference is never overwritten by the auto-collapse.
        GeometryReader { geo in
            let groupsFit = geo.size.width >= 880
            HSplitView {
                if groupsVisible && groupsFit {
                    groupsColumn
                        .frame(minWidth: 150, idealWidth: 185, maxWidth: 260)
                }
                listColumn
                    .frame(minWidth: 250, idealWidth: 310, maxWidth: 420)
                detail()
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { groupsVisible.toggle() }
                } label: {
                    Label("Groups", systemImage: "sidebar.left")
                }
                .help(groupsVisible ? "Hide groups" : "Show groups")
            }
        }
    }

    // MARK: - Groups column

    private var groupsColumn: some View {
        VStack(spacing: 0) {
            List(selection: $selectedGroups) {
                ForEach(groupSections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            groupRow(group)
                                .tag(group.id)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let onCreateGroup {
                Divider()
                HStack {
                    Button {
                        onCreateGroup()
                    } label: {
                        Label("New Group", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .alert("Rename Group", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renamingGroup = nil }
            Button("Rename") {
                if let group = renamingGroup { onRenameGroup?(group, renameDraft) }
                renamingGroup = nil
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: DirectoryGroup) -> some View {
        HStack(spacing: 6) {
            Label {
                Text(group.title).lineLimit(1)
            } icon: {
                if let icon = group.icon {
                    Image(systemName: icon)
                }
            }
            Spacer(minLength: 2)
            Text("\(group.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contextMenu {
            if group.isEditableSmart {
                Button("Edit Rule…") { onEditSmartRule?(group) }
            }
            if group.isUserGroup {
                Button("Rename…") {
                    renameDraft = group.title
                    renamingGroup = group
                }
                Button("Delete", role: .destructive) { onDeleteGroup?(group) }
            }
        }
        .dropDestination(for: String.self) { strings, _ in
            guard group.isUserGroup, let onDropMembers else { return false }
            let ids = strings.compactMap(UUID.init(uuidString:))
            guard !ids.isEmpty else { return false }
            onDropMembers(group, ids)
            return true
        }
    }

    // MARK: - List column

    private struct ListSection: Identifiable {
        let id: String
        let items: [Item]
    }

    private var listSections: [ListSection] {
        var result: [ListSection] = []
        for item in items {
            let key = sectionKey(item)
            if result.last?.id == key {
                result[result.count - 1] = ListSection(id: key,
                                                       items: result[result.count - 1].items + [item])
            } else {
                result.append(ListSection(id: key, items: [item]))
            }
        }
        return result
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand {
                        searchText = ""
                        searchFocused = false
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 8) {
                listAccessory()
                Spacer()
                Text(countLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    List(selection: $selection) {
                        if items.isEmpty {
                            Text("No matches.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                        ForEach(listSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    row(item)
                                        .tag(item.id)
                                        .draggable(item.id.uuidString)
                                }
                            } header: {
                                Text(section.id)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .id("section-\(section.id)")
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    // Deep links select rows far from the current scroll
                    // position; the list follows the selection.
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }

                    if showsIndexRail {
                        indexRail(proxy: proxy)
                    }
                }
            }
        }
        .onChange(of: searchFocusToken) { _, _ in searchFocused = true }
    }

    /// The A–Z rail: letters with content are solid, empty letters faint;
    /// click or drag scrubs the list to that section.
    private func indexRail(proxy: ScrollViewProxy) -> some View {
        let present = Set(listSections.map(\.id))
        return VStack(spacing: 1) {
            ForEach(NameIndex.railSections, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(present.contains(letter) ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 14, height: 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if present.contains(letter) {
                            proxy.scrollTo("section-\(letter)", anchor: .top)
                        }
                    }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 2)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    // Scrub: map y to a rail letter, land on the nearest
                    // populated section at or after it.
                    let letters = NameIndex.railSections
                    let slot = Int((value.location.y - 4) / 13)
                    guard slot >= 0, slot < letters.count else { return }
                    let letter = letters[slot]
                    if present.contains(letter) {
                        proxy.scrollTo("section-\(letter)", anchor: .top)
                    }
                }
        )
    }
}
