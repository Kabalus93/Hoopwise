import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI

/// The expanded card for every Hoopwise notification (October 2026, Luther's
/// design). The collapsed banner stays iOS's own; this is what a press shows.
/// Everything it draws comes from `NotificationCard.read`.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private var host: UIHostingController<NotificationCardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func didReceive(_ notification: UNNotification) {
        let card = NotificationCard.read(notification.request.content)
        let root = NotificationCardView(kind: card.kind, headline: card.headline, detail: card.detail)
        if let host {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
            self.host = host
        }
        let width = view.bounds.width > 0 ? view.bounds.width : 360
        preferredContentSize = CGSize(width: width, height: 156)
    }
}

struct NotificationCardView: View {
    let kind: NotificationCard.Kind
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HOOPWISE")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(1.2)
                Spacer()
                Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "现在" : "now")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 10)

            Text(headline)
                .font(.system(size: 30, weight: .heavy))
                .kerning(-0.4)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(CardGradient(kind: kind))
    }
}

/// One deep → bright gradient per kind, darkest corner top-left, the bright
/// bloom bottom-right — the same build as the Live Activity cards.
struct CardGradient: View {
    let kind: NotificationCard.Kind

    private var stops: (deep: Color, mid: Color, bloom: Color) {
        switch kind {
        case .upcoming:  return (Color(hex: 0x2A0E8F), Color(hex: 0x5B21D9), Color(hex: 0xB45CFF))
        case .started:   return (Color(hex: 0x0A2A8A), Color(hex: 0x0E6FD8), Color(hex: 0x14E0C8))
        case .completed: return (Color(hex: 0x063A2E), Color(hex: 0x0B6B4F), Color(hex: 0x1BC77A))
        case .reminder:  return (Color(hex: 0x8A3A06), Color(hex: 0xD9630F), Color(hex: 0xFFB020))
        case .nextCycle: return (Color(hex: 0xE2470F), Color(hex: 0xD61F45), Color(hex: 0xB0104F))
        }
    }

    var body: some View {
        let s = stops
        ZStack {
            LinearGradient(colors: [s.deep, s.mid], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [s.bloom.opacity(0.9), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 240)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
