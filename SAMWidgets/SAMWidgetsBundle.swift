//
//  SAMWidgetsBundle.swift
//  SAMWidgets
//
//  Created by Luther Mutombo on 1/8/26.
//

import WidgetKit
import SwiftUI

@main
struct SAMWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SAMWidgets()
        SAMWidgetsControl()
        SessionLiveActivityWidget()
    }
}
