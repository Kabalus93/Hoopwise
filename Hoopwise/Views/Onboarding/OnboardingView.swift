import SwiftUI

// MARK: - Main Onboarding Container
struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        ZStack {
            // Light theme background matching app design
            Color(hex: "#f5f5f7")
                .ignoresSafeArea()
            
            // Content based on current step
            switch authManager.authState {
            case .onboarding(let step):
                stepContent(for: step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .unauthenticated:
                WelcomeView()
            case .needsOrganization:
                OrganizationChoiceView()
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: authManager.authState)
    }
    
    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeView()
        case .signIn:
            SignInView()
        case .createAccount:
            CreateAccountView()
        case .profileSetup:
            ProfileSetupView()
        case .organizationChoice:
            OrganizationChoiceView()
        case .createOrganization:
            CreateOrganizationView()
        case .joinOrganization:
            JoinOrganizationView()
        case .complete:
            OnboardingCompleteView()
        }
    }
}

// MARK: - Premium Background
struct OnboardingBackground: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Deep dark gradient
            LinearGradient(
                colors: [
                    Color(hex: "#050508"),
                    Color(hex: "#0a0a12"),
                    Color(hex: "#08080f"),
                    Color(hex: "#050508")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating ambient orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#B8860B").opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: isAnimating ? -50 : -100, y: isAnimating ? -150 : -200)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: isAnimating ? 120 : 180, y: isAnimating ? 250 : 300)
            
            // Subtle grid
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, to: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, to: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.02), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Logo Section
            VStack(spacing: 24) {
                // App Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.orange.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.95)
                
                VStack(spacing: 8) {
                    Text("Hoopwise")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text("BASKETBALL TRAINING MANAGER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .tracking(2)
                }
                
                Text("Manage your athletes, programs,\nand sessions all in one place")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.bottom, 60)
            
            // Action Buttons
            VStack(spacing: 14) {
                // Create Account Button
                Button(action: {
                    HapticFeedback.impact(.medium)
                    withAnimation {
                        authManager.proceedToStep(.createAccount)
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Create Account")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .cornerRadius(14)
                    .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                
                // Sign In Button
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.signIn)
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .medium))
                        Text("Sign In")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                
                // Continue as Guest
                Button(action: {
                    HapticFeedback.impact(.light)
                    authManager.continueAsGuest()
                }) {
                    Text("Continue without account")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Footer
            Text("v1.0.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Sign In View
struct SignInView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPasswordReset = false
    @FocusState private var focusedField: SignInField?
    
    enum SignInField {
        case email, password
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.welcome)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Welcome Back")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("Sign in to your account")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)
                    
                    // Form Card
                    VStack(spacing: 0) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                TextField("Enter your email", text: $email)
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                    .textContentType(.emailAddress)
                                    .autocapitalizationCompat(.never)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .keyboardType(.emailAddress)
                                    #endif
                                    .focused($focusedField, equals: .email)
                            }
                            .padding(14)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .email ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .padding(16)
                        
                        Divider().padding(.horizontal, 16)
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                Group {
                                    if showPassword {
                                        TextField("Enter your password", text: $password)
                                    } else {
                                        SecureField("Enter your password", text: $password)
                                    }
                                }
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .password ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    
                    // Error Message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // Sign In Button
                    Button(action: performSignIn) {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(14)
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                    
                    // Forgot Password
                    Button(action: {
                        HapticFeedback.impact(.light)
                        showPasswordReset = true
                    }) {
                        Text("Forgot Password?")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    
                    // Switch to Create Account
                    Button(action: {
                        HapticFeedback.impact(.light)
                        withAnimation {
                            authManager.proceedToStep(.createAccount)
                        }
                    }) {
                        Text("Don't have an account? ")
                            .foregroundColor(.gray) +
                        Text("Create one")
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            OnboardingPasswordResetView()
                .environmentObject(authManager)
        }
    }
    
    private func performSignIn() {
        HapticFeedback.impact(.medium)
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Create Account View
struct CreateAccountView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var showPassword = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, password
    }
    
    private var isFormValid: Bool {
        !name.isEmpty && !email.isEmpty && password.count >= 6
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.welcome)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                }
                
                Spacer()
                
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == 0 ? Color.orange : Color.gray.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("Start managing your academy")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)
                    
                    // Form Card
                    VStack(spacing: 0) {
                        // Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Full Name")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "person")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                TextField("Enter your name", text: $name)
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                    .textContentType(.name)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .name)
                            }
                            .padding(14)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .name ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .padding(16)
                        
                        Divider().padding(.horizontal, 16)
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                TextField("Enter your email", text: $email)
                                    .font(.system(size: 16))
                                    .foregroundColor(.black)
                                    .textContentType(.emailAddress)
                                    .autocapitalizationCompat(.never)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .keyboardType(.emailAddress)
                                    #endif
                                    .focused($focusedField, equals: .email)
                            }
                            .padding(14)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .email ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .padding(16)
                        
                        Divider().padding(.horizontal, 16)
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                Group {
                                    if showPassword {
                                        TextField("Create a password", text: $password)
                                    } else {
                                        SecureField("Create a password", text: $password)
                                    }
                                }
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .password ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                            
                            Text("At least 6 characters")
                                .font(.system(size: 11))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    
                    // Error Message
                    if let error = authManager.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // Continue Button
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if authManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                            } else {
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(14)
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(authManager.isLoading || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)
                    
                    // Switch to Sign In
                    Button(action: {
                        HapticFeedback.impact(.light)
                        withAnimation {
                            authManager.proceedToStep(.signIn)
                        }
                    }) {
                        Text("Already have an account? ")
                            .foregroundColor(.gray) +
                        Text("Sign In")
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func submit() {
        focusedField = nil
        HapticFeedback.impact(.medium)
        
        Task {
            do {
                try await authManager.signUp(email: email, password: password, name: name)
            } catch {
                HapticFeedback.notification(.error)
                authManager.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Profile Setup View
struct ProfileSetupView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var name: String = ""
    @State private var chineseName: String = ""
    @State private var selectedImage: Data?
    @State private var showImagePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedback.impact(.light)
                    withAnimation {
                        authManager.proceedToStep(.createAccount)
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                }
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i <= 1 ? Color.orange : Color.gray.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Complete Your Profile")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("Add a photo and customize your name")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)
                    
                    // Profile Image
                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.1))
                                .frame(width: 120, height: 120)
                            
                            if let imageData = selectedImage,
                               let platformImg = platformImage(from: imageData) {
                                platformImageView(platformImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 116, height: 116)
                                    .clipShape(Circle())
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.orange)
                                    Text("Add Photo")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // Camera badge
                            Circle()
                                .fill(Color.white)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.orange)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                .offset(x: 40, y: 40)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Name Fields Card
                    VStack(spacing: 0) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            TextField("Your name", text: $name)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .padding(14)
                                .background(Color.gray.opacity(0.06))
                                .cornerRadius(12)
                        }
                        .padding(16)
                        
                        Divider().padding(.horizontal, 16)
                        
                        // Chinese Name (Optional)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("Chinese Name")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.gray)
                                Text("(Optional)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            
                            TextField("中文名", text: $chineseName)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .padding(14)
                                .background(Color.gray.opacity(0.06))
                                .cornerRadius(12)
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    
                    // Continue Button
                    Button(action: continueSetup) {
                        HStack(spacing: 10) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(14)
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    // Skip
                    Button(action: skipSetup) {
                        Text("Skip for now")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            name = authManager.currentUser?.name ?? ""
            chineseName = authManager.currentUser?.chineseName ?? ""
        }
    }
    
    private func continueSetup() {
        HapticFeedback.impact(.medium)
        Task {
            await authManager.updateProfile(
                name: name.isEmpty ? (authManager.currentUser?.name ?? "Coach") : name,
                chineseName: chineseName.isEmpty ? nil : chineseName,
                profileImageData: selectedImage
            )
            withAnimation {
                authManager.proceedToStep(.organizationChoice)
            }
        }
    }
    
    private func skipSetup() {
        HapticFeedback.impact(.light)
        withAnimation {
            authManager.proceedToStep(.organizationChoice)
        }
    }
    
    #if os(iOS)
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    
    private func platformImageView(_ image: UIImage) -> Image {
        Image(uiImage: image)
    }
    #else
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
    
    private func platformImageView(_ image: NSImage) -> Image {
        Image(nsImage: image)
    }
    #endif
}

// MARK: - Password Reset View (Onboarding)
struct OnboardingPasswordResetView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var currentStep: ResetStep = .requestCode
    @State private var generatedCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    enum ResetStep {
        case requestCode
        case enterCode
        case newPassword
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Reset Password")
                            .font(.title.bold())
                        
                        Text(stepDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    switch currentStep {
                    case .requestCode:
                        requestCodeView
                    case .enterCode:
                        enterCodeView
                    case .newPassword:
                        newPasswordView
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeadingCompat) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Password Reset Successful", isPresented: $showSuccess) {
                Button("Sign In") { dismiss() }
            } message: {
                Text("Your password has been reset. You can now sign in with your new password.")
            }
        }
    }
    
    private var stepDescription: String {
        switch currentStep {
        case .requestCode: return "Enter your email address to receive a reset code"
        case .enterCode: return "Enter the 6-digit code displayed below"
        case .newPassword: return "Create a new password for your account"
        }
    }
    
    private var requestCodeView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                TextField("your@email.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalizationCompat(.never)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    #endif
            }
            
            Button(action: requestCode) {
                if authManager.isLoading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Request Reset Code")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(email.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(email.isEmpty || authManager.isLoading)
        }
        .padding(.top, 20)
    }
    
    private var enterCodeView: some View {
        VStack(spacing: 20) {
            #if DEBUG
            if !generatedCode.isEmpty {
                VStack(spacing: 12) {
                    Text("Debug Reset Code:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(generatedCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.vertical)
            }
            #endif
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter Reset Code")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                TextField("000000", text: $resetCode)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
            }
            
            Button(action: verifyCode) {
                Text("Verify Code")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(resetCode.count == 6 ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(resetCode.count != 6)
            
            Button("Request New Code") {
                currentStep = .requestCode
                resetCode = ""
                generatedCode = ""
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
    }
    
    private var newPasswordView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Password")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                SecureField("Enter new password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                SecureField("Confirm new password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }
            
            if !newPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: newPassword.count >= 6 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(newPassword.count >= 6 ? .green : .red)
                    Text("At least 6 characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !confirmPassword.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: newPassword == confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(newPassword == confirmPassword ? .green : .red)
                    Text("Passwords match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button(action: resetPassword) {
                if authManager.isLoading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Reset Password")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canResetPassword ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(!canResetPassword || authManager.isLoading)
        }
        .padding(.top, 20)
    }
    
    private var canResetPassword: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }
    
    private func requestCode() {
        Task {
            do {
                generatedCode = try await authManager.requestPasswordReset(email: email)
                currentStep = .enterCode
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func verifyCode() {
        if resetCode.count == 6 {
            currentStep = .newPassword
        } else {
            errorMessage = "Invalid reset code. Please try again."
            showError = true
        }
    }
    
    private func resetPassword() {
        Task {
            do {
                try await authManager.resetPassword(email: email, resetCode: resetCode, newPassword: newPassword)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Placeholder Extension
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
