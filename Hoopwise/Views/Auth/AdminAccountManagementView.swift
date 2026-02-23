import SwiftUI

/// Admin view for creating and managing coach accounts within an organization
/// Admins can create accounts with username/password (no email required)
struct AdminAccountManagementView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var organizationAccounts: [OrganizationAccount] = []
    @State private var showingCreateAccount = false
    @State private var isLoading = false
    @State private var selectedAccount: OrganizationAccount?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            List {
                // Info section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "管理教练账号" : "Manage Coach Accounts")
                                .font(.system(size: 15, weight: .semibold))
                            Text(isChinese 
                                 ? "创建账号后，将用户名和密码分享给教练即可登录"
                                 : "Create accounts and share credentials with coaches to let them sign in")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Accounts list
                Section(header: Text(isChinese ? "教练账号" : "Coach Accounts")) {
                    if organizationAccounts.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray)
                                Text(isChinese ? "暂无账号" : "No accounts yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 24)
                            Spacer()
                        }
                    } else {
                        ForEach(organizationAccounts) { account in
                            AccountRow(account: account, onTap: {
                                selectedAccount = account
                            })
                        }
                        .onDelete(perform: deleteAccounts)
                    }
                }
                
                // Create new account button
                Section {
                    Button(action: { showingCreateAccount = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text(isChinese ? "创建新账号" : "Create New Account")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "账号管理" : "Account Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateAccount) {
                CreateCoachAccountSheet(onAccountCreated: { account in
                    organizationAccounts.append(account)
                })
            }
            .sheet(item: $selectedAccount) { account in
                AccountDetailSheet(account: account)
            }
            .onAppear {
                loadAccounts()
            }
        }
    }
    
    private func loadAccounts() {
        guard let orgId = authManager.currentOrganization?.id else { return }
        
        isLoading = true
        Task {
            do {
                let accounts: [SupabaseOrganizationAccount] = try await SupabaseManager.shared.fetchWithFilter(
                    from: "organization_accounts",
                    column: "organization_id",
                    op: .eq,
                    value: orgId.uuidString
                )
                await MainActor.run {
                    organizationAccounts = accounts.map { $0.toOrganizationAccount() }
                    isLoading = false
                }
            } catch {
                debugLog("⚠️ Failed to load accounts: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            let account = organizationAccounts[index]
            Task {
                do {
                    try await SupabaseManager.shared.delete(from: "organization_accounts", id: account.id)
                } catch {
                    debugLog("⚠️ Failed to delete account: \(error)")
                }
            }
        }
        organizationAccounts.remove(atOffsets: offsets)
    }
}

// MARK: - Account Row
struct AccountRow: View {
    let account: OrganizationAccount
    let onTap: () -> Void
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(account.name.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(roleColor)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text("@\(account.username)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(account.role.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(roleColor)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var roleColor: Color {
        switch account.role {
        case .owner: return .purple
        case .admin: return .blue
        case .coach: return .orange
        case .assistant: return .green
        case .viewer: return .gray
        }
    }
}

// MARK: - Create Coach Account Sheet
struct CreateCoachAccountSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    
    let onAccountCreated: (OrganizationAccount) -> Void
    
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: OrganizationRole = .coach
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var createdAccount: OrganizationAccount?
    @State private var showingCredentials = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            if showingCredentials, let account = createdAccount {
                // Show credentials to share
                CredentialsShareView(
                    account: account,
                    password: password,
                    onDone: {
                        onAccountCreated(account)
                        dismiss()
                    }
                )
            } else {
                Form {
                    // Name section
                    Section(header: Text(isChinese ? "基本信息" : "Basic Info")) {
                        TextField(isChinese ? "姓名" : "Full Name", text: $name)
                            .textContentType(.name)
                        
                        TextField(isChinese ? "用户名" : "Username", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { _, newValue in
                                // Only allow alphanumeric and underscore
                                username = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            }
                    }
                    
                    // Password section
                    Section(header: Text(isChinese ? "密码" : "Password")) {
                        SecureField(isChinese ? "密码 (至少6位)" : "Password (min 6 chars)", text: $password)
                            .textContentType(.newPassword)
                        
                        SecureField(isChinese ? "确认密码" : "Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                        
                        if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                            Text(isChinese ? "密码不匹配" : "Passwords don't match")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Role section
                    Section(header: Text(isChinese ? "角色" : "Role")) {
                        Picker(isChinese ? "角色" : "Role", selection: $selectedRole) {
                            ForEach([OrganizationRole.coach, .assistant, .viewer], id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(roleDescription)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle(isChinese ? "创建账号" : "Create Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isChinese ? "取消" : "Cancel") { dismiss() }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: createAccount) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(isChinese ? "创建" : "Create")
                            }
                        }
                        .disabled(!canCreate || isLoading)
                    }
                }
            }
        }
    }
    
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.count >= 3 &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    private var roleDescription: String {
        switch selectedRole {
        case .coach:
            return isChinese ? "可以管理学员、课程和比赛" : "Can manage students, sessions, and games"
        case .assistant:
            return isChinese ? "可以查看和记录出勤、比分" : "Can view and record attendance, scores"
        case .viewer:
            return isChinese ? "只能查看数据，不能编辑" : "Can only view data, no editing"
        default:
            return ""
        }
    }
    
    private func createAccount() {
        guard let orgId = authManager.currentOrganization?.id else {
            errorMessage = isChinese ? "请先加入组织" : "Please join an organization first"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Note: createdBy is set to nil because the FK constraint references user_accounts,
        // but organization admins are in organization_accounts, not user_accounts
        let newAccount = OrganizationAccount(
            id: UUID(),
            organizationId: orgId,
            username: username.lowercased(),
            email: nil,
            passwordHash: UserAccount.hashPassword(password),
            name: name.trimmingCharacters(in: .whitespaces),
            role: selectedRole,
            isActive: true,
            createdAt: Date(),
            createdBy: nil
        )
        
        Task {
            do {
                try await SupabaseManager.shared.insert(
                    into: "organization_accounts",
                    data: SupabaseOrganizationAccount(from: newAccount)
                )
                
                await MainActor.run {
                    createdAccount = newAccount
                    showingCredentials = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Credentials Share View
struct CredentialsShareView: View {
    let account: OrganizationAccount
    let password: String
    let onDone: () -> Void
    
    @State private var copied = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        VStack(spacing: 24) {
            // Success header
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text(isChinese ? "账号创建成功!" : "Account Created!")
                    .font(.system(size: 24, weight: .bold))
                
                Text(isChinese 
                     ? "请将以下登录信息分享给 \(account.name)"
                     : "Share these login credentials with \(account.name)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            // Credentials card
            VStack(spacing: 16) {
                credentialRow(label: isChinese ? "用户名" : "Username", value: account.username)
                
                Divider()
                
                credentialRow(label: isChinese ? "密码" : "Password", value: password)
            }
            .padding(20)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            
            // Copy button
            Button(action: copyCredentials) {
                HStack {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? (isChinese ? "已复制" : "Copied!") : (isChinese ? "复制登录信息" : "Copy Credentials"))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Done button
            Button(action: onDone) {
                Text(isChinese ? "完成" : "Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 32)
        }
    }
    
    private func credentialRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
    
    private func copyCredentials() {
        let text = """
        \(isChinese ? "用户名" : "Username"): \(account.username)
        \(isChinese ? "密码" : "Password"): \(password)
        """
        UIPasteboard.general.string = text
        
        withAnimation {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}

// MARK: - Account Detail Sheet
struct AccountDetailSheet: View {
    let account: OrganizationAccount
    @Environment(\.dismiss) var dismiss
    
    @State private var showingResetPassword = false
    @State private var newPassword = ""
    @State private var isResetting = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            List {
                // Account info
                Section(header: Text(isChinese ? "账号信息" : "Account Info")) {
                    LabeledContent(isChinese ? "姓名" : "Name", value: account.name)
                    LabeledContent(isChinese ? "用户名" : "Username", value: "@\(account.username)")
                    LabeledContent(isChinese ? "角色" : "Role", value: account.role.displayName)
                    LabeledContent(isChinese ? "状态" : "Status", value: account.isActive ? (isChinese ? "活跃" : "Active") : (isChinese ? "已禁用" : "Disabled"))
                    LabeledContent(isChinese ? "创建时间" : "Created", value: account.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                
                // Actions
                Section {
                    Button(action: { showingResetPassword = true }) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                            Text(isChinese ? "重置密码" : "Reset Password")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .alert(isChinese ? "重置密码" : "Reset Password", isPresented: $showingResetPassword) {
                SecureField(isChinese ? "新密码" : "New Password", text: $newPassword)
                Button(isChinese ? "取消" : "Cancel", role: .cancel) { newPassword = "" }
                Button(isChinese ? "重置" : "Reset") {
                    resetPassword()
                }
                .disabled(newPassword.count < 6)
            } message: {
                Text(isChinese ? "输入新密码 (至少6位)" : "Enter new password (min 6 characters)")
            }
        }
    }
    
    private func resetPassword() {
        guard newPassword.count >= 6 else { return }
        
        isResetting = true
        let newHash = UserAccount.hashPassword(newPassword)
        
        // Create updated account with new password hash
        var updatedAccount = account
        updatedAccount.passwordHash = newHash
        
        Task {
            do {
                try await SupabaseManager.shared.upsert(
                    into: "organization_accounts",
                    data: SupabaseOrganizationAccount(from: updatedAccount)
                )
                
                await MainActor.run {
                    newPassword = ""
                    isResetting = false
                }
            } catch {
                debugLog("⚠️ Failed to reset password: \(error)")
                await MainActor.run {
                    isResetting = false
                }
            }
        }
    }
}

// MARK: - Organization Account Model (Unified - used for all logins)
struct OrganizationAccount: Identifiable, Codable {
    let id: UUID
    let organizationId: UUID
    var username: String
    var email: String?  // Optional email for login/recovery
    var passwordHash: String
    var name: String
    var role: OrganizationRole
    var isActive: Bool
    var createdAt: Date
    var createdBy: UUID?
}

// MARK: - Supabase Model
struct SupabaseOrganizationAccount: Codable {
    let id: UUID
    let organizationId: UUID
    let username: String
    let email: String?
    let passwordHash: String
    let name: String
    let role: String
    let isActive: Bool
    let createdAt: Date
    let createdBy: UUID?
    
    init(from account: OrganizationAccount) {
        self.id = account.id
        self.organizationId = account.organizationId
        self.username = account.username
        self.email = account.email
        self.passwordHash = account.passwordHash
        self.name = account.name
        self.role = account.role.rawValue
        self.isActive = account.isActive
        self.createdAt = account.createdAt
        self.createdBy = account.createdBy
    }
    
    func toOrganizationAccount() -> OrganizationAccount {
        OrganizationAccount(
            id: id,
            organizationId: organizationId,
            username: username,
            email: email,
            passwordHash: passwordHash,
            name: name,
            role: OrganizationRole(rawValue: role) ?? .viewer,
            isActive: isActive,
            createdAt: createdAt,
            createdBy: createdBy
        )
    }
}

#Preview {
    AdminAccountManagementView()
}
