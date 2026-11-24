import SwiftUI

// PUSHED PAGES ON THE GLASS (25 Nov 2026). SwiftUI paints an opaque system
// background behind every page a NavigationStack pushes — on the Mac's glass
// window that made every inner page a black slab while the pages above it
// were glass. A pushed page says `containerBackground(.clear, for:
// .navigation)` to stay clear, and it has to be said per destination.
//
// Rather than touching every link, the app's `NavigationLink` is this thin
// wrapper around SwiftUI's on the Mac (and in simulator DEBUG builds, so the
// UI tests exercise it): same links, their destinations marked clear when the
// film room is on. iPhone and iPad release builds use SwiftUI's own type.

struct FilmRoomDestination: ViewModifier {
    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content
        }
    }
}

extension View {
    /// A page's background: the system's grouped background off the Mac; on
    /// the Mac nothing at all — the window's glass — also when it is pushed.
    func filmRoomPage() -> some View {
        background(FilmRoomPageBackground().ignoresSafeArea())
            .modifier(FilmRoomDestination())
    }
}

#if targetEnvironment(macCatalyst) || (DEBUG && targetEnvironment(simulator))
struct NavigationLink<Label: View, Destination: View>: View {
    private let destination: Destination
    private let label: Label

    init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        SwiftUI.NavigationLink(destination: destination.modifier(FilmRoomDestination())) { label }
    }
}

extension NavigationLink where Label == Text {
    init(_ title: String, destination: Destination) {
        self.init(destination: destination) { Text(title) }
    }
}
#endif
