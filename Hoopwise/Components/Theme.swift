import SwiftUI
import Combine

// MARK: - Theme Mode
enum ThemeMode: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Theme Manager
@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: "app_theme_mode")
            updateColorScheme()
        }
    }
    
    @Published var isDarkMode: Bool = true
    
    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "app_theme_mode") ?? "dark"
        self.currentMode = ThemeMode(rawValue: savedMode) ?? .dark
        updateColorScheme()
    }
    
    func updateColorScheme() {
        switch currentMode {
        case .light:
            isDarkMode = false
        case .dark:
            isDarkMode = true
        case .system:
            #if os(iOS)
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
            #else
            isDarkMode = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            #endif
        }
    }
    
    func toggle() {
        currentMode = isDarkMode ? .light : .dark
    }
}

// MARK: - App Theme (Dynamic Light/Dark)
struct AppTheme {
    // Access the current theme state
    static var isDark: Bool {
        ThemeManager.shared.isDarkMode
    }
    
    // Accent color - different for light/dark mode for readability
    static var accentColor: Color {
        isDark ? Color(hex: "#CDFF00") : Color(hex: "#007AFF")  // Lime green (dark) / Blue (light)
    }
    
    // Keep lime green available for dark mode specific uses
    static let limeAccent = Color(hex: "#CDFF00")
    static let blueAccent = Color(hex: "#007AFF")
    
    static let successColor = Color(hex: "#00D26A")      // Bright green
    static let warningColor = Color(hex: "#FFB800")      // Amber
    static let errorColor = Color(hex: "#FF4757")        // Coral red
    
    // Dynamic colors based on theme
    static var primaryColor: Color {
        isDark ? Color(hex: "#0D0D0D") : Color(hex: "#FFFFFF")
    }
    
    static var secondaryColor: Color {
        isDark ? Color(hex: "#1A1A1A") : Color(hex: "#F5F5F7")
    }
    
    static var tertiaryColor: Color {
        isDark ? Color(hex: "#2A2A2A") : Color(hex: "#E8E8ED")
    }
    
    // Backgrounds
    static var background: Color {
        isDark ? Color(hex: "#0D0D0D") : Color(hex: "#FFFFFF")
    }
    
    static var cardBackground: Color {
        isDark ? Color(hex: "#1A1A1A") : Color(hex: "#F5F5F7")
    }
    
    static var surfaceColor: Color {
        isDark ? Color(hex: "#252525") : Color(hex: "#E8E8ED")
    }
    
    // Text colors
    static var textPrimary: Color {
        isDark ? Color(hex: "#FFFFFF") : Color(hex: "#000000")
    }
    
    static var textSecondary: Color {
        isDark ? Color(hex: "#A0A0A0") : Color(hex: "#666666")
    }
    
    static var textTertiary: Color {
        isDark ? Color(hex: "#666666") : Color(hex: "#999999")
    }
    
    // Card shadow
    static var cardShadow: Color {
        isDark ? Color.black.opacity(0.3) : Color.black.opacity(0.08)
    }
    
    // Gradient colors - theme aware
    static var gradientStart: Color {
        isDark ? Color(hex: "#CDFF00") : Color(hex: "#007AFF")  // Lime (dark) / Blue (light)
    }
    static var gradientEnd: Color {
        isDark ? Color(hex: "#00D26A") : Color(hex: "#5856D6")  // Green (dark) / Purple (light)
    }
    static let orangeGradientStart = Color(hex: "#FF6B35")
    static let orangeGradientEnd = Color(hex: "#F7931E")
    
    // Accent gradient
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [orangeGradientStart, orangeGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Minimal shadows and radii
    static let cornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 12
    static let largeCornerRadius: CGFloat = 28
    
    // Spacing system
    static let spacing: CGFloat = 20
    static let smallSpacing: CGFloat = 12
    static let tinySpacing: CGFloat = 6
    static let largeSpacing: CGFloat = 32
    
    // Typography - Clean modern fonts
    static let titleFont = Font.system(size: 32, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 22, weight: .bold, design: .rounded)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 13, weight: .medium, design: .default)
    static let smallFont = Font.system(size: 11, weight: .medium, design: .default)
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
    
