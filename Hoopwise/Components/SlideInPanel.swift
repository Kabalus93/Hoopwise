import SwiftUI

// MARK: - Slide-In Panel (macOS-native style)
/// A reusable panel that slides in from the trailing edge with frosted glass effect
/// Sizes to content width with optional min/max constraints
struct SlideInPanel<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let showSaveButton: Bool
    let saveButtonTitle: String
    let saveAction: (() -> Void)?
    let content: () -> Content
    
    init(
        isPresented: Binding<Bool>,
        title: String,
        minWidth: CGFloat = 320,
        maxWidth: CGFloat = 480,
        showSaveButton: Bool = false,
        saveButtonTitle: String = "Save",
        saveAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.showSaveButton = showSaveButton
        self.saveButtonTitle = saveButtonTitle
        self.saveAction = saveAction
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Dimmed background tap to dismiss
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissPanel()
                    }
                
                // Panel content
                VStack(spacing: 0) {
                    // Header
                    panelHeader
                    
                    Divider()
                        .opacity(0.5)
                    
                    // Content
                    ScrollView {
                        content()
                            .padding(.vertical, 16)
                    }
                }
                .frame(
                    minWidth: minWidth,
                    idealWidth: maxWidth,
                    maxWidth: geometry.size.width * 0.95
                )
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 24, x: -8, y: 0)
                .padding(.vertical, 12)
                .padding(.trailing, 12)
            }
        }
        .ignoresSafeArea()
    }
    
    private var panelHeader: some View {
        HStack(spacing: 12) {
            Button(action: dismissPanel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            if showSaveButton {
                Button(action: {
                    saveAction?()
                }) {
                    Text(saveButtonTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#00D4AA"))
                }
                .buttonStyle(.plain)
            } else {
                // Spacer for symmetry
                Color.clear
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var panelBackground: some View {
        ZStack {
            // Dark glassmorphic background
            Color(hex: "#0D0D0F").opacity(0.95)
            
            #if os(iOS)
            VisualEffectBlur(blurStyle: .systemThinMaterial)
            #else
            VisualEffectBlur()
            #endif
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func dismissPanel() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

// MARK: - Slide-In Panel Modifier
extension View {
    /// Presents a slide-in panel from the trailing edge
    func slideInPanel<Content: View>(
        isPresented: Binding<Bool>,
        title: String,
        minWidth: CGFloat = 320,
        maxWidth: CGFloat = 480,
        showSaveButton: Bool = false,
        saveButtonTitle: String = "Save",
        saveAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                SlideInPanel(
                    isPresented: isPresented,
                    title: title,
                    minWidth: minWidth,
                    maxWidth: maxWidth,
                    showSaveButton: showSaveButton,
                    saveButtonTitle: saveButtonTitle,
                    saveAction: saveAction,
                    content: content
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented.wrappedValue)
    }
}

// MARK: - Panel Section
/// A styled section for use within SlideInPanel
struct PanelSection<Content: View>: View {
    let title: String?
    let content: () -> Content
    
    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .textCase(.uppercase)
            }
            
            content()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Panel Text Field
/// A styled text field for use within panels
struct PanelTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.surfaceColor.opacity(0.8))
        )
    }
}

// MARK: - Panel Button
/// A styled action button for panels
struct PanelButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
    }
    
    init(
        _ title: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return AppTheme.accentColor
        case .secondary: return AppTheme.surfaceColor
        case .destructive: return AppTheme.errorColor
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return AppTheme.textPrimary
        case .destructive: return .white
        }
    }
}
