import SwiftUI
import UIKit
import ObjectiveC
import os

// THE MAC WINDOW IS FROSTED GLASS (25 Nov 2026, Luther, after the first film
// room: "I like the direction so far but not so much having the basketball
// court in the background. How about nothing? Just a frosted glass? Also let
// other layers adopt the new look."). Nothing is painted behind the app: the
// window itself is glass — what is behind it on the desktop shows through,
// blurred and dimmed — and every layer above (pushed pages, lists, bars,
// popups) is clear so the same glass runs through all of them.
//
// Mac Catalyst has no SwiftUI or UIKit way to blur BEHIND the window, so the
// AppKit window is reached by name (NSApplication → windows) and given an
// NSVisualEffectView under the app's content. Only public AppKit classes and
// properties, addressed dynamically because Catalyst cannot import AppKit.

private let glassLog = Logger(subsystem: "hoopwise.mac", category: "glass")

enum MacGlass {
    /// Set while the Quick Peep's stage is up: its cover stays clear.
    static var clearCover = false
    /// What a full-screen cover is painted with on the Mac.
    static let coverColor = UIColor(red: 0.105, green: 0.11, blue: 0.125, alpha: 1)
    private static var installed = false
    private static var timer: Timer?
    /// NSVisualEffectView.Material.hudWindow — dark, translucent, the same in
    /// light and dark system appearance.
    private static let material = 13