    // Muted, sophisticated avatar colors
    static func avatarColor(_ color: AvatarColor) -> Color {
        switch color {
        case .blue: return Color(hex: "#5B8DEF")
        case .green: return Color(hex: "#6BCB77")
        case .orange: return Color(hex: "#FFB347")
        case .purple: return Color(hex: "#9B7EDE")
        case .red: return Color(hex: "#EF6B6B")
        case .teal: return Color(hex: "#4ECDC4")
        case .pink: return Color(hex: "#F8A5C2")
        case .indigo: return Color(hex: "#7C83FD")
        }
    }
    
    static func ageGroupColor(_ group: AgeGroup) -> Color {
        Color(hex: group.colorHex)
    }
    
    static func drillCategoryColor(_ category: DrillCategory) -> Color {
        switch category {
        case .shooting: return Color(hex: "#FFB347")
        case .offense: return Color(hex: "#5B8DEF")
        case .defense: return Color(hex: "#EF6B6B")
        case .skills: return Color(hex: "#9B7EDE")
        case .conditioning: return Color(hex: "#6BCB77")
        case .warmup: return Color(hex: "#FFE066")
        case .cooldown: return Color(hex: "#4ECDC4")
        }
    }
    
    static func difficultyColor(_ level: DifficultyLevel) -> Color {
        switch level {
        case .beginner: return Color(hex: "#6BCB77")
        case .intermediate: return Color(hex: "#FFB347")
        case .advanced: return Color(hex: "#EF6B6B")
        }
    }
    
    static func statusColor(_ status: SessionEventStatus) -> Color {
        switch status {
        case .scheduled: return Color(hex: "#5B8DEF")
        case .inProgress: return Color(hex: "#FFB347")
        case .completed: return Color(hex: "#6BCB77")
        case .cancelled: return Color(hex: "#95A5A6")
        case .skipped: return Color(hex: "#B0BEC5")
        }
    }
    
    static func playCategoryColor(_ category: PlayCategory) -> Color {
        switch category {
        case .motionOffense: return Color(hex: "#5B8DEF")
        case .setPlays: return Color(hex: "#9B7EDE")
        case .zoneOffense: return Color(hex: "#FFB347")
        case .zoneDefense: return Color(hex: "#EF6B6B")
        case .manDefense: return Color(hex: "#F8A5C2")
        case .pressBreak: return Color(hex: "#6BCB77")
        case .fastBreak: return Color(hex: "#4ECDC4")
        case .outOfBounds: return Color(hex: "#95A5A6")
        }
    }
    
    static func contractStatusColor(_ status: ContractStatus) -> Color {
        switch status {
        case .pending: return Color(hex: "#FFB347")
        case .active: return Color(hex: "#6BCB77")
        case .completed: return Color(hex: "#5B8DEF")
        case .expired: return Color(hex: "#EF6B6B")
        case .cancelled: return Color(hex: "#95A5A6")
        }
    }
    
    // MARK: - Accessible Text Color
    /// Returns a darker version of light colors for better readability on light backgrounds
    var accessibleText: Color {
        // Convert to UIColor to extract RGB
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Calculate relative luminance (perceived brightness)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        
        // If color is too light (luminance > 0.6), darken it significantly
        if luminance > 0.6 {
            return Color(red: r * 0.55, green: g * 0.55, blue: b * 0.55)
        }
        // If moderately light, darken slightly
        if luminance > 0.45 {
            return Color(red: r * 0.7, green: g * 0.7, blue: b * 0.7)
        }
        return self
    }
}

// MARK: - View Modifiers (Dark Theme)
struct CardStyle: ViewModifier {
    var elevated: Bool = false
    
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

struct GlassCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(Color.white.opacity(0.05))
                    .background(.ultraThinMaterial.opacity(0.5))
            )
            .cornerRadius(AppTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

struct SoftCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

struct GradientCardStyle: ViewModifier {
    var gradient: LinearGradient = AppTheme.accentGradient
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(gradient)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "#0D0D0D"))
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.accentGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.surfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(AppTheme.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(AppTheme.textPrimary)
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(AppTheme.surfaceColor)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct AccentIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Color(hex: "#0D0D0D"))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(AppTheme.accentGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    func elevatedCard() -> some View {
        modifier(CardStyle(elevated: true))
    }
    
    func glassCard() -> some View {
        modifier(GlassCardStyle())
    }
    
    func softCard() -> some View {
        modifier(SoftCardStyle())
    }
    
    func gradientCard(_ gradient: LinearGradient = AppTheme.accentGradient) -> some View {
        modifier(GradientCardStyle(gradient: gradient))
    }
}

// MARK: - Custom Transitions
extension AnyTransition {
    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }
    
    static var fadeScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        )
    }
}
