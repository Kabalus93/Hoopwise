import SwiftUI
import Combine

/// "Add a make-up class?" — asked when a cancelled or skipped class pushed
/// its phase's plans on and the last one has no class (SessionPlanShift).
///
/// Attached to the app's root AND to screens shown as sheets (the session
/// page, the attention sheet): an alert on a view underneath a sheet is never
/// shown, so only the most recently appeared host presents it.
struct MakeUpOfferAlert: ViewModifier {
    @EnvironmentObject var dataManager: DataManager
    @ObservedObject private var hosts = MakeUpOfferHosts.shared
    @State private var token = UUID()

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    func body(content: Content) -> some View {
        content
            .onAppear { hosts.push(token) }
            .onDisappear { hosts.remove(token) }
            .alert(isChinese ? "要补一节课吗？" : "Add a make-up class?",
                   isPresented: Binding(
                    get: { dataManager.makeUpOffer != nil && hosts.top == token },
                    set: { if !$0 { dataManager.declineMakeUp() } }),
                   presenting: dataManager.makeUpOffer) { offer in
                Button(isChinese ? "添加补课" : "Add make-up class") {
                    dataManager.acceptMakeUp(offer)
                }
                Button(isChinese ? "不用，去掉最后一个计划" : "No, drop the last plan", role: .cancel) {
                    dataManager.declineMakeUp()
                }
            } message: { offer in
                Text(message(offer))
            }
    }

    private func message(_ offer: MakeUpOffer) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isChinese ? "zh_CN" : "en_GB")
        f.dateFormat = isChinese ? "M月d日 EEE HH:mm" : "EEE d MMM, HH:mm"
        let when = f.string(from: offer.start)
        return isChinese
            ? "\(offer.className) 的训练计划已顺延一节课。在 \(when) 加一节补课，最后一个计划就不会丢。"
            : "\(offer.className)'s plans moved on by one class. Add a make-up class on \(when) so the last plan isn't lost."
    }
}

/// Which views can present the offer, most recent last.
final class MakeUpOfferHosts: ObservableObject {
    static let shared = MakeUpOfferHosts()
    @Published private(set) var stack: [UUID] = []
    var top: UUID? { stack.last }
    func push(_ id: UUID) { stack.removeAll { $0 == id }; stack.append(id) }
    func remove(_ id: UUID) { stack.removeAll { $0 == id } }
}

extension View {
    func makeUpOfferAlert() -> some View { modifier(MakeUpOfferAlert()) }
}
