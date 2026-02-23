import Foundation
import SwiftUI
import Combine
import CommonCrypto

// MARK: - Authentication State
enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case authenticated(userId: UUID)
    case needsOrganization  // Authenticated but no org selected
    case onboarding(step: OnboardingStep)
}

enum OnboardingStep: Int, Equatable {
    case welcome = 0
    case signIn = 1
    case createAccount = 2
    case profileSetup = 3
    case organizationChoice = 4  // Create or Join
    case createOrganization = 5
    case joinOrganization = 6
    case complete = 7
}

// MARK: - User Account Model
struct UserAccount: Codable, Identifiable {
    let id: UUID
    var email: String
    var passwordHash: String  // SHA256 hash of password
    var name: String
    var chineseName: String?
    var profileImageUrl: String?
    var profileImageData: Data?
    var organizationId: UUID?
    var role: OrganizationRole
    var createdAt: Date
    var updatedAt: Date
    
    static let guest = UserAccount(
        id: UUID(),
        email: "",
        passwordHash: "",
        name: "Guest",
        chineseName: nil,
        profileImageUrl: nil,
        profileImageData: nil,
        organizationId: nil,
        role: .viewer,
        createdAt: Date(),
        updatedAt: Date()
    )
    
    // Hash password using SHA256
    static func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // Verify password against stored hash
    func verifyPassword(_ password: String) -> Bool {
        return passwordHash == UserAccount.hashPassword(password)
    }
}

// MARK: - Organization Model
struct Organization: Codable, Identifiable {
    let id: UUID
    var name: String
    var displayName: String
    var logoUrl: String?
    var secretCode: String  // 8-char code for joining
    var ownerId: UUID
    var createdAt: Date
    var updatedAt: Date
    
    // Generate a unique secret code
    static func generateSecretCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  // Excluding confusing chars (0, O, 1, I)
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

// MARK: - Organization Membership
struct OrganizationMember: Codable, Identifiable {
    let id: UUID
    var userId: UUID
    var organizationId: UUID
    var role: OrganizationRole
    var joinedAt: Date
    var invitedBy: UUID?
}

enum OrganizationRole: String, Codable, CaseIterable {
    case owner = "owner"
    case admin = "admin"
    case coach = "coach"
    case assistant = "assistant"
    case viewer = "viewer"
    
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Administrator"
        case .coach: return "Head Coach"
        case .assistant: return "Assistant Coach"
        case .viewer: return "Viewer"
        }
    }
    
    var localizedDisplayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .owner: return isChinese ? "所有者" : "Owner"
        case .admin: return isChinese ? "管理员" : "Administrator"
        case .coach: return isChinese ? "主教练" : "Head Coach"
        case .assistant: return isChinese ? "助理教练" : "Assistant Coach"
        case .viewer: return isChinese ? "查看者" : "Viewer"
        }
    }
    
    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .admin: return "gearshape.2.fill"
        case .coach: return "person.fill"
        case .assistant: return "person.2.fill"
        case .viewer: return "eye.fill"
        }
    }
    
    var color: String {
        switch self {
        case .owner: return "purple"
        case .admin: return "blue"
        case .coach: return "orange"
        case .assistant: return "green"
        case .viewer: return "gray"
        }
    }
    
    // MARK: - Organization Management
    var canManageOrganization: Bool {
        self == .owner || self == .admin
    }
    
    var canGenerateSecretCode: Bool {
        self == .owner || self == .admin
    }
    
    var canManageAccounts: Bool {
        self == .owner || self == .admin
    }
    
    // MARK: - Profile Permissions
    var canEditOwnProfile: Bool {
        true // Everyone can edit their own profile
    }
    
    var canEditOtherProfiles: Bool {
        self == .owner || self == .admin
    }
    
    // MARK: - Student Permissions
    var canCreateStudents: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    var canEditStudents: Bool {
        self != .viewer // All except viewer
    }
    
    var canDeleteStudents: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    // MARK: - Program Permissions
    var canCreatePrograms: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    var canEditPrograms: Bool {
        self != .viewer // All except viewer
    }
    
    var canDeletePrograms: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    // MARK: - Phase/MicroCycle Permissions
    var canCreatePhases: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    var canEditPhases: Bool {
        self != .viewer // All except viewer
    }
    
    var canDeletePhases: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    // MARK: - Session Permissions
    var canCreateSessions: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    var canEditSessions: Bool {
        self != .viewer // All except viewer
    }
    
    var canDeleteSessions: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    // MARK: - Schedule Permissions
    var canViewAllSchedules: Bool {
        true // Everyone can view all schedules
    }
    
    // MARK: - General Data Permissions
    var canEditData: Bool {
        self != .viewer
    }
    
    var canDeleteData: Bool {
        self == .owner || self == .admin || self == .coach
    }
    
    var isAdmin: Bool {
        self == .owner || self == .admin
    }
}

