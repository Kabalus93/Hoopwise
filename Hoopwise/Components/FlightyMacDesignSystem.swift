import SwiftUI

#if os(macOS)
// MARK: - Flighty macOS Design System
/// Elegant, refined design language for macOS with Flighty aesthetics
/// Features: Scaled fonts, frosted glass, Finder-style columns, slide-in panels

// MARK: - Design Tokens
struct FlightyMac {
    // Colors - Light theme with Flighty orange accent
    static let background = Color(hex: "#f5f5f7")
    static let cardBackground = Color.white
    static let sidebarBackground = Color(NSColor.controlBackgroundColor).opacity(0.6)
    static let accent = Color.orange
    static let accentGradient = LinearGradient(
        colors: [Color.orange, Color.orange.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Text colors
    static let textPrimary = Color.black
    static let textSecondary = Color.gray
    static let textTertiary = Color.gray.opacity(0.6)
    
    // Shadows
    static let cardShadow = Color.black.opacity(0.04)
    static let elevatedShadow = Color.black.opacity(0.08)
    
    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    
    // Corner radii
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14
    static let radiusXL: CGFloat = 18
    
    // Font sizes - Scaled down for elegance
    static let fontXS: CGFloat = 9
    static let fontSM: CGFloat = 10
    static let fontMD: CGFloat = 11
    static let fontLG: CGFloat = 12
    static let fontXL: CGFloat = 13
    static let fontXXL: CGFloat = 15
    static let fontTitle: CGFloat = 18
    static let fontHero: CGFloat = 22
}

// MARK: - Frosted Glass Card
/// A card with frosted glass effect and subtle border
struct FlightyGlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = FlightyMac.spacingLG
    var cornerRadius: CGFloat = FlightyMac.radiusLG
    var showBorder: Bool = true
    
    init(
        padding: CGFloat = FlightyMac.spacingLG,
        cornerRadius: CGFloat = FlightyMac.radiusLG,
        showBorder: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.showBorder = showBorder
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(showBorder ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .shadow(color: FlightyMac.cardShadow, radius: 8, y: 2)
    }
}

// MARK: - Solid White Card
/// A clean white card with subtle shadow
struct FlightyCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = FlightyMac.spacingLG
    var cornerRadius: CGFloat = FlightyMac.radiusLG
    
    init(
        padding: CGFloat = FlightyMac.spacingLG,
        cornerRadius: CGFloat = FlightyMac.radiusLG,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(FlightyMac.cardBackground)
            .cornerRadius(cornerRadius)
            .shadow(color: FlightyMac.cardShadow, radius: 8, y: 2)
    }
}

// MARK: - Section Header
/// Elegant section header with optional action
struct FlightySectionHeader: View {
    let title: String
    var icon: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var actionIcon: String? = nil
    
    var body: some View {
        HStack(spacing: FlightyMac.spacingSM) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: FlightyMac.fontSM))
                    .foregroundColor(FlightyMac.textTertiary)
            }
            
            Text(title.uppercased())
                .font(.system(size: FlightyMac.fontXS, weight: .bold, design: .monospaced))
                .foregroundColor(FlightyMac.textTertiary)
                .tracking(0.5)
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let icon = actionIcon {
                            Image(systemName: icon)
                                .font(.system(size: FlightyMac.fontXS))
                        }
                        if let label = actionLabel {
                            Text(label)
                                .font(.system(size: FlightyMac.fontSM, weight: .medium))
                        }
                    }
                    .foregroundColor(FlightyMac.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Finder Column
/// A Finder-style column with header and scrollable content
struct FlightyFinderColumn<Content: View>: View {
    let title: String
    var icon: String? = nil
    var width: CGFloat? = nil
    var showDivider: Bool = true
    let content: Content
    
    init(
        _ title: String,
        icon: String? = nil,
        width: CGFloat? = nil,
        showDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.width = width
        self.showDivider = showDivider
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: FlightyMac.spacingSM) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: FlightyMac.fontSM))
                        .foregroundColor(FlightyMac.accent)
                }
                Text(title)
                    .font(.system(size: FlightyMac.fontLG, weight: .semibold))
                    .foregroundColor(FlightyMac.textPrimary)
                Spacer()
            }
            .padding(.horizontal, FlightyMac.spacingMD)
            .padding(.vertical, FlightyMac.spacingSM)
            .background(Color.white.opacity(0.5))
            
            Divider()
            
            // Content
            ScrollView(showsIndicators: false) {
                content
                    .padding(FlightyMac.spacingSM)
            }
        }
        .frame(width: width)
        .background(FlightyMac.background.opacity(0.5))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: showDivider ? 1 : 0),
            alignment: .trailing
        )
    }
}

