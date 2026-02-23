import SwiftUI

// MARK: - Mac Design System
/// Shared design components matching the Student List panel style
/// Use these throughout the app for consistent macOS-native appearance

// MARK: - Panel Section Card
/// A frosted glass card with icon + title header, used for grouping related info
struct PanelSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    var showDivider: Bool = false
    var headerAction: (() -> Void)? = nil
    var headerActionLabel: String? = nil
    var headerActionIcon: String? = nil
    
    init(
        _ title: String,
        icon: String,
        showDivider: Bool = false,
        headerAction: (() -> Void)? = nil,
        headerActionLabel: String? = nil,
        headerActionIcon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.showDivider = showDivider
        self.headerAction = headerAction
        self.headerActionLabel = headerActionLabel
        self.headerActionIcon = headerActionIcon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                if let action = headerAction {
                    Button(action: action) {
                        if let label = headerActionLabel, let actionIcon = headerActionIcon {
                            Label(label, systemImage: actionIcon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.accentColor)
                        } else if let actionIcon = headerActionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if showDivider {
                Divider()
            }
            
            content
        }
        .padding(16)
        .background(panelCardBackground)
        .cornerRadius(12)
    }
    
    private var panelCardBackground: some View {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}

// MARK: - Panel Info Row
/// A row with label on left, value on right - matches the Student detail style
struct PanelInfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var valueColor: Color = AppTheme.textPrimary
    var valueFontWeight: Font.Weight = .medium
    
    var body: some View {
        HStack {
            if let icon = icon {
                Label(label, systemImage: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            } else {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: valueFontWeight))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Panel List Row
/// A selectable list row with avatar, title, subtitle, and optional chevron
struct PanelListRow<Avatar: View>: View {
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    var showChevron: Bool = true
    let avatar: Avatar
    let action: () -> Void
    
    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        showChevron: Bool = true,
        @ViewBuilder avatar: () -> Avatar,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.showChevron = showChevron
        self.avatar = avatar()
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                avatar
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                if showChevron && isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel Stat Pill
/// Colored stat display with value and label - matches the Height/Weight/Wingspan pills
struct PanelStatPill: View {
    let value: String
    let unit: String
    let label: String
    var color: Color = .blue
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Panel Skill Row
/// Skill display with name and colored dots rating
struct PanelSkillRow: View {
    let name: String
    let value: Int // 1-5
    var maxValue: Int = 5
    
    var ratingColor: Color {
        switch value {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .green
        default: return .gray
        }
    }
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
            
            Spacer()
            
            HStack(spacing: 2) {
                ForEach(0..<maxValue, id: \.self) { index in
                    Circle()
                        .fill(index < value ? ratingColor : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

// MARK: - Panel Search Bar
/// Search bar matching the Student list style
struct PanelSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textTertiary)
                .font(.system(size: 12))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(panelSearchBackground)
        .cornerRadius(6)
    }
    
    private var panelSearchBackground: some View {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }
}

// MARK: - Panel Header
/// Standard panel header with close button, title, and optional action
struct PanelHeader: View {
    let title: String
    var onClose: (() -> Void)? = nil
    var onAction: (() -> Void)? = nil
    var actionIcon: String? = nil
    var actionColor: Color = AppTheme.accentColor
    
    var body: some View {
        HStack {
            if let close = onClose {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            Spacer()
            
            if let action = onAction, let icon = actionIcon {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(actionColor)
                }
                .buttonStyle(.plain)
            } else {
                // Spacer for balance
                Color.clear.frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Panel Avatar
/// Circular avatar with initials - matches Student list style
struct PanelAvatar: View {
    let initials: String
    var color: Color = .blue
    var size: CGFloat = 36
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Panel Divider with Label
/// A divider with optional centered label
struct PanelDividerWithLabel: View {
    var label: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            
            if let label = label {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .textCase(.uppercase)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Panel Empty State
/// Empty state view with icon and message
struct PanelEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var actionColor: Color = AppTheme.accentColor
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(AppTheme.textTertiary)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(actionColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Panel Column Container
/// Container for Finder-like column navigation
struct PanelColumnContainer<LeftColumn: View, RightColumn: View>: View {
    let leftColumn: LeftColumn
    let rightColumn: RightColumn?
    var leftWidth: CGFloat = 340
    var rightWidth: CGFloat = 440
    var onDismiss: () -> Void
    
    init(
        leftWidth: CGFloat = 340,
        rightWidth: CGFloat = 440,
        onDismiss: @escaping () -> Void,
        @ViewBuilder leftColumn: () -> LeftColumn,
        @ViewBuilder rightColumn: () -> RightColumn?
    ) {
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.onDismiss = onDismiss
        self.leftColumn = leftColumn()
        self.rightColumn = rightColumn()
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Column container
            HStack(spacing: 0) {
                leftColumn
                    .frame(width: leftWidth)
                
                if rightColumn != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                    
                    rightColumn
                        .frame(width: rightWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)
                    .ignoresSafeArea(),
                alignment: .leading
            )
        }
    }
}

// MARK: - Panel Action Button
/// Primary/secondary action button for panels
struct PanelActionButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyle = .primary
    var color: Color = AppTheme.accentColor
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return color
        case .secondary: return color.opacity(0.15)
        case .destructive: return Color.red
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return color
        case .destructive: return .white
        }
    }
}

// MARK: - Panel Badge
/// Small colored badge for status/category display
struct PanelBadge: View {
    let text: String
    var color: Color = AppTheme.accentColor
    var style: BadgeStyle = .filled
    
    enum BadgeStyle {
        case filled
        case outlined
        case subtle
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style == .outlined ? color : .clear, lineWidth: 1)
            )
    }
    
    private var backgroundColor: Color {
        switch style {
        case .filled: return color
        case .outlined: return .clear
        case .subtle: return color.opacity(0.15)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled: return .white
        case .outlined: return color
        case .subtle: return color
        }
    }
}

// Note: HoopwiseLogoView is defined in SAMLogoView.swift