// MARK: - Auth Manager
class AuthManager: ObservableObject {
    @MainActor static let shared = AuthManager()
    
    // MARK: - Published State
    @Published var authState: AuthState = .unknown
    @Published var currentUser: UserAccount?
    @Published var currentOrganization: Organization?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Permission Helpers
    /// Current user's role (defaults to coach for demo/guest mode)
    var currentRole: OrganizationRole {
        currentUser?.role ?? .coach
    }
    
    /// Check if user can create students
    var canCreateStudents: Bool { currentRole.canCreateStudents }
    var canEditStudents: Bool { currentRole.canEditStudents }
    var canDeleteStudents: Bool { currentRole.canDeleteStudents }
    
    /// Check if user can manage programs
    var canCreatePrograms: Bool { currentRole.canCreatePrograms }
    var canEditPrograms: Bool { currentRole.canEditPrograms }
    var canDeletePrograms: Bool { currentRole.canDeletePrograms }
    
    /// Check if user can manage phases
    var canCreatePhases: Bool { currentRole.canCreatePhases }
    var canEditPhases: Bool { currentRole.canEditPhases }
    var canDeletePhases: Bool { currentRole.canDeletePhases }
    
    /// Check if user can manage sessions
    var canCreateSessions: Bool { currentRole.canCreateSessions }
    var canEditSessions: Bool { currentRole.canEditSessions }
    var canDeleteSessions: Bool { currentRole.canDeleteSessions }
    
    /// Check if user has admin privileges
    var isAdmin: Bool { currentRole.isAdmin }
    
    /// Check if user can edit any data
    var canEditData: Bool { currentRole.canEditData }
    
    // MARK: - UserDefaults Keys
    private let userIdKey = "auth_user_id"
    private let userDataKey = "auth_user_data"
    private let organizationIdKey = "auth_organization_id"
    private let organizationDataKey = "auth_organization_data"
    private let hasCompletedOnboardingKey = "auth_completed_onboarding"
    
    private init() {}
    
    // MARK: - Initialize Auth State
    func initialize() async {
        isLoading = true
        defer { isLoading = false }
        
        // Check for saved user session
        if let userData = UserDefaults.standard.data(forKey: userDataKey),
           let user = try? JSONDecoder().decode(UserAccount.self, from: userData) {
            currentUser = user
            
            // Check for organization
            if let orgData = UserDefaults.standard.data(forKey: organizationDataKey),
               let org = try? JSONDecoder().decode(Organization.self, from: orgData) {
                currentOrganization = org
                authState = .authenticated(userId: user.id)
                debugLog("✅ Restored auth session: \(user.name) @ \(org.name)")
            } else if user.organizationId != nil {
                // Has org ID but no cached org - need to fetch
                authState = .needsOrganization
            } else {
                authState = .needsOrganization
            }
        } else {
            // No saved session - go directly to guest/demo mode
            // Skip onboarding entirely for a seamless first experience
            authState = .unauthenticated
            
            // Mark as completed so we don't show onboarding later
            if !UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) {
                UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
                UserDefaults.standard.set(true, forKey: "hasSkippedLogin")
                debugLog("👤 First launch - entering demo mode directly")
            }
        }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String, name: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        // Validate inputs
        guard !email.isEmpty, email.contains("@") else {
            throw AuthError.invalidEmail
        }
        guard password.count >= 6 else {
            throw AuthError.weakPassword
        }
        guard !name.isEmpty else {
            throw AuthError.invalidName
        }
        
