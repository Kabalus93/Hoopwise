import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Cross-Platform Colors
extension Color {
    static var systemBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var secondarySystemBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var systemGray6: Color {
        #if os(iOS)
        return Color(UIColor.systemGray6)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var systemGray5: Color {
        #if os(iOS)
        return Color(UIColor.systemGray5)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
    
    static var systemGray4: Color {
        #if os(iOS)
        return Color(UIColor.systemGray4)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}

// MARK: - Cross-Platform View Modifiers

extension View {
    /// Cross-platform navigation bar title display mode
    @ViewBuilder
    func navigationBarTitleDisplayModeCompat(_ mode: NavigationBarTitleDisplayModeCompat) -> some View {
        #if os(iOS)
        switch mode {
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        case .automatic:
            self.navigationBarTitleDisplayMode(.automatic)
        }
        #else
        self
        #endif
    }
    
    /// Cross-platform full screen cover (uses sheet on macOS)
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
    
    /// Cross-platform keyboard type (no-op on macOS)
    @ViewBuilder
    func keyboardTypeCompat(_ type: KeyboardTypeCompat) -> some View {
        #if os(iOS)
        switch type {
        case .default:
            self.keyboardType(.default)
        case .emailAddress:
            self.keyboardType(.emailAddress)
        case .numberPad:
            self.keyboardType(.numberPad)
        case .phonePad:
            self.keyboardType(.phonePad)
        case .decimalPad:
            self.keyboardType(.decimalPad)
        case .URL:
            self.keyboardType(.URL)
        }
        #else
        self
        #endif
    }
    
    /// Cross-platform autocapitalization (no-op on macOS)
    @ViewBuilder
    func autocapitalizationCompat(_ style: AutocapitalizationCompat) -> some View {
        #if os(iOS)
        switch style {
        case .never:
            self.autocapitalization(.none)
        case .words:
            self.autocapitalization(.words)
        case .sentences:
            self.autocapitalization(.sentences)
        case .allCharacters:
            self.autocapitalization(.allCharacters)
        }
        #else
        self
        #endif
    }
}

// MARK: - Compat Enums

enum NavigationBarTitleDisplayModeCompat {
    case inline
    case large
    case automatic
}

enum KeyboardTypeCompat {
    case `default`
    case emailAddress
    case numberPad
    case phonePad
    case decimalPad
    case URL
}

enum AutocapitalizationCompat {
    case never
    case words
    case sentences
    case allCharacters
}

// MARK: - Cross-Platform Toolbar Placements

extension ToolbarItemPlacement {
    static var navigationBarTrailingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .automatic
        #endif
    }
    
    static var navigationBarLeadingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarLeading
        #else
        return .automatic
        #endif
    }
    
    static var topBarLeadingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .automatic
        #endif
    }
    
    static var topBarTrailingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .automatic
        #endif
    }
}

// MARK: - Cross-Platform List Styles

extension View {
    @ViewBuilder
    func listStyleInsetGroupedCompat() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}

// MARK: - Cross-Platform TabView Styles

extension View {
    @ViewBuilder
    func tabViewStylePageCompat() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .automatic))
        #else
        self
        #endif
    }
}