    /// Once at launch: page-level view controllers stop painting an opaque
    /// background, pushes stop sliding (two clear pages sliding over each
    /// other show through one another), and every window is frosted as it
    /// appears.
    static func install() {
        #if DEBUG && targetEnvironment(macCatalyst)
        dumpTopViewsIfAsked()
        #endif
        // The Mac — and the iPad simulator's DEBUG film-room preview, so the
        // layers can be looked at there (the glass itself is the Mac's).
        guard FilmRoom.isOn, !installed else { return }
        installed = true
        swap(#selector(UIViewController.viewWillLayoutSubviews), #selector(UIViewController.hw_glassLayout), on: UIViewController.self)
        swap(#selector(UINavigationController.pushViewController(_:animated:)),
             #selector(UINavigationController.hw_glassPush(_:animated:)), on: UINavigationController.self)
        swap(#selector(UINavigationController.popViewController(animated:)),
             #selector(UINavigationController.hw_glassPop(animated:)), on: UINavigationController.self)

        // No scroll-edge strip: iOS 26 lays a dimming backdrop over the top of
        // every scrolling page, under the title bar. On the glass it showed
        // as a dark bar across the work area when the pointer came near the
        // top or the window was behind another (26 Nov 2026, Luther).
        swapSafely(UIScrollView.self, #selector(UIView.didMoveToWindow), #selector(UIScrollView.hw_glassScrollMoved))
        // Hiding the effect is not enough: its backdrop (a view of its own
        // inside the scroll view) stays and is what paints the strip.
        if let backdrop = NSClassFromString("_TtCC5UIKit20ScrollEdgeEffectView12BackdropView") {
            swapSafely(backdrop, #selector(UIView.didMoveToWindow), #selector(UIView.hw_glassHideWhenShown))
            swapSafely(backdrop, #selector(UIView.layoutSubviews), #selector(UIView.hw_glassHideOnLayout))
        }

        // Bars and lists sit on the glass, not on their own slabs.
        // Grouped List rows: the system paints each an opaque dark slab.
        swapSafely(UICollectionViewListCell.self, #selector(UIView.layoutSubviews), #selector(UICollectionViewListCell.hw_glassCellLayout))

        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        // Titles in light type, like the numbers on the panes.
        bar.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 30, weight: .light),
                                        .foregroundColor: UIColor.white]
        bar.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 15, weight: .medium),
                                   .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UICollectionView.appearance().backgroundColor = .clear
        UITableView.appearance().backgroundColor = .clear

        #if targetEnvironment(macCatalyst)
        // Windows come and go (popups are windows of their own on the Mac).
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { frostWindows() }
        }
        DispatchQueue.main.async { frostWindows() }
        #endif
    }

    /// Swaps a method a class INHERITS without touching its superclass: the
    /// class first gets its own copy.
    private static func swapSafely(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let o = class_getInstanceMethod(type, original), let r = class_getInstanceMethod(type, replacement) else { return }
        if class_addMethod(type, original, method_getImplementation(r), method_getTypeEncoding(r)) {
            class_replaceMethod(type, replacement, method_getImplementation(o), method_getTypeEncoding(o))
        } else {
            method_exchangeImplementations(o, r)
        }
    }

    private static func swap(_ a: Selector, _ b: Selector, on type: AnyClass) {
        guard let x = class_getInstanceMethod(type, a), let y = class_getInstanceMethod(type, b) else { return }
        method_exchangeImplementations(x, y)
    }

    #if targetEnvironment(macCatalyst)
    private static var frosted = Set<ObjectIdentifier>()

    #if DEBUG
    /// HOOPWISE_TOPBAR_DUMP=<seconds>: after that long, logs every view near
    /// the top of each window that paints something (what draws a strip there).
    static func dumpTopViewsIfAsked() {
        guard let raw = ProcessInfo.processInfo.environment["HOOPWISE_TOPBAR_DUMP"], let after = Double(raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            for scene in UIApplication.shared.connectedScenes {
                guard let scene = scene as? UIWindowScene else { continue }
                for window in scene.windows {
                    func walk(_ v: UIView, _ depth: Int) {
                        let f = v.convert(v.bounds, to: window)
                        if f.minY < 60, f.height < 120, f.width > 300, !v.isHidden, v.alpha > 0.01 {
                            let bg = v.backgroundColor.flatMap { $0.cgColor.components?.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "-"
                            let layerBg = v.layer.backgroundColor.flatMap { $0.components?.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "-"
                            let line = "\(depth) \(NSStringFromClass(type(of: v))) < \(v.superview.map { NSStringFromClass(type(of: $0)) } ?? "-") < \(v.superview?.superview.map { NSStringFromClass(type(of: $0)) } ?? "-") hidden=\(v.isHidden) frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) bg=\(bg) layer=\(layerBg) alpha=\(v.alpha)"
                            glassLog.log("TOPDUMP \(line, privacy: .public)")
                        }
                        for sub in v.subviews { walk(sub, depth + 1) }
                    }
                    walk(window, 0)
                }
            }
        }
    }
    #endif

    /// Every AppKit window of the app gets the glass under its content, once.
    static func frostWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                if window.backgroundColor != .clear {
                    window.backgroundColor = .clear
                    window.isOpaque = false
                }
                // The film room is a dark room in every window (the Coach
                // board's own window came up light).
                if window.overrideUserInterfaceStyle != .dark { window.overrideUserInterfaceStyle = .dark }
            }
        }
        guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
              let app = appClass.value(forKey: "sharedApplication") as? NSObject,
              let windows = app.value(forKey: "windows") as? [NSObject],
              let effectClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type,
              let clear = (NSClassFromString("NSColor") as? NSObject.Type)?.value(forKey: "clearColor")
        else { return }
        for window in windows where !frosted.contains(ObjectIdentifier(window)) {
            // Menus, tooltips and the like are not the app's content windows.
            let name = NSStringFromClass(type(of: window))
            guard name.contains("UINSWindow") || name.contains("Presentation") || name == "NSWindow",
                  let content = window.value(forKey: "contentView") as? NSObject,
                  let subviews = content.value(forKey: "subviews") as? [NSObject] else { continue }
            frosted.insert(ObjectIdentifier(window))
            window.setValue(false, forKey: "opaque")
            window.setValue(clear, forKey: "backgroundColor")
            // The title bar draws nothing of its own. Left to the system it
            // painted a dark strip across the top of the glass whenever the
            // pointer came near the window's buttons, and while the window
            // was behind another (26 Nov 2026, Luther: "the black bar at the
            // top when the mouse hovers").
            if window.responds(to: NSSelectorFromString("setTitlebarAppearsTransparent:")) {
                window.setValue(true, forKey: "titlebarAppearsTransparent")
            }
            if window.responds(to: NSSelectorFromString("setTitlebarSeparatorStyle:")) {
                window.setValue(1, forKey: "titlebarSeparatorStyle")    // none
            }
            let effect = effectClass.init()
            effect.setValue(material, forKey: "material")
            effect.setValue(0, forKey: "blendingMode")      // behind the window
            effect.setValue(1, forKey: "state")             // frosted when the window is not in front, too
            if let frame = content.value(forKey: "bounds") { effect.setValue(frame, forKey: "frame") }
            effect.setValue(18, forKey: "autoresizingMask") // width + height
            // A popup is a window of its own and nothing paints the room's
            // tint in it: a form whose page is clear came up as raw, pale
            // glass. It gets the tint itself, a little denser than the main
            // window so it reads as the sheet in front.
            var under: [NSObject] = [effect]
            if name.contains("Presentation") || name == "NSWindow", let viewClass = NSClassFromString("NSView") as? NSObject.Type {
                let tint = viewClass.init()
                tint.setValue(true, forKey: "wantsLayer")
                (tint.value(forKey: "layer") as? CALayer)?.backgroundColor =
                    UIColor(red: 0.05, green: 0.055, blue: 0.075, alpha: 0.8).cgColor
                if let frame = content.value(forKey: "bounds") { tint.setValue(frame, forKey: "frame") }
                tint.setValue(18, forKey: "autoresizingMask")
                under.append(tint)
            }
            content.setValue(under + subviews, forKey: "subviews")
            glassLog.log("glass frosted \(name, privacy: .public)")
        }
    }
    #endif
}

extension UIViewController {
    /// Hosting, navigation and split controllers paint systemBackground by
    /// default — on the glass they are clear. Pickers, cameras, alerts and
    /// other system screens keep their own background.
    @objc func hw_glassLayout() {
        hw_glassLayout()
        hw_applyTextScale()
        // Clear pages are see-through: only the top page of a stack shows
        // (the page underneath was readable through the one pushed over it).
        if let stack = self as? UINavigationController { stack.hw_showOnlyTheTopPage() }
        // A full-screen cover (Create Game, the live game, the recap) shares
        // the main window with the page that opened it, and that page stays
        // drawn: a clear cover showed it through, unreadable. A cover is a
        // solid dark stage. The Quick Peep's stage is the one cover that is
        // meant to float over its page (MacGlass.clearCover).
        if isViewLoaded, parent == nil, presentingViewController != nil, !MacGlass.clearCover,
           modalPresentationStyle == .fullScreen || modalPresentationStyle == .overFullScreen,
           String(describing: type(of: self)).contains("Hosting") {
            if view.backgroundColor != MacGlass.coverColor { view.backgroundColor = MacGlass.coverColor }
            // The cover's view starts under the title bar; its container
            // fills the window, so the strip above is covered too.
            if let container = view.superview, container !== view.window, container.backgroundColor != MacGlass.coverColor {
                container.backgroundColor = MacGlass.coverColor
            }
            return
        }
        guard isViewLoaded, view.backgroundColor != .clear else { return }
        let name = String(describing: type(of: self))
        if name.contains("Hosting") || name.contains("Navigation") || name.contains("SplitView")
            || name.contains("NavigationStack") || name.contains("Sidebar") {
            view.backgroundColor = .clear
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOOPWISE_GLASS_TRACE"] == "1" {
            var chain: [String] = []
            var v: UIView? = view
            while let x = v {
                if let c = x.backgroundColor, c != .clear { chain.append("\(type(of: x))=\(c.cgColor.components?.map { String(format: "%.2f", $0) }.joined(separator: ",") ?? "?")") }
                v = x.superview
            }
            if !chain.isEmpty {
                let line = name + " <- " + chain.joined(separator: " | ")
                Logger(subsystem: "hoopwise.mac", category: "glass").log("GLASSTRACE \(line, privacy: .public)")
            }
        }
        #endif
    }
}

extension UIView {
    @objc func hw_glassHideWhenShown() {
        hw_glassHideWhenShown()
        if !isHidden { isHidden = true }
    }
    @objc func hw_glassHideOnLayout() {
        hw_glassHideOnLayout()
        if !isHidden { isHidden = true }
    }
}

extension UIScrollView {
    @objc func hw_glassScrollMoved() {
        hw_glassScrollMoved()
        guard window != nil else { return }
        if !topEdgeEffect.isHidden { topEdgeEffect.isHidden = true }
    }
}

private var glassCellManagedKey: UInt8 = 0
private var glassCellHoverKey: UInt8 = 0

extension UICollectionViewListCell {
    /// A List row the system would paint as an opaque slab becomes the pane
    /// (a grouped row) or nothing (a plain row), and lights up under the
    /// pointer. Rows the app gave their own background keep it.
    @objc func hw_glassCellLayout() {
        hw_glassCellLayout()
        guard var config = backgroundConfiguration, config.customView == nil else { return }
        let managed = objc_getAssociatedObject(self, &glassCellManagedKey) as? Int   // 1 grouped, 2 plain
        var kind = managed
        if kind == nil {
            let resolved = config.resolvedBackgroundColor(for: tintColor)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.9, r < 0.3 else { return }
            // Dark grey = a grouped row; black = a plain one.
            kind = r > 0.05 ? 1 : 2
            objc_setAssociatedObject(self, &glassCellManagedKey, kind, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hw_glassHover(_:))))
        }
        let hovered = (objc_getAssociatedObject(self, &glassCellHoverKey) as? Bool) ?? false
        let alpha: CGFloat = kind == 1 ? (hovered ? 0.13 : 0.07) : (hovered ? 0.07 : 0)
        let wanted = UIColor.white.withAlphaComponent(alpha)
        if config.backgroundColor != wanted {
            config.backgroundColor = wanted
            backgroundConfiguration = config
        }
    }