        // Create user account with hashed password
        let newUser = UserAccount(
            id: UUID(),
            email: email.lowercased().trimmingCharacters(in: .whitespaces),
            passwordHash: UserAccount.hashPassword(password),
            name: name.trimmingCharacters(in: .whitespaces),
            chineseName: nil,
            profileImageUrl: nil,
            profileImageData: nil,
            organizationId: nil,
            role: .coach,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to Supabase
        do {
            try await SupabaseManager.shared.insert(into: "user_accounts", data: SupabaseUserAccount(from: newUser))
            debugLog("✅ User account created in Supabase")
        } catch {
            debugLog("⚠️ Could not save to Supabase (offline mode): \(error)")
            // Continue anyway for offline support
        }
        
        // Save locally
        currentUser = newUser
        saveUserSession(newUser)
        
        authState = .onboarding(step: .profileSetup)
        debugLog("✅ Signed up: \(name)")
    }
    
    // MARK: - Sign In (Unified - uses organization_accounts only)
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard !email.isEmpty else {
            throw AuthError.invalidEmail
        }
        
        guard !password.isEmpty else {
            throw AuthError.invalidPassword
        }
        
        let loginIdentifier = email.lowercased().trimmingCharacters(in: .whitespaces)
        debugLog("🔐 Attempting sign in for: \(loginIdentifier)")
        
        // Unified login - check organization_accounts only
        // Try username first, then email
        var accounts: [SupabaseOrganizationAccount] = []
        
        // Try username match
        accounts = try await SupabaseManager.shared.fetchWithFilter(
            from: "organization_accounts",
            column: "username",
            op: .eq,
            value: loginIdentifier
        )
        
        // If no match, try email field
        if accounts.isEmpty {
            accounts = try await SupabaseManager.shared.fetchWithFilter(
                from: "organization_accounts",
                column: "email",
                op: .eq,
                value: loginIdentifier
            )
        }
        
        debugLog("🔐 Found \(accounts.count) account(s)")
        
        guard let account = accounts.first else {
            debugLog("🔐 No account found")
            throw AuthError.userNotFound
        }
        
        let orgAccount = account.toOrganizationAccount()
        
        // Check if account is active
        guard orgAccount.isActive else {
            debugLog("🔐 Account is deactivated")
            throw AuthError.userNotFound
        }
        
        // Verify password
        let inputHash = UserAccount.hashPassword(password)
        guard inputHash == orgAccount.passwordHash else {
            debugLog("🔐 Password verification failed")
            throw AuthError.invalidPassword
        }
        
        // Create a UserAccount from the organization account for session
        let user = UserAccount(
            id: orgAccount.id,
            email: orgAccount.email ?? "",
            passwordHash: orgAccount.passwordHash,
            name: orgAccount.name,
            chineseName: nil,
            profileImageUrl: nil,
            profileImageData: nil,
            organizationId: orgAccount.organizationId,
            role: orgAccount.role,
            createdAt: orgAccount.createdAt,
            updatedAt: orgAccount.createdAt
        )
        
        currentUser = user
        saveUserSession(user)
        
        // Fetch organization
        let orgs: [SupabaseOrganization] = try await SupabaseManager.shared.fetchWithFilter(
            from: "organizations",
            column: "id",
            op: .eq,
            value: orgAccount.organizationId.uuidString
        )
        
        if let org = orgs.first?.toOrganization() {
            currentOrganization = org
            saveOrganizationSession(org)
            authState = .authenticated(userId: user.id)
        } else {
            authState = .needsOrganization
        }
        
