import SwiftUI

// MARK: - ==================== GLASSMORPHIC DESIGN SYSTEM ====================
// Extracted from MacContentView.swift for better compilation performance

// MARK: - Design System Colors
struct GlassColors {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let backgroundGradientStart = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let backgroundGradientEnd = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let glassBackground = Color.white.opacity(0.08)
    static let glassBackgroundLight = Color.white.opacity(0.12)
    static let glassBackgroundDark = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.20)
    static let glassBorderSubtle = Color.white.opacity(0.10)
    static let accentCyan = Color(red: 0, green: 0.8, blue: 1.0)
    static let accentCyanGlow = Color(red: 0, green: 0.8, blue: 1.0).opacity(0.6)
    static let accentOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let accentGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let accentRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let accentYellow = Color(red: 1.0, green: 0.85, blue: 0.2)
    static let accentGold = Color(red: 0.85, green: 0.65, blue: 0.13)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let textMuted = Color.white.opacity(0.35)
}

// MARK: - Design System Metrics
struct GlassMetrics {
    static let radiusLarge: CGFloat = 28
    static let radiusMedium: CGFloat = 20
    static let radiusSmall: CGFloat = 12
    static let radiusXSmall: CGFloat = 8
    static let spacingXL: CGFloat = 32
    static let spacingLarge: CGFloat = 24
    static let spacingMedium: CGFloat = 16
    static let spacingSmall: CGFloat = 12
    static let spacingXS: CGFloat = 8
    static let spacingXXS: CGFloat = 4
    static let blurHeavy: CGFloat = 60
    static let blurMedium: CGFloat = 40
    static let blurLight: CGFloat = 20
    static let shadowRadius: CGFloat = 30
    static let shadowOpacity: Double = 0.3
}

// MARK: - Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassMetrics.radiusMedium
    var opacity: Double = 0.08
    var borderOpacity: Double = 0.20
    var padding: CGFloat = GlassMetrics.spacingMedium
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(opacity))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.5)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(GlassMetrics.shadowOpacity), radius: GlassMetrics.shadowRadius, x: 0, y: 10)
    }
}

// MARK: - Glass Container Modifier
struct GlassContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassMetrics.radiusLarge
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.06))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 20)
    }
}

// MARK: - Glass Button Style
struct GlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var accentColor: Color = GlassColors.accentCyan
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, GlassMetrics.spacingMedium)
            .padding(.vertical, GlassMetrics.spacingSmall)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(isActive ? accentColor : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .stroke(isActive ? accentColor.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundColor(isActive ? .black : .white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Primary Action Button Style
struct PrimaryActionButtonStyle: ButtonStyle {
    var accentColor: Color = GlassColors.accentCyan
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, GlassMetrics.spacingLarge)
            .padding(.vertical, GlassMetrics.spacingSmall)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 12, x: 0, y: 4)
            )
            .foregroundColor(.black)
            .fontWeight(.semibold)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extensions
extension View {
    func glassCard(
        cornerRadius: CGFloat = GlassMetrics.radiusMedium,
        opacity: Double = 0.08,
        borderOpacity: Double = 0.20,
        padding: CGFloat = GlassMetrics.spacingMedium
    ) -> some View {
        modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            opacity: opacity,
            borderOpacity: borderOpacity,
            padding: padding
        ))
    }
    
    func glassContainer(cornerRadius: CGFloat = GlassMetrics.radiusLarge) -> some View {
        modifier(GlassContainerModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Ambient Background View
struct AmbientBackgroundView: View {
    var primaryColor: Color = GlassColors.accentCyan
    var secondaryColor: Color = GlassColors.accentOrange
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.06, blue: 0.10),
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Ambient glow effects
            Circle()
                .fill(primaryColor.opacity(0.15))
                .blur(radius: 150)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(secondaryColor.opacity(0.10))
                .blur(radius: 120)
                .offset(x: 150, y: 300)
            
            Circle()
                .fill(primaryColor.opacity(0.08))
                .blur(radius: 100)
                .offset(x: 200, y: -100)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Text Field
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(GlassColors.textTertiary)
            }
            
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundColor(GlassColors.textPrimary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.radiusSmall)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Glass Section Header
struct GlassSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    // Convenience init for trailing closure syntax
    init(title: String, subtitle: String? = nil, actionLabel: String = "See All", action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }
    
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(GlassColors.textSecondary)
                    .tracking(1.5)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(GlassColors.textMuted)
                }
            }
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GlassColors.accentCyan)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Glass Empty State
struct GlassEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(GlassColors.textMuted)
            
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(GlassColors.textSecondary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(GlassColors.textTertiary)
                .multilineTextAlignment(.center)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Glass Avatar
struct GlassAvatar: View {
    let initials: String
    var color: Color = GlassColors.accentCyan
    var size: CGFloat = 40
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Floating Orb (for premium backgrounds)
struct FloatingOrb: View {
    let color: Color
    let size: CGFloat
    let offset: CGSize
    let blur: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: offset.width + (isAnimating ? 20 : -20),
                    y: offset.height + (isAnimating ? 15 : -15))
            .animation(
                .easeInOut(duration: 8)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
