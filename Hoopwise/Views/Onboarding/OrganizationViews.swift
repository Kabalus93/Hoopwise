import SwiftUI

// MARK: - Organization Choice View
struct OrganizationChoiceView: View {
    @StateObject private var authManager = AuthManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.profileSetup)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i <= 2 ? Color(hex: "#B8860B") : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Title
                    VStack(spacing: 12) {
                        Text("Your Organization")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Create a new organization or join an existing one")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Organization Cards
                    VStack(spacing: 16) {
                        // Create Organization Card
                        OrganizationOptionCard(
                            icon: "building.2.fill",
                            title: "Create Organization",
                            subtitle: "Start fresh with your own academy data",
                            accentColor: Color(hex: "#B8860B")
                        ) {
                            HapticFeedback.impact(.medium)
                            withAnimation {
                                authManager.proceedToStep(.createOrganization)
                            }
                        }
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                            Text("OR")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 16)
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 8)
                        
                        // Join Organization Card
                        OrganizationOptionCard(
                            icon: "person.3.fill",
                            title: "Join Organization",
                            subtitle: "Enter a code to access existing data",
                            accentColor: Color.purple
                        ) {
                            HapticFeedback.impact(.medium)
                            withAnimation {
                                authManager.proceedToStep(.joinOrganization)
                            }
                        }
                    }
                    
                    // Info Box
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "#B8860B"))
                            Text("What's an Organization?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Organizations keep your data separate and secure. Create one if you're starting a new academy, or join one if you're part of an existing team.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#B8860B").opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Organization Option Card
struct OrganizationOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isPressed ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isPressed ? accentColor.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Create Organization View
struct CreateOrganizationView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var organizationName = ""
    @State private var displayName = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, displayName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.organizationChoice)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i <= 3 ? Color(hex: "#B8860B") : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#B8860B").opacity(0.2), Color(hex: "#FFD700").opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)
                    
                    // Title
                    VStack(spacing: 12) {
                        Text("Create Organization")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Set up your academy's workspace")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // Form
                    VStack(spacing: 16) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Organization Name")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .textCase(.uppercase)
                            
                            TextField("", text: $displayName)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedField == .displayName ? Color(hex: "#B8860B") : Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .focused($focusedField, equals: .displayName)
                                .placeholder(when: displayName.isEmpty) {
                                    Text("e.g., Elite Basketball Academy")
                                        .foregroundColor(.white.opacity(0.3))
                                        .padding(.leading, 16)
                                }
                                .onChange(of: displayName) { newValue in
                                    // Auto-generate slug from display name
                                    organizationName = newValue.lowercased()
                                        .replacingOccurrences(of: " ", with: "_")
                                        .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                }
                        }
                        
                        // Slug Preview
                        if !organizationName.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.4))
                                Text("Identifier: \(organizationName)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What you'll get:")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        
                        ForEach([
                            ("checkmark.circle.fill", "Dedicated data storage"),
                            ("person.3.fill", "Invite coaches with a secret code"),
                            ("lock.shield.fill", "Secure & private student data"),
                            ("icloud.fill", "Cloud sync across all devices")
                        ], id: \.0) { icon, text in
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#B8860B"))
                                Text(text)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    
                    // Error Message
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Create Button
                    Button(action: createOrganization) {
                        HStack(spacing: 10) {
                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.black)
                                    .controlSize(.small)
                            } else {
                                Text("Create Organization")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: displayName.isEmpty ? [Color.gray.opacity(0.3)] : [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: displayName.isEmpty ? .clear : Color(hex: "#B8860B").opacity(0.4), radius: 12, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(displayName.isEmpty || authManager.isLoading)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func createOrganization() {
        focusedField = nil
        HapticFeedback.impact(.medium)
        
        Task {
            do {
                _ = try await authManager.createOrganization(
                    name: organizationName,
                    displayName: displayName
                )
                HapticFeedback.notification(.success)
                withAnimation {
                    authManager.proceedToStep(.complete)
                }
            } catch {
                HapticFeedback.notification(.error)
                authManager.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Join Organization View
struct JoinOrganizationView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var secretCode = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.organizationChoice)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i <= 3 ? Color.purple : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.purple, Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)
                    
                    // Title
                    VStack(spacing: 12) {
                        Text("Join Organization")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Enter the code from your admin")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    
                    // Code Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Organization Code")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                        
                        TextField("", text: $secretCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .textContentType(.oneTimeCode)
                            .autocorrectionDisabled()
                            .padding(20)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isFocused ? Color.purple : Color.white.opacity(0.1),
                                        lineWidth: isFocused ? 2 : 1
                                    )
                            )
                            .focused($isFocused)
                            .onChange(of: secretCode) { newValue in
                                // Limit to 12 characters and uppercase
                                secretCode = String(newValue.uppercased().prefix(12))
                            }
                            .placeholder(when: secretCode.isEmpty) {
                                Text("XXXXXXXX")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                    }
                    
                    // Character count
                    HStack {
                        Spacer()
                        Text("\(secretCode.count) characters")
                            .font(.system(size: 12))
                            .foregroundColor(secretCode.count >= 6 ? Color.green : .white.opacity(0.4))
                    }
                    
                    // Info
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.purple.opacity(0.8))
                        
                        Text("Ask your organization admin for the secret code. They can generate one in Settings → Organization → Generate Code.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(12)
                    
                    // Error Message
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Join Button
                    Button(action: joinOrganization) {
                        HStack(spacing: 10) {
                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.black)
                                    .controlSize(.small)
                            } else {
                                Text("Join Organization")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: secretCode.count >= 6 ? [Color.purple, Color.purple.opacity(0.8)] : [Color.gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: secretCode.count >= 6 ? Color.purple.opacity(0.4) : .clear, radius: 12, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(secretCode.count < 6 || authManager.isLoading)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func joinOrganization() {
        isFocused = false
        HapticFeedback.impact(.medium)
        
        Task {
            do {
                try await authManager.joinOrganization(secretCode: secretCode)
                HapticFeedback.notification(.success)
                withAnimation {
                    authManager.proceedToStep(.complete)
                }
            } catch {
                HapticFeedback.notification(.error)
                authManager.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Onboarding Complete View
struct OnboardingCompleteView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var showCheckmark = false
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Success Animation
            ZStack {
                // Glow
                Circle()
                    .fill(Color(hex: "#B8860B").opacity(0.2))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .scaleEffect(showCheckmark ? 1.2 : 0.8)
                
                // Circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)
                    .opacity(showCheckmark ? 1.0 : 0.0)
                
                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.black)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)
                    .opacity(showCheckmark ? 1.0 : 0.0)
            }
            
            // Content
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                if let org = authManager.currentOrganization {
                    Text("Welcome to \(org.displayName)")
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Text("Start managing your academy with Hoopwise")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
            }
            .opacity(showContent ? 1.0 : 0.0)
            .offset(y: showContent ? 0 : 20)
            
            Spacer()
            
            // Get Started Button
            Button(action: {
                HapticFeedback.impact(.medium)
                authManager.completeOnboarding()
            }) {
                HStack(spacing: 10) {
                    Text("Get Started")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color(hex: "#B8860B").opacity(0.4), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .opacity(showContent ? 1.0 : 0.0)
            .offset(y: showContent ? 0 : 20)
            
            Spacer()
                .frame(height: 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                showCheckmark = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showContent = true
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(DataManager.shared)
}