        debugLog("✅ Signed in: \(orgAccount.name)")
    }
    
    // MARK: - Password Reset
    /// Request a password reset - generates and stores a reset token.
    /// Returns a debug-only code for simulator/testing convenience.
    func requestPasswordReset(email: String) async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard !email.isEmpty, email.contains("@") else {
            throw AuthError.invalidEmail
        }
        
        // Fetch user from Supabase
        let users: [SupabaseUserAccount] = try await SupabaseManager.shared.fetchWithFilter(
            from: "user_accounts",
            column: "email",
            op: .eq,
            value: email.lowercased()
        )
        
        guard let supabaseUser = users.first else {
            throw AuthError.userNotFound
        }
        
        // Generate a 6-digit reset code
        let resetCode = String(format: "%06d", Int.random(in: 100000...999999))
        let resetToken = PasswordResetToken(
            id: UUID(),
            userId: supabaseUser.id,
            email: email.lowercased(),
            resetCode: resetCode,
            expiresAt: Date().addingTimeInterval(3600), // 1 hour expiry
            createdAt: Date()
        )
        
        // Save reset token to Supabase
        try await SupabaseManager.shared.insert(into: "password_reset_tokens", data: SupabasePasswordResetToken(from: resetToken))
        
        debugLog("✅ Password reset code generated")
        #if DEBUG
        return resetCode
        #else
        return ""
        #endif
    }
    
    /// Verify reset code and reset password
    func resetPassword(email: String, resetCode: String, newPassword: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard !email.isEmpty else {
            throw AuthError.invalidEmail
        }
        
        guard newPassword.count >= 6 else {
            throw AuthError.weakPassword
        }
        
        // Fetch valid reset tokens for this email
        let tokens: [SupabasePasswordResetToken] = try await SupabaseManager.shared.fetchWithFilter(
            from: "password_reset_tokens",
            column: "email",
            op: .eq,
            value: email.lowercased()
        )
        
        // Find matching, non-expired token
        guard let validToken = tokens.first(where: { token in
            token.resetCode == resetCode && token.expiresAt > Date()
        }) else {
            throw AuthError.invalidResetCode
        }
        
        // Fetch user
        let users: [SupabaseUserAccount] = try await SupabaseManager.shared.fetchWithFilter(
            from: "user_accounts",
            column: "id",
            op: .eq,
            value: validToken.userId.uuidString
        )
        
        guard let supabaseUser = users.first else {
            throw AuthError.userNotFound
        }
        
        // Update password
        var user = supabaseUser.toUserAccount()
        user.passwordHash = UserAccount.hashPassword(newPassword)
        user.updatedAt = Date()
        
        try await SupabaseManager.shared.upsert(into: "user_accounts", data: SupabaseUserAccount(from: user))
        
        // Delete used reset token
        try? await SupabaseManager.shared.delete(from: "password_reset_tokens", id: validToken.id)
        
        debugLog("✅ Password reset successful for: \(email)")
    }
    
    // MARK: - Update Profile
    func updateProfile(name: String, chineseName: String?, profileImageData: Data?) async {
        guard var user = currentUser else { return }
        
        user.name = name
        user.chineseName = chineseName
        user.profileImageData = profileImageData
        user.updatedAt = Date()
        
        currentUser = user
        saveUserSession(user)
        
        // Sync to cloud
        Task {
            try? await SupabaseManager.shared.upsert(into: "user_accounts", data: SupabaseUserAccount(from: user))
        }
        
        debugLog("✅ Profile updated")
    }
    
    // MARK: - Create Organization
    func createOrganization(name: String, displayName: String) async throws -> Organization {
        guard let user = currentUser else {
            throw AuthError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let org = Organization(
            id: UUID(),
            name: name.lowercased().replacingOccurrences(of: " ", with: "_"),
            displayName: displayName,
            logoUrl: nil,
            secretCode: Organization.generateSecretCode(),
            ownerId: user.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to Supabase
        do {
            try await SupabaseManager.shared.insert(into: "organizations", data: SupabaseOrganization(from: org))
            
            // Create membership
            let membership = OrganizationMember(
                id: UUID(),
                userId: user.id,
                organizationId: org.id,
                role: .owner,
                joinedAt: Date(),
                invitedBy: nil
            )
            try await SupabaseManager.shared.insert(into: "organization_members", data: SupabaseOrgMember(from: membership))
            
            // Update user with organization
            var updatedUser = user
            updatedUser.organizationId = org.id
            updatedUser.role = .owner
            updatedUser.updatedAt = Date()
            try await SupabaseManager.shared.upsert(into: "user_accounts", data: SupabaseUserAccount(from: updatedUser))
            
            currentUser = updatedUser
            saveUserSession(updatedUser)
            
            debugLog("✅ Organization created: \(org.displayName)")
        } catch {
            debugLog("⚠️ Could not save organization to Supabase: \(error)")
            // Continue for offline support
        }
        
        currentOrganization = org
        saveOrganizationSession(org)
        authState = .authenticated(userId: user.id)
        
        return org
    }
    
    // MARK: - Join Organization
    func joinOrganization(secretCode: String) async throws {
        guard let user = currentUser else {
            throw AuthError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Find organization by secret code
        let orgs: [SupabaseOrganization] = try await SupabaseManager.shared.fetchWithFilter(
            from: "organizations",
            column: "secret_code",
            op: .eq,
            value: secretCode.uppercased()
        )
        
        guard let supabaseOrg = orgs.first else {
            throw AuthError.invalidSecretCode
        }
        
        let org = supabaseOrg.toOrganization()
        
        // Create membership
        let membership = OrganizationMember(
            id: UUID(),
            userId: user.id,
            organizationId: org.id,
            role: .coach,  // Default role for new members
            joinedAt: Date(),
            invitedBy: org.ownerId
        )
        
        try await SupabaseManager.shared.insert(into: "organization_members", data: SupabaseOrgMember(from: membership))
        
        // Update user
        var updatedUser = user
        updatedUser.organizationId = org.id
        updatedUser.role = .coach
        updatedUser.updatedAt = Date()
        try await SupabaseManager.shared.upsert(into: "user_accounts", data: SupabaseUserAccount(from: updatedUser))
        
        currentUser = updatedUser
        saveUserSession(updatedUser)
        currentOrganization = org
        saveOrganizationSession(org)
        authState = .authenticated(userId: user.id)
        
        debugLog("✅ Joined organization: \(org.displayName)")
    }
    
    // MARK: - Generate New Secret Code
    func regenerateSecretCode() async throws -> String {
        guard let org = currentOrganization else {
            throw AuthError.noOrganization
        }
        guard currentUser?.role.canGenerateSecretCode == true else {
            throw AuthError.insufficientPermissions
        }
        
        var updatedOrg = org
        updatedOrg.secretCode = Organization.generateSecretCode()
        updatedOrg.updatedAt = Date()
        
        try await SupabaseManager.shared.upsert(into: "organizations", data: SupabaseOrganization(from: updatedOrg))
        
        currentOrganization = updatedOrg
        saveOrganizationSession(updatedOrg)
        
        debugLog("✅ New secret code generated: \(updatedOrg.secretCode)")
        return updatedOrg.secretCode
    }
    
    // MARK: - Sign Out
    func signOut() {
        currentUser = nil
        currentOrganization = nil
        
        // Clear all auth-related UserDefaults
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userDataKey)
        UserDefaults.standard.removeObject(forKey: organizationIdKey)
        UserDefaults.standard.removeObject(forKey: organizationDataKey)
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        
        // Clear legacy flags
        UserDefaults.standard.removeObject(forKey: "hasSkippedLogin")
        UserDefaults.standard.removeObject(forKey: "loggedInCoachId")
        
        authState = .unauthenticated
        debugLog("👋 Signed out - all session data cleared")
    }
    
    // MARK: - Guest Mode
    
    /// Check if user is in guest/demo mode (not authenticated)
    var isGuestMode: Bool {
        currentUser == nil || currentOrganization == nil
    }
    
    /// Skip to Guest Mode - loads app with sample data
    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        authState = .unauthenticated
        
        // Set legacy skip flag for backward compatibility
        UserDefaults.standard.set(true, forKey: "hasSkippedLogin")
        
        debugLog("👤 Continuing as guest with sample data")
    }
    
    /// Enter guest mode directly (for first-time users)
    func enterGuestMode() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.set(true, forKey: "hasSkippedLogin")
        authState = .unauthenticated
        debugLog("👤 Entered guest mode")
    }
    
    // MARK: - Complete Onboarding
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        if let user = currentUser {
            authState = .authenticated(userId: user.id)
        }
    }
    
    // MARK: - Navigation Helpers
    func proceedToStep(_ step: OnboardingStep) {
        authState = .onboarding(step: step)
    }
    
    // MARK: - Private Helpers
    private func saveUserSession(_ user: UserAccount) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDataKey)
            UserDefaults.standard.set(user.id.uuidString, forKey: userIdKey)
        }
    }
    
    private func saveOrganizationSession(_ org: Organization) {
        if let data = try? JSONEncoder().encode(org) {
            UserDefaults.standard.set(data, forKey: organizationDataKey)
            UserDefaults.standard.set(org.id.uuidString, forKey: organizationIdKey)
        }
    }
}