    @objc func hw_glassHover(_ hover: UIHoverGestureRecognizer) {
        let over = hover.state == .began || hover.state == .changed
        guard ((objc_getAssociatedObject(self, &glassCellHoverKey) as? Bool) ?? false) != over else { return }
        objc_setAssociatedObject(self, &glassCellHoverKey, over, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        setNeedsLayout()
    }
}

extension UINavigationController {
    @objc func hw_glassPush(_ controller: UIViewController, animated: Bool) {
        hw_glassPush(controller, animated: false)
        hw_showOnlyTheTopPage()
    }
    @objc func hw_glassPop(animated: Bool) -> UIViewController? {
        let popped = hw_glassPop(animated: false)
        hw_showOnlyTheTopPage()
        return popped
    }

    func hw_showOnlyTheTopPage() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOOPWISE_GLASS_TRACE"] == "1", viewControllers.count > 1 {
            var lines: [String] = []
            func walk(_ v: UIView, _ depth: Int) {
                guard depth < 9, !v.isHidden else { return }
                let a = v.backgroundColor?.cgColor.alpha ?? 0
                let layerA = v.layer.backgroundColor?.alpha ?? 0
                if a > 0.03 || layerA > 0.03 || v is UIVisualEffectView {
                    lines.append("d\(depth) \(type(of: v)) bg=\(String(format: "%.2f", a)) layer=\(String(format: "%.2f", layerA)) \(Int(v.frame.width))x\(Int(v.frame.height))")
                }
                for sub in v.subviews { walk(sub, depth + 1) }
            }
            walk(view, 0)
            Logger(subsystem: "hoopwise.mac", category: "glass").log("GLASSTREE \(lines.prefix(14).joined(separator: " | "), privacy: .public)")
        }
        #endif
        let top = topViewController
        for controller in viewControllers where controller.isViewLoaded {
            let hide = controller !== top
            if controller.view.isHidden != hide { controller.view.isHidden = hide }
        }
    }
}
