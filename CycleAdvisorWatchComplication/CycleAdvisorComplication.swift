import WidgetKit
import SwiftUI

struct CycleAdvisorComplicationEntry: TimelineEntry {
    let date: Date
}

struct CycleAdvisorComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CycleAdvisorComplicationEntry {
        CycleAdvisorComplicationEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CycleAdvisorComplicationEntry) -> Void) {
        completion(CycleAdvisorComplicationEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CycleAdvisorComplicationEntry>) -> Void) {
        completion(Timeline(entries: [CycleAdvisorComplicationEntry(date: Date())], policy: .never))
    }
}

struct CycleAdvisorComplicationEntryView: View {
    var entry: CycleAdvisorComplicationEntry

    var body: some View {
        Text("🌙")
    }
}

@main
struct CycleAdvisorComplication: Widget {
    let kind: String = "CycleAdvisorComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CycleAdvisorComplicationProvider()) { entry in
            CycleAdvisorComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("CycleAdvisor")
        .description("Current cycle phase at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
