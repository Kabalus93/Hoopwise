//
//  SAMWidgetsLiveActivity.swift
//  SAMWidgets
//
//  Created by Luther Mutombo on 1/8/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SAMWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SAMWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SAMWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SAMWidgetsAttributes {
    fileprivate static var preview: SAMWidgetsAttributes {
        SAMWidgetsAttributes(name: "World")
    }
}

extension SAMWidgetsAttributes.ContentState {
    fileprivate static var smiley: SAMWidgetsAttributes.ContentState {
        SAMWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SAMWidgetsAttributes.ContentState {
         SAMWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SAMWidgetsAttributes.preview) {
   SAMWidgetsLiveActivity()
} contentStates: {
    SAMWidgetsAttributes.ContentState.smiley
    SAMWidgetsAttributes.ContentState.starEyes
}
