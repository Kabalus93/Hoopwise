import SwiftUI

/// TEXT SIZE ON THE MAC (25 Nov 2026, Luther: "in the settings I want to be
/// able to set font size"). Most of the app's type is set in fixed points, so
/// Dynamic Type alone would grow some words and not others. Instead every
/// window's content — the main window, the board, each popup and cover — is
/// drawn at a scale, so type, photos, courts and controls grow together and
/// each page simply has a little less room, like a zoom level in a browser.
///
/// The work is one line in MacGlass's layout hook: a root view with a scale
/// transform is laid out by UIKit at frame ÷ scale. Alerts, menus, popovers
/// and system pickers are left alone.
enum MacTextSize: Double, CaseIterable, Identifiable {
    case small = 0.9, standard = 1.0, large = 1.1, larger = 1.2, largest = 1.3

    var id: Double { rawValue }
    static let key = "mac.textScale"

    func title(chinese zh: Bool) -> String {
        switch self {
        case .small: return zh ? "小" : "Small"
        case .standard: return zh ? "标准" : "Default"
        case .large: return zh ? "大" : "Large"
        case .larger: return zh ? "更大" : "Larger"
        case .largest: return zh ? "最大" : "Largest"
        }
    }

    /// The scale in force. DEBUG: HOOPWISE_TEXT_SCALE=<0.9…1.3> for looking at
    /// it on a demo copy WITHOUT writing the setting — on the Mac a demo copy
    /// shares the real app's preferences.
    static var scale: CGFloat {
        #if targetEnvironment(macCatalyst)
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HOOPWISE_TEXT_SCALE"], let v = Double(raw) {
            return CGFloat(min(1.3, max(0.9, v)))
        }
        #endif
        let stored = UserDefaults.standard.double(forKey: key)
        return stored == 0 ? 1 : CGFloat(min(1.3, max(0.9, stored)))
        #else
        return 1
        #endif
    }

    static var current: MacTextSize {
        allCases.min { abs($0.rawValue - Double(scale)) < abs($1.rawValue - Double(scale)) } ?? .standard
    }

    #if targetEnvironment(macCatalyst)
    /// Stores the choice and re-lays every window out at it.
    static func set(_ size: MacTextSize) {
        UserDefaults.standard.set(size.rawValue, forKey: key)
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                var controller = window.rootViewController
                while let c = controller {
                    c.hw_applyTextScale()
                    c.view.setNeedsLayout()
                    controller = c.presentedViewController
                }
            }
        }
    }
    #endif
}

extension UIViewController {
    /// A window's root and every popup / cover presented over it are drawn at
    /// the chosen scale. With a scale transform, the frame UIKit gives the
    /// view becomes bounds of frame ÷ scale, so the page lays itself out in
    /// the smaller (or larger) space and fills the same area on screen.
    func hw_applyTextScale() {
        guard isViewLoaded, parent == nil else { return }
        let isRoot = view.window?.rootViewController === self
        let isPopup = presentingViewController != nil && modalPresentationStyle != .popover
        guard isRoot || isPopup, String(describing: type(of: self)).contains("Hosting") else { return }
        let scale = MacTextSize.scale
        let wanted = CGAffineTransform(scaleX: scale, y: scale)
        guard view.transform != wanted else { return }
        let frame = view.frame
        view.transform = wanted
        view.frame = frame
    }
}