// MARK: - Password Reset Token Model
struct PasswordResetToken: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let email: String
    let resetCode: String
    let expiresAt: Date
    let createdAt: Date
}

// MARK: - Auth Errors
enum AuthError: Error, LocalizedError {
    case invalidEmail
    case invalidPassword
    case weakPassword
    case invalidName
    case userNotFound
    case notAuthenticated
    case invalidSecretCode
    case invalidResetCode
    case noOrganization
    case insufficientPermissions
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address"
        case .invalidPassword: return "Invalid password"
        case .weakPassword: return "Password must be at least 6 characters"
        case .invalidName: return "Please enter your name"
        case .userNotFound: return "No account found with this email"
        case .notAuthenticated: return "Please sign in first"
        case .invalidSecretCode: return "Invalid organization code"
        case .invalidResetCode: return "Invalid or expired reset code"
        case .noOrganization: return "No organization selected"
        case .insufficientPermissions: return "You don't have permission for this action"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supabase Models for Auth
// Note: SupabaseManager already uses .convertFromSnakeCase, so no CodingKeys needed
struct SupabaseUserAccount: Codable {
    let id: UUID
    let email: String
    let passwordHash: String?  // Optional for backward compatibility
    let name: String
    let chineseName: String?
    let profileImageUrl: String?
    let organizationId: UUID?
    let role: String
    let createdAt: Date
    let updatedAt: Date
    
