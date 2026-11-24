import SwiftUI

// ONE GLASS (25 Nov 2026, Luther, judging the first Mac build: some cards
// were solid navy, others see-through — "two apps"; then his references:
// panes of real frosted glass with a fine light edge, light type, quiet
// controls, and macOS's own dark widget panes).
//
// On the Mac the system's Liquid Glass (`.glassEffect`) cannot sample what is
// behind a transparent window, so it rendered as an opaque navy slab. Every
// pane in the app therefore goes through `.filmGlass(…)`: off the Mac it IS
// `.glassEffect(…)`, unchanged; on the Mac it is the film room's pane — a
// thin veil of white over the window's frost with a hairline edge that
// catches the light at the top-left.

enum FilmGlass {
    /// The veil a pane lays over the window's frost.
    static let fill = Color.white.opacity(0.07)
    /// A pane under the pointer or pressed.
    static let fillActive = Color.white.opacity(0.13)
    /// The hairline: brighter where the light comes from.
    static let edge = LinearGradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0.07), Color.white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct FilmGlassPane<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            content
                .background(shape.fill(FilmGlass.fill))
                .overlay(shape.stroke(FilmGlass.edge, lineWidth: 1).allowsHitTesting(false))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }
}

extension View {
    /// The app's glass: the system's Liquid Glass on iPhone and iPad, the
    /// film room's pane on the Mac.
    func filmGlass(_ glass: Glass = .regular, in shape: some Shape = Capsule()) -> some View {
        modifier(FilmGlassPane(glass: glass, shape: shape))
    }
}

// MATERIALS. A SwiftUI Material blurs what is behind it INSIDE the window; a
// transparent Mac window has nothing there, so every material came out as an
// opaque black slab. On the Mac they are the pane's veil; elsewhere the
// system's materials, unchanged.
extension ShapeStyle where Self == AnyShapeStyle {
    static var filmMaterial: AnyShapeStyle {
        FilmRoom.isOn ? AnyShapeStyle(FilmGlass.fill) : AnyShapeStyle(Material.regular)
    }
    static var filmThinMaterial: AnyShapeStyle {
        FilmRoom.isOn ? AnyShapeStyle(FilmGlass.fill) : AnyShapeStyle(Material.thin)
    }
    static var filmUltraThinMaterial: AnyShapeStyle {
        FilmRoom.isOn ? AnyShapeStyle(FilmGlass.fill) : AnyShapeStyle(Material.ultraThin)
    }
}
