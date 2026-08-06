import WidgetKit
import SwiftUI

@main
struct SAMWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
        AttentionWidget()
        CadenceWidget()
        SessionLiveActivityWidget()
    }
}