    init(from user: UserAccount) {
        self.id = user.id
        self.email = user.email
        self.passwordHash = user.passwordHash
        self.name = user.name
        self.chineseName = user.chineseName
        self.profileImageUrl = user.profileImageUrl
        self.organizationId = user.organizationId
        self.role = user.role.rawValue
        self.createdAt = user.createdAt
        self.updatedAt = user.updatedAt
    }
    
    func toUserAccount() -> UserAccount {
        UserAccount(
            id: id,
            email: email,
            passwordHash: passwordHash ?? "",  // Default to empty if not set
            name: name,
            chineseName: chineseName,
            profileImageUrl: profileImageUrl,
            profileImageData: nil,
            organizationId: organizationId,
            role: OrganizationRole(rawValue: role) ?? .coach,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SupabaseOrganization: Codable {
    let id: UUID
    let name: String
    let displayName: String
    let logoUrl: String?
    let secretCode: String
    let ownerId: UUID
    let createdAt: Date
    let updatedAt: Date
    
    init(from org: Organization) {
        self.id = org.id
        self.name = org.name
        self.displayName = org.displayName
        self.logoUrl = org.logoUrl
        self.secretCode = org.secretCode
        self.ownerId = org.ownerId
        self.createdAt = org.createdAt
        self.updatedAt = org.updatedAt
    }
    
    func toOrganization() -> Organization {
        Organization(
            id: id,
            name: name,
            displayName: displayName,
            logoUrl: logoUrl,
            secretCode: secretCode,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SupabaseOrgMember: Codable {
    let id: UUID
    let userId: UUID
    let organizationId: UUID
    let role: String
    let joinedAt: Date
    let invitedBy: UUID?
    
    init(from member: OrganizationMember) {
        self.id = member.id
        self.userId = member.userId
        self.organizationId = member.organizationId
        self.role = member.role.rawValue
        self.joinedAt = member.joinedAt
        self.invitedBy = member.invitedBy
    }
}

struct SupabasePasswordResetToken: Codable {
    let id: UUID
    let userId: UUID
    let email: String
    let resetCode: String
    let expiresAt: Date
    let createdAt: Date
    
    init(from token: PasswordResetToken) {
        self.id = token.id
        self.userId = token.userId
        self.email = token.email
        self.resetCode = token.resetCode
        self.expiresAt = token.expiresAt
        self.createdAt = token.createdAt
    }
}
