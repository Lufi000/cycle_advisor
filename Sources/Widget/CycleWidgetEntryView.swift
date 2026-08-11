import SwiftUI
import WidgetKit

struct CycleWidgetEntryView: View {
    let entry: CycleWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            CycleSmallWidgetView(entry: entry)
        case .systemMedium:
            CycleMediumWidgetView(entry: entry)
        default:
            CycleSmallWidgetView(entry: entry)
        }
    }
}
