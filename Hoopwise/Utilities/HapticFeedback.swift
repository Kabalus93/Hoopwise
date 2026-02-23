import SwiftUI
import Combine

#if os(iOS)
import UIKit
#endif

// MARK: - App Language Enum
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case chinese = "zh"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
    
    var icon: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        }
    }
}

// MARK: - Localization Manager
@MainActor
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "en"
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .english
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }
}

// MARK: - Haptic Feedback
/// Cross-platform haptic feedback helper
/// Provides haptic feedback on iOS and does nothing on macOS
enum HapticFeedback {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case selection
    
    func trigger() {
        #if os(iOS)
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
        // On macOS, haptics are not available - do nothing
    }
    
    /// Static convenience methods
    static func impact(_ style: HapticFeedback = .medium) {
        style.trigger()
    }
    
    static func notification(_ type: HapticFeedback) {
        type.trigger()
    }
}
