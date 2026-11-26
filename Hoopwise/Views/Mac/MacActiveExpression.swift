//
//  MacActiveExpression.swift
//  Hoopwise
//
//  FULL EXPRESSION WHEN IT IS THE THING IN FRONT, RECEDING WHEN IT IS NOT
//  (26 Nov 2026, Luther, with two captures of macOS's desktop widgets: in
//  front they are solid and in full colour — photos, coloured calendars;
//  behind a window the same widgets drain to one tone and go translucent, so
//  the wallpaper carries them. "Bring that into Hoopwise on the Mac … not
//  shallow but a bit more considerate").
//
//  Two levels, one vocabulary:
//
//  · THE WINDOW. A Hoopwise window that is not the one being worked in
//    (another app is in front, or another Hoopwise window is) lets go of its
//    colour and thins out: photos, team colours, status greens and the blue
//    accent all drain toward the glass; the panes get thinner. Back in front,
//    everything returns. The drain is an overlay that exists only while the
//    window is behind, so the window pays nothing for it while in use.
//
//  · THE ITEM. In a list that has one thing open beside it (Athletes, Drills),
//    the open row is the one in full expression — a firmer pane, its photo or
//    symbol in colour, bright type — and the rows around it step back a
//    little. With nothing open, every row is at full expression: there is
//    nothing to step back from.
//
//  Mac only. iPhone and iPad are untouched.
//

import SwiftUI

private struct FilmWindowExpression: ViewModifier {
    @Environment(\.appearsActive) private var active

    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            content
                // Thinner: more of the glass (and the desktop) comes through.
                .opacity(active ? 1 : 0.8)
                .overlay {
                    if !active {
                        // Colour out, tone kept: the saturation of a grey laid
                        // over everything the window draws.
                        Color.gray
                            .blendMode(.saturation)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: active)
        } else {
            content
        }
    }
}

private struct FilmItemExpression: ViewModifier {
    let selected: Bool
    let anySelected: Bool
    @Environment(\.appearsActive) private var active

    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            let recede = anySelected && !selected
            content
                .saturation(recede ? 0.25 : 1)
                .opacity(recede ? 0.7 : 1)
                .animation(.easeOut(duration: 0.2), value: recede)
        } else {
            content
        }
    }
}

extension View {
    /// On a window's root: full expression in front, drained and thinner behind.
    func filmWindowExpression() -> some View { modifier(FilmWindowExpression()) }

    /// On a row of a list with something open beside it: the open row keeps
    /// its colour, the others step back.
    func filmItemExpression(selected: Bool, anySelected: Bool) -> some View {
        modifier(FilmItemExpression(selected: selected, anySelected: anySelected))
    }
}

extension FilmGlass {
    /// The pane of the one open item: firmer than a resting pane.
    static let fillSelected = Color.white.opacity(0.17)
}
