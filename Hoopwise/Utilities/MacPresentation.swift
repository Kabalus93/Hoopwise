import SwiftUI

// The Mac app is the iPad app (Mac Catalyst). Two presentation differences,
// asked for by Luther (November 2026): a popup opens at once — no slide-up —
// and it is sized to show its whole content instead of a short form sheet.
// On iPhone and iPad both are no-ops.

extension View {
    /// A sheet's size on the Mac: the large page size, tall enough for the
    /// whole content. Apply to the sheet's CONTENT.
    func macPopupSizing() -> some View {
        #if targetEnvironment(macCatalyst)
        presentationSizing(.page)
        #else
        self
        #endif
    }
}

/// Runs a state change that presents a sheet — without the slide-up
/// animation on the Mac, with the normal animation elsewhere.
@MainActor
func presentWithoutAnimationOnMac(_ change: () -> Void) {
    #if targetEnvironment(macCatalyst)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
    #else
    change()
    #endif
}
