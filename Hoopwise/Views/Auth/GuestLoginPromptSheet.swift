import SwiftUI

/// Sheet presented when guest user taps profile, prompting them to sign in
struct GuestLoginPromptSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var showingSignIn = false
    @State private var showingJoinOrg = false
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Hero illustration
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                    }
                    
                    Text(isChinese ? "加入您的组织" : "Join Your Organization")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(isChinese 
                         ? "登录后，您的数据将与组织同步，您可以与团队协作。"
                         : "Sign in to sync your data with your organization and collaborate with your team.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Benefits list
                VStack(alignment: .leading, spacing: 16) {
                    benefitRow(
                        icon: "cloud.fill",
                        title: isChinese ? "数据同步" : "Cloud Sync",
                        subtitle: isChinese ? "所有设备实时同步" : "Real-time sync across all devices"
                    )
                    
                    benefitRow(
                        icon: "person.3.fill",
                        title: isChinese ? "团队协作" : "Team Collaboration",
                        subtitle: isChinese ? "与其他教练共享数据" : "Share data with other coaches"
                    )
                    
                    benefitRow(
                        icon: "lock.shield.fill",
                        title: isChinese ? "数据安全" : "Data Security",
                        subtitle: isChinese ? "安全备份您的数据" : "Secure backup of your data"
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Sign In button
                    Button(action: { showingSignIn = true }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(isChinese ? "登录账号" : "Sign In")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(14)
                    }
                    
                    // Join Organization button
                    Button(action: { showingJoinOrg = true }) {
                        HStack {
                            Image(systemName: "building.2.fill")
                            Text(isChinese ? "加入组织" : "Join Organization")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(14)
                    }
                    
                    // Continue as guest
                    Button(action: { dismiss() }) {
                        Text(isChinese ? "继续体验模式" : "Continue as Guest")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(AppTheme.background))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }
            .sheet(isPresented: $showingSignIn) {
                SignInSheet()
            }
            .sheet(isPresented: $showingJoinOrg) {
                JoinOrganizationSheet()
            }
        }
    }
    
    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Sign In Sheet
struct SignInSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text(isChinese ? "登录" : "Sign In")
                        .font(.system(size: 24, weight: .bold))
                }
                .padding(.top, 32)
                
                // Form
                VStack(spacing: 16) {
                    // Username/Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "用户名或邮箱" : "Username or Email")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField(isChinese ? "输入用户名或邮箱" : "Enter username or email", text: $username)
                            .textContentType(.username)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .disableAutocorrection(true)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "密码" : "Password")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        SecureField(isChinese ? "输入密码" : "Enter password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Sign In button
                Button(action: signIn) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isChinese ? "登录" : "Sign In")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSignIn ? Color.orange : Color.gray)
                .cornerRadius(14)
                .disabled(!canSignIn || isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(AppTheme.background))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var canSignIn: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }
    
    private func signIn() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.signIn(email: username, password: password)
                await MainActor.run {
                    dismiss()
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

// MARK: - Join Organization Sheet
struct JoinOrganizationSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    
    @State private var secretCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text(isChinese ? "加入组织" : "Join Organization")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text(isChinese 
                         ? "输入组织管理员提供的邀请码"
                         : "Enter the invitation code provided by your organization admin")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 32)
                
                // Code input
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "组织邀请码" : "Organization Code")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("XXXXXXXX", text: $secretCode)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        #if os(iOS)
                        .autocapitalization(.allCharacters)
                        #endif
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .onChange(of: secretCode) { _, newValue in
                            // Limit to 8 characters and uppercase
                            secretCode = String(newValue.uppercased().prefix(8))
                        }
                }
                .padding(.horizontal, 24)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // Join button
                Button(action: joinOrganization) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isChinese ? "加入" : "Join")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(secretCode.count == 8 ? Color.orange : Color.gray)
                .cornerRadius(14)
                .disabled(secretCode.count != 8 || isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(AppTheme.background))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func joinOrganization() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.joinOrganization(secretCode: secretCode)
                await MainActor.run {
                    dismiss()
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

#Preview {
    GuestLoginPromptSheet()
}
