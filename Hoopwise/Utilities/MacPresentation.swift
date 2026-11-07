import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
import ObjectiveC
import os

private let popupLog = Logger(subsystem: "hoopwise.mac", category: "popup")

/// A timing line in the Mac popup log (tap → requested → on screen).
func macPopupTrace(_ message: String) {
    popupLog.log("popup \(message, privacy: .public)")
}
#endif

// The Mac app is the iPad app (Mac Catalyst). Luther (November 2026): on the
// Mac a popup opens AT ONCE — no slide-up — and LARGE enough to show its whole
// content, for EVERY popup. One hook does it for the whole app:
// `UIViewController.present` is wrapped on Catalyst, so every SwiftUI
// `.sheet` (they are UIKit form/page sheets underneath) is presented without
// animation and sized to the window. Alerts, menus, popovers, share sheets
// and full-screen covers are left as they are. On iPhone and iPad nothing
// changes. Each presentation logs its final size (subsystem "hoopwise.mac",
// "popup …") so the result can be checked from the log.

#if targetEnvironment(macCatalyst)
enum MacPopups {
    private static var installed = false

    /// Called once at launch.
    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(UIViewController.self,
                                                     #selector(UIViewController.present(_:animated:completion:))),
              let replacement = class_getInstanceMethod(UIViewController.self,
                                                        #selector(UIViewController.hw_present(_:animated:completion:)))
        else { return }
        method_exchangeImplementations(original, replacement)
        // SwiftUI sets a sheet's preferredContentSize to its form size (about
        // 620×680) after presenting; a sheet this hook sized keeps its size.
        if let setter = class_getInstanceMethod(UIViewController.self,
                                                #selector(setter: UIViewController.preferredContentSize)),
           let pinned = class_getInstanceMethod(UIViewController.self,
                                                #selector(UIViewController.hw_setPreferredContentSize(_:))) {
            method_exchangeImplementations(setter, pinned)
        }
        installed = true
        popupLog.debug("popup hook installed")
    }

    /// A sheet's size: nearly the whole window, but not wider than reads well.
    static func size(in window: UIWindow?) -> CGSize? {
        guard let bounds = window?.bounds, bounds.width > 0 else { return nil }
        return CGSize(width: min(bounds.width - 80, 960), height: max(bounds.height - 60, 400))
    }
}

private var pinnedSizeKey: UInt8 = 0

extension UIViewController {
    /// The size the Mac popup hook chose for this sheet, if it chose one.
    var hw_pinnedSize: CGSize? {
        get { (objc_getAssociatedObject(self, &pinnedSizeKey) as? NSValue)?.cgSizeValue }
        set { objc_setAssociatedObject(self, &pinnedSizeKey, newValue.map { NSValue(cgSize: $0) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Esc / ⌘W: close the top-most popup above this controller.
    @objc func hw_closePopup() {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        guard top.hw_pinnedSize != nil else { return }      // only our popups
        OutsideClickDismiss.close(top, how: "key")
    }

    @objc func hw_setPreferredContentSize(_ size: CGSize) {
        hw_setPreferredContentSize(hw_pinnedSize ?? size)   // the original setter
    }

    @objc func hw_present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)?) {
        let isSheet: Bool
        switch controller.modalPresentationStyle {
        case .formSheet, .pageSheet, .automatic: isSheet = !(controller is UIAlertController)
        default: isSheet = false
        }
        guard isSheet else {
            hw_present(controller, animated: animated, completion: completion)   // the original
            return
        }
        controller.modalPresentationStyle = .formSheet
        let target = MacPopups.size(in: view.window)
        if let target {
            controller.hw_pinnedSize = target
            controller.preferredContentSize = target
        }
        popupLog.log("popup requested \(type(of: controller), privacy: .public)")
        // `animated: false` alone still showed a slide: suppress every
        // implicit animation while the transition is set up.
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        hw_present(controller, animated: false) {
            OutsideClickDismiss.attach(to: controller)
            #if DEBUG
            // Agent check: the Esc/⌘W path, without a keyboard.
            if ProcessInfo.processInfo.environment["HOOPWISE_TEST_POPUP_CLOSE"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.hw_closePopup() }
            }
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                popupLog.log("popup \(type(of: controller), privacy: .public) target \(String(describing: target), privacy: .public) now \(Int(controller.view.bounds.width), privacy: .public)×\(Int(controller.view.bounds.height), privacy: .public) pcs \(String(describing: controller.preferredContentSize), privacy: .public)")
            }
            completion?()
        }
    }
}

/// A click on the dimmed window around a Mac popup closes it (Luther,
/// November 2026), exactly as swiping a sheet down does on iPad: the sheet's
/// presentation delegate is asked first, so a sheet that refuses dismissal
/// (`interactiveDismissDisabled`, e.g. a step with unsaved drawing) stays and
/// gets its "attempted to dismiss" callback instead, and SwiftUI's binding is
/// told the sheet went away.
final class OutsideClickDismiss: NSObject, UIGestureRecognizerDelegate {
    private weak var controller: UIViewController?
    private weak var recognizer: UITapGestureRecognizer?
    fileprivate static var key: UInt8 = 0

    /// On the WINDOW (every click passes through it), not the sheet's dimming
    /// container — clicks on the Mac's dimmed area never reached a
    /// recognizer there.
    static func attach(to controller: UIViewController) {
        guard let window = controller.view.window else {
            macPopupTrace("outside click: no window to attach to")
            return
        }
        let handler = OutsideClickDismiss()
        handler.controller = controller
        // Esc and ⌘W close the top popup too (Luther, November 2026: a popup
        // covering the whole window left nowhere to click and no Done).
        controller.addKeyCommand(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [],
                                              action: #selector(UIViewController.hw_closePopup)))
        controller.addKeyCommand(UIKeyCommand(input: "w", modifierFlags: .command,
                                              action: #selector(UIViewController.hw_closePopup)))
        let tap = UITapGestureRecognizer(target: handler, action: #selector(clicked))
        tap.delegate = handler
        tap.cancelsTouchesInView = false
        window.addGestureRecognizer(tap)
        handler.recognizer = tap
        objc_setAssociatedObject(controller, &key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func detach() {
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
    }

    /// Only clicks OUTSIDE the popup, and only while it is the top popup.
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let controller, controller.presentingViewController != nil else {
            detach()           // the popup is gone
            return false
        }
        guard controller.presentedViewController == nil else { return false }
        let point = touch.location(in: controller.view)
        let outside = !controller.view.bounds.contains(point)
        macPopupTrace("click \(outside ? "outside" : "inside") \(type(of: controller)) at \(Int(point.x)),\(Int(point.y)) in \(Int(controller.view.bounds.width))×\(Int(controller.view.bounds.height))")
        return outside
    }

    // A click outside should still close the popup when something else under
    // it also wants the click.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func clicked() {
        guard let controller, controller.presentedViewController == nil else { return }
        Self.close(controller, how: "outside click")
    }

    /// The one way a Mac popup is closed by the user — click outside, Esc or
    /// ⌘W — exactly like an iPad swipe-down: the sheet may refuse.
    static func close(_ controller: UIViewController, how: String) {
        guard let presentation = controller.presentationController else { return }
        let delegate = presentation.delegate
        if delegate?.presentationControllerShouldDismiss?(presentation) == false {
            macPopupTrace("\(how): sheet refuses dismissal")
            delegate?.presentationControllerDidAttemptToDismiss?(presentation)
            return
        }
        macPopupTrace("\(how): dismissed \(type(of: controller))")
        (objc_getAssociatedObject(controller, &key) as? OutsideClickDismiss)?.detach()
        delegate?.presentationControllerWillDismiss?(presentation)
        controller.dismiss(animated: false) {
            delegate?.presentationControllerDidDismiss?(presentation)
        }
    }
}

// MARK: - The Mac window (November 2026, Luther: "more adapted to the Mac,
// without drifting too far"). Only window chrome: the title bar's text and
// toolbar strip go so the app's own content reaches the top of the window
// (the traffic lights stay), and the window cannot be squeezed below a size
// the iPad layouts were built for. The screens themselves are unchanged.
enum MacWindow {
    static let minimumSize = CGSize(width: 900, height: 680)

    static func configure() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.toolbar = nil
            scene.sizeRestrictions?.minimumSize = minimumSize
        }
        popupLog.log("window configured")
    }
}
#endif

extension Notification.Name {
    /// ⌘1–⌘4 on the Mac: switch the main tab (MainTabView observes).
    static let hoopwiseSelectTab = Notification.Name("hoopwiseSelectTab")
}
