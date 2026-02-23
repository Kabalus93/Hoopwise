import SwiftUI

// MARK: - Premium Login Splash Screen
/// American Express-inspired premium login experience
struct LoginSplashView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var searchText = ""
    @State private var isAnimating = false
    @State private var selectedCoach: StaffCoach? = nil
    @State private var showingCoachList = false
    
    // Cached filtered coaches for performance
    private var filteredCoaches: [StaffCoach] {
        let activeCoaches = dataManager.staffCoaches.filter { $0.isActive }
        if searchText.isEmpty {
            return activeCoaches
        }
        return activeCoaches.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Premium ambient background
                premiumBackground
                
                #if os(macOS)
                macOSLayout(geometry: geometry)
                #else
                iOSLayout(geometry: geometry)
                #endif
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Premium Background
    private var premiumBackground: some View {
        ZStack {
            // Deep dark gradient base
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
                        colors: [Color(hex: "#B8860B").opacity(0.25), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: isAnimating ? -50 : -100, y: isAnimating ? -150 : -200)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: isAnimating)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#DAA520").opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: isAnimating ? 120 : 180, y: isAnimating ? 250 : 300)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: isAnimating)
            
            // Subtle grid pattern overlay
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
    }
    
    // MARK: - iOS Layout
    @ViewBuilder
    private func iOSLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Premium Logo Section
            VStack(spacing: 24) {
                // Golden star cluster
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(isAnimating ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.5).delay(Double(i) * 0.1), value: isAnimating)
                    }
                }
                
                // SAM Logo with premium glow
                ZStack {
                    // Glow effect
                    HoopwiseLogoView(size: 100, showBackground: true, animated: isAnimating)
                        .blur(radius: 30)
                        .opacity(0.5)
                    
                    HoopwiseLogoView(size: 100, showBackground: true, animated: isAnimating)
                }
                .shadow(color: Color(hex: "#B8860B").opacity(0.4), radius: 30, x: 0, y: 10)
                
                VStack(spacing: 8) {
                    Text("Hoopwise")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("BASKETBALL TRAINING MANAGER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#B8860B"))
                        .tracking(3)
                }
            }
            .padding(.bottom, 50)
            
            // Login Card
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("WELCOME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#DAA520"))
                        .tracking(4)
                    
                    Text("Select Your Profile")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                if dataManager.staffCoaches.isEmpty {
                    emptyCoachesView
                } else {
                    coachSelectionView
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.05))
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#B8860B").opacity(0.3), Color.white.opacity(0.1), Color(hex: "#B8860B").opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Footer
            premiumFooter
        }
    }
    
    // MARK: - macOS Layout
    @ViewBuilder
    private func macOSLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left side - Branding
            VStack {
                Spacer()
                
                VStack(spacing: 32) {
                    // Golden stars
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { i in
                            Image(systemName: "star.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .opacity(isAnimating ? 1.0 : 0.6)
                                .animation(.easeInOut(duration: 0.5).delay(Double(i) * 0.15), value: isAnimating)
                        }
                    }
                    
                    // Logo
                    ZStack {
                        HoopwiseLogoView(size: 140, showBackground: true, animated: isAnimating)
                            .blur(radius: 40)
                            .opacity(0.4)
                        
                        HoopwiseLogoView(size: 140, showBackground: true, animated: isAnimating)
                    }
                    .shadow(color: Color(hex: "#B8860B").opacity(0.5), radius: 40, x: 0, y: 15)
                    
                    VStack(spacing: 12) {
                        Text("Hoopwise")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Text("BASKETBALL TRAINING MANAGER")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#B8860B"))
                            .tracking(4)
                    }
                    
                    // Tagline
                    Text("Professional coaching\nmanagement platform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                premiumFooter
            }
            .frame(width: geometry.size.width * 0.45)
            
            // Right side - Login
            VStack {
                Spacer()
                
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Text("WELCOME BACK")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#DAA520"))
                            .tracking(4)
                        
                        Text("Select Your Profile")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    if dataManager.staffCoaches.isEmpty {
                        emptyCoachesView
                    } else {
                        // Search
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.4))
                            
                            TextField("Search coaches...", text: $searchText)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                                .textFieldStyle(.plain)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        
                        // Coach grid
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(filteredCoaches) { coach in
                                    PremiumCoachCard(coach: coach) {
                                        loginAs(coach)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                        
                        // Guest option
                        Button(action: { continueAsGuest() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle")
                                Text("Continue as Guest")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(40)
                .frame(maxWidth: 480)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.04))
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(.ultraThinMaterial)
                                .opacity(0.2)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#B8860B").opacity(0.2), Color.white.opacity(0.08), Color(hex: "#B8860B").opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                
                Spacer()
            }
            .frame(width: geometry.size.width * 0.55)
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Coach Selection View
    private var coachSelectionView: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("Search coaches...", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .autocapitalizationCompat(.never)
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Coach list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCoaches) { coach in
                        PremiumCoachCard(coach: coach) {
                            loginAs(coach)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            
            // Continue as guest
            Button(action: { continueAsGuest() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle")
                    Text("Continue as Guest")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Empty Coaches View
    private var emptyCoachesView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "person.2.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.3))
            }
            
            VStack(spacing: 8) {
                Text("No Coaches Available")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Add coaches in Hub → Organization\nto enable login")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { continueAsGuest() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Continue as Guest")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
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
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Premium Footer
    private var premiumFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 6))
                        .foregroundColor(Color(hex: "#B8860B").opacity(0.5))
                }
            }
            
            Text("v1.0.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.bottom, 32)
    }
    
    // MARK: - Actions
    private func loginAs(_ coach: StaffCoach) {
        HapticFeedback.notification(.success)
        withAnimation(.easeInOut(duration: 0.3)) {
            dataManager.login(as: coach)
        }
    }
    
    private func continueAsGuest() {
        HapticFeedback.impact(.light)
        withAnimation(.easeInOut(duration: 0.3)) {
            dataManager.skipLogin()
        }
    }
}

// MARK: - Premium Coach Card (American Express Style)
struct PremiumCoachCard: View {
    let coach: StaffCoach
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Premium Avatar with golden ring
                ZStack {
                    // Golden ring (on hover/press)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#FFD700"), Color(hex: "#B8860B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isHovered || isPressed ? 2 : 0
                        )
                        .frame(width: 54, height: 54)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.avatarColor(coach.avatarColor), Color.avatarColor(coach.avatarColor).opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Text(coach.initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(coach.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 5) {
                        // Role badge
                        HStack(spacing: 4) {
                            Image(systemName: coach.role.icon)
                                .font(.system(size: 9))
                            Text(coach.role.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(coach.role.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(coach.role.color.opacity(0.15))
                        .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Premium arrow with glow
                ZStack {
                    if isHovered || isPressed {
                        Circle()
                            .fill(Color(hex: "#B8860B").opacity(0.3))
                            .frame(width: 32, height: 32)
                            .blur(radius: 8)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isHovered || isPressed ? Color(hex: "#FFD700") : .white.opacity(0.4))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isHovered || isPressed ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isHovered || isPressed
                            ? LinearGradient(colors: [Color(hex: "#B8860B").opacity(0.5), Color(hex: "#FFD700").opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Legacy Login Coach Card (for backward compatibility)
struct LoginCoachCard: View {
    let coach: StaffCoach
    let onSelect: () -> Void
    
    var body: some View {
        PremiumCoachCard(coach: coach, onSelect: onSelect)
    }
}

#Preview {
    LoginSplashView()
        .environmentObject(DataManager.shared)
}