// MARK: - Column List Row
/// A selectable row for Finder-style columns
struct FlightyColumnRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color = FlightyMac.accent
    var isSelected: Bool = false
    var badge: String? = nil
    var badgeColor: Color = FlightyMac.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: FlightyMac.spacingSM) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: FlightyMac.fontMD))
                        .foregroundColor(isSelected ? .white : iconColor)
                        .frame(width: 20)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: FlightyMac.fontLG, weight: .medium))
                        .foregroundColor(isSelected ? .white : FlightyMac.textPrimary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: FlightyMac.fontXS))
                            .foregroundColor(isSelected ? .white.opacity(0.7) : FlightyMac.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: FlightyMac.fontXS, weight: .bold))
                        .foregroundColor(isSelected ? .white : badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : badgeColor.opacity(0.12))
                        )
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: FlightyMac.fontXS, weight: .semibold))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : FlightyMac.textTertiary)
            }
            .padding(.horizontal, FlightyMac.spacingMD)
            .padding(.vertical, FlightyMac.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: FlightyMac.radiusSM)
                    .fill(isSelected ? FlightyMac.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slide-In Detail Panel
/// A slide-in panel from the right edge with frosted glass
struct FlightySlidePanel<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = 400
    let content: Content
    
    init(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        width: CGFloat = 400,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { 
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(FlightyMac.textTertiary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: FlightyMac.fontXL, weight: .semibold))
                            .foregroundColor(FlightyMac.textPrimary)
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: FlightyMac.fontXS))
                                .foregroundColor(FlightyMac.textTertiary)
                        }
                    }
                    
                    Spacer()
                    
                    // Balance spacer
                    Color.clear.frame(width: 18, height: 18)
                }
                .padding(.horizontal, FlightyMac.spacingLG)
                .padding(.vertical, FlightyMac.spacingMD)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // Content
                ScrollView(showsIndicators: false) {
                    content
                        .padding(FlightyMac.spacingLG)
                }
            }
            .frame(width: width)
            .background(.ultraThickMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1),
                alignment: .leading
            )
        }
    }
}

// MARK: - Stat Cell
/// A compact stat display for dashboards
struct FlightyStatCell: View {
    let value: String
    let label: String
    var color: Color = FlightyMac.accent
    var icon: String? = nil
    
    var body: some View {
        VStack(spacing: 2) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: FlightyMac.fontSM))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: FlightyMac.fontTitle, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: FlightyMac.fontXS, weight: .medium))
                .foregroundColor(FlightyMac.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sidebar Item
/// Elegant sidebar navigation item
struct FlightySidebarItem: View {
    let title: String
    let icon: String
    var isSelected: Bool = false
    var badge: Int? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: FlightyMac.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: FlightyMac.fontMD))
                    .foregroundColor(isSelected ? .white : FlightyMac.textSecondary)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: FlightyMac.fontLG, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : FlightyMac.textPrimary)
                
                Spacer()
                
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: FlightyMac.fontXS, weight: .bold))
                        .foregroundColor(isSelected ? FlightyMac.accent : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white : FlightyMac.accent)
                        )
                }
            }
            .padding(.horizontal, FlightyMac.spacingMD)
            .padding(.vertical, FlightyMac.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: FlightyMac.radiusSM)
                    .fill(isSelected ? FlightyMac.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Field
/// Elegant search field with frosted glass
struct FlightySearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var width: CGFloat? = nil
    
    var body: some View {
        HStack(spacing: FlightyMac.spacingSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: FlightyMac.fontSM))
                .foregroundColor(FlightyMac.textTertiary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: FlightyMac.fontMD))
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: FlightyMac.fontSM))
                        .foregroundColor(FlightyMac.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, FlightyMac.spacingSM)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: FlightyMac.radiusSM)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlightyMac.radiusSM)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .frame(width: width)
    }
}

// MARK: - Pill Button
/// A compact pill-shaped button
struct FlightyPillButton: View {
    let title: String
    var icon: String? = nil
    var isSelected: Bool = false
    var color: Color = FlightyMac.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: FlightyMac.fontXS))
                }
                Text(title)
                    .font(.system(size: FlightyMac.fontSM, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, FlightyMac.spacingSM)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Row
/// A label-value row for detail panels
struct FlightyInfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var valueColor: Color = FlightyMac.textPrimary
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: FlightyMac.fontXS))
                    .foregroundColor(FlightyMac.textTertiary)
                    .frame(width: 14)
            }
            
            Text(label)
                .font(.system(size: FlightyMac.fontMD))
                .foregroundColor(FlightyMac.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: FlightyMac.fontMD, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Avatar
/// A circular avatar with initials
struct FlightyAvatar: View {
    let initials: String
    var color: Color = FlightyMac.accent
    var size: CGFloat = 32
    
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

// MARK: - Badge
/// A small colored badge
struct FlightyBadge: View {
    let text: String
    var color: Color = FlightyMac.accent
    var style: BadgeStyle = .filled
    
    enum BadgeStyle {
        case filled, outlined, subtle
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: FlightyMac.fontXS, weight: .bold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style == .outlined ? color : Color.clear, lineWidth: 1)
            )
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled: return .white
        case .outlined: return color
        case .subtle: return color
        }
    }
    
    private var background: some View {
        Group {
            switch style {
            case .filled: color
            case .outlined: Color.clear
            case .subtle: color.opacity(0.12)
            }
        }
    }
}

// MARK: - Empty State
/// An elegant empty state view
struct FlightyEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: FlightyMac.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(FlightyMac.textTertiary)
            
            Text(title)
                .font(.system(size: FlightyMac.fontXL, weight: .medium))
                .foregroundColor(FlightyMac.textSecondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: FlightyMac.fontMD))
                    .foregroundColor(FlightyMac.textTertiary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: FlightyMac.fontMD, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, FlightyMac.spacingLG)
                        .padding(.vertical, FlightyMac.spacingSM)
                        .background(FlightyMac.accent)
                        .cornerRadius(FlightyMac.radiusSM)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FlightyMac.spacingXL)
    }
}

// MARK: - View Extension for Slide Panel
extension View {
    func flightySlidePanel<Content: View>(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        width: CGFloat = 400,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            self
            
            if isPresented.wrappedValue {
                // Dimmed background
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented.wrappedValue = false
                        }
                    }
                
                FlightySlidePanel(
                    isPresented: isPresented,
                    title: title,
                    subtitle: subtitle,
                    width: width,
                    content: content
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented.wrappedValue)
    }
}

#endif
