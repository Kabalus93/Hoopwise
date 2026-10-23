import Foundation
import UserNotifications

// MARK: - Notification cards (October 2026, Luther's design)
//
// Every Hoopwise notification carries a KIND and two lines — a bold headline
// and a detail line. The collapsed banner is iOS's own (title = headline,
// body = detail); pressing it opens the expanded card drawn by the
// HoopwiseNotifications content extension: the kind's gradient, "HOOPWISE"
// in tracked caps, the headline big and the detail under it. The extension
// reads only what is stamped here, so the app and the card cannot disagree.
//
// Member of the iOS app, HoopwiseMac (rule 1 — CyclePlanner stamps it) and
// the HoopwiseNotifications extension.

enum NotificationCard {

    enum Kind: String, CaseIterable {
        /// N minutes before a class (Profile → Session Reminders).
        case upcoming
        /// A class's start time.
        case started
        /// After Complete Session: review attendance.
        case completed
        /// A coach's own reminder.
        case reminder
        /// Two weeks before a cycle's target date.
        case nextCycle

        /// The category the content extension is registered for
        /// (HoopwiseNotifications/Info.plist lists every one).
        var categoryIdentifier: String { "HW_CARD_\(rawValue.uppercased())" }
    }

    static let kindKey = "hw.kind"
    static let headlineKey = "hw.headline"
    static let detailKey = "hw.detail"

    /// Stamps the content: title/body for the banner, kind + lines for the card.
    /// Existing userInfo (session ids, epochs) is kept.
    static func stamp(_ content: UNMutableNotificationContent, kind: Kind,
                      headline: String, detail: String) {
        content.title = headline
        content.body = detail
        content.categoryIdentifier = kind.categoryIdentifier
        content.threadIdentifier = "hoopwise.\(kind.rawValue)"
        var info = content.userInfo
        info[kindKey] = kind.rawValue
        info[headlineKey] = headline
        info[detailKey] = detail
        content.userInfo = info
    }

    /// Reads a delivered notification back. Falls back to its title/body so a
    /// notification scheduled by an older build still renders.
    static func read(_ content: UNNotificationContent) -> (kind: Kind, headline: String, detail: String) {
        let info = content.userInfo
        let kind = (info[kindKey] as? String).flatMap(Kind.init(rawValue:))
            ?? Kind.allCases.first { $0.categoryIdentifier == content.categoryIdentifier }
            ?? .reminder
        let headline = info[headlineKey] as? String ?? content.title
        let detail = info[detailKey] as? String ?? content.body
        return (kind, headline, detail)
    }

    /// "18:30" in the device's 24-hour style the coach reads everywhere else.
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
