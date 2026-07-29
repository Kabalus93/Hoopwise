import SwiftUI

// MARK: - Schools List Section
/// Section embedded in `OrganizationView` for managing the partner-school
/// roster used by `.school` programs. Mirrors `LocationsListSection` but
/// without map chrome — schools are usually identified by name + contact.
struct SchoolsListSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddSchool = false
    @State private var editingSchool: School?
    @State private var searchText = ""

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var filteredSchools: [School] {
        let all = dataManager.schools.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        if searchText.isEmpty { return all }
        return all.filter { school in
            school.name.localizedCaseInsensitiveContains(searchText)
                || (school.chineseName ?? "").localizedCaseInsensitiveContains(searchText)
                || (school.contactName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                PanelSearchBar(
                    text: $searchText,
                    placeholder: isChinese ? "搜索学校..." : "Search schools..."
                )
                .padding(.horizontal, 16)

                Button {
                    showingAddSchool = true
                } label: {
                    Label(isChinese ? "添加学校" : "Add School", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.regular)
                .tint(SessionFormat.school.tint)
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: showingAddSchool)

                if filteredSchools.isEmpty {
                    PanelEmptyState(
                        icon: "building.columns",
                        title: searchText.isEmpty
                            ? (isChinese ? "暂无学校" : "No Schools Yet")
                            : (isChinese ? "无结果" : "No Results"),
                        subtitle: searchText.isEmpty
                            ? (isChinese ? "添加合作学校" : "Add partner schools for school-collab programs")
                            : (isChinese ? "试试其他搜索" : "Try a different search")
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredSchools) { school in
                            SchoolRow(school: school)
                                .onTapGesture { editingSchool = school }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 100)
            }
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showingAddSchool) {
            AddEditSchoolView(school: nil)
        }
        .sheet(item: $editingSchool) { school in
            AddEditSchoolView(school: school)
        }
    }
}

// MARK: - School Row (compact)
struct SchoolRow: View {
    let school: School
    @EnvironmentObject var dataManager: DataManager

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var programCount: Int {
        dataManager.programs.filter { $0.schoolId == school.id }.count
    }

    private var studentCount: Int {
        let ids = Set(
            dataManager.programs
                .filter { $0.schoolId == school.id }
                .flatMap { $0.enrolledStudentIds }
        )
        return ids.count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(SessionFormat.school.tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SessionFormat.school.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(school.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !school.isActive {
                        Text(isChinese ? "停用" : "Inactive")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.7), in: .capsule)
                    }
                }
                let parts = [
                    programCount == 0
                        ? (isChinese ? "无课程" : "No programs")
                        : "\(programCount) \(isChinese ? "课程" : (programCount == 1 ? "program" : "programs"))",
                    studentCount > 0
                        ? "\(studentCount) \(isChinese ? "学员" : (studentCount == 1 ? "athlete" : "athletes"))"
                        : nil,
                    school.contactName
                ].compactMap { $0 }
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

// MARK: - Add / Edit School
struct AddEditSchoolView: View {
    let school: School?
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var chineseName: String = ""
    @State private var contactName: String = ""
    @State private var contactPhone: String = ""
    @State private var contactEmail: String = ""
    @State private var address: String = ""
    @State private var notes: String = ""
    @State private var isActive: Bool = true
    @State private var showingDeleteConfirmation = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var isEditing: Bool { school != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isChinese ? "学校" : "School") {
                    TextField(isChinese ? "学校名称" : "School name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(isChinese ? "中文名称（选填）" : "Chinese name (optional)", text: $chineseName)
                }

                Section(isChinese ? "联系人" : "Contact") {
                    TextField(isChinese ? "联系人姓名" : "Contact name", text: $contactName)
                        .textInputAutocapitalization(.words)
                    TextField(isChinese ? "电话" : "Phone", text: $contactPhone)
                        .keyboardType(.phonePad)
                    TextField(isChinese ? "电子邮箱" : "Email", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(isChinese ? "地址与备注" : "Address & Notes") {
                    TextField(isChinese ? "地址" : "Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(isChinese ? "备注" : "Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    Toggle(isChinese ? "启用" : "Active", isOn: $isActive)
                } footer: {
                    Text(isChinese
                         ? "停用的学校不会出现在新课程的选择列表中。"
                         : "Inactive schools are hidden from the school picker on new programs.")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text(isChinese ? "删除学校" : "Delete School")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing
                             ? (isChinese ? "编辑学校" : "Edit School")
                             : (isChinese ? "添加学校" : "Add School"))
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert(isChinese ? "删除学校？" : "Delete school?",
                   isPresented: $showingDeleteConfirmation) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) { }
                Button(isChinese ? "删除" : "Delete", role: .destructive) { delete() }
            } message: {
                Text(isChinese
                     ? "关联的课程将变为普通团课，不会被删除。"
                     : "Programs linked to this school will be converted to regular group programs. They won't be deleted.")
            }
            .onAppear {
                guard let school else { return }
                name = school.name
                chineseName = school.chineseName ?? ""
                contactName = school.contactName ?? ""
                contactPhone = school.contactPhone ?? ""
                contactEmail = school.contactEmail ?? ""
                address = school.address ?? ""
                notes = school.notes ?? ""
                isActive = school.isActive
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let updated = School(
            id: school?.id ?? UUID(),
            name: trimmedName,
            chineseName: chineseName.trimmingNonEmpty,
            contactName: contactName.trimmingNonEmpty,
            contactPhone: contactPhone.trimmingNonEmpty,
            contactEmail: contactEmail.trimmingNonEmpty,
            address: address.trimmingNonEmpty,
            notes: notes.trimmingNonEmpty,
            isActive: isActive,
            createdAt: school?.createdAt ?? Date(),
            updatedAt: Date()
        )
        if isEditing {
            dataManager.updateSchool(updated)
        } else {
            dataManager.addSchool(updated)
        }
        dismiss()
    }

    private func delete() {
        guard let school else { return }
        dataManager.deleteSchool(school)
        dismiss()
    }
}

private extension String {
    /// Returns nil when the string trims to empty — saves a bit of guard
    /// boilerplate when persisting optional fields.
    var trimmingNonEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
