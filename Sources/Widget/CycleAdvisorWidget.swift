import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

@main
struct CycleAdvisorWidgetBundle: WidgetBundle {
    var body: some Widget {
        CycleAdvisorWidget()
    }
}

// MARK: - Widget Definition

struct CycleAdvisorWidget: Widget {
    let kind: String = "com.cycleadvisor.app.widget.cycle"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CycleWidgetProvider()) { entry in
            CycleWidgetEntryView(entry: entry)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName(Text("widget.display_name"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
