import SwiftUI
import Combine

#if os(iOS)
import UIKit
#endif

// MARK: - App Language Enum
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case chinese = "zh"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .spanish: return "Español"
        }
    }

    var icon: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        case .spanish: return "🇪🇸"
        }
    }
}

// MARK: - Localization Manager
@MainActor
extension Notification.Name {
    /// The app language changed. SwiftDataManager rebuilds its caches, because
    /// phase words and derived session names resolve at cache-build time.
    static let hoopwiseLanguageChanged = Notification.Name("hoopwiseLanguageChanged")
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            guard oldValue != currentLanguage else { return }
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
            // Phase 2.7: phase words — and the session names derived from them
            // — are resolved into the current language when the caches are
            // built. Without this the plan keeps speaking the old language
            // until something else happens to trigger a refresh.
            NotificationCenter.default.post(name: .hoopwiseLanguageChanged, object: nil)
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
