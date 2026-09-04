import WidgetKit
import SwiftUI

struct CycleComplicationEntry: TimelineEntry {
    let date: Date
    let phaseEmoji: String
    let phaseName: String
    let daysLeft: Int?
}

struct CycleComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CycleComplicationEntry {
        CycleComplicationEntry(date: .now, phaseEmoji: "🌱", phaseName: "", daysLeft: 8)
    }
    func getSnapshot(in context: Context, completion: @escaping (CycleComplicationEntry) -> Void) {
        Task { completion(await loadEntry()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CycleComplicationEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            // 每日刷新：下一次 timeline 在明天 0 点后
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
                                                 to: Calendar.current.startOfDay(for: .now))!
            completion(Timeline(entries: [entry], policy: .after(tomorrow)))
        }
    }

    private func loadEntry() async -> CycleComplicationEntry {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAvailable,
              let lastPeriodStart = await healthKit.fetchLastPeriodStart() else {
            return CycleComplicationEntry(date: .now, phaseEmoji: "🌙", phaseName: "", daysLeft: nil)
        }
        let cycleLength = await healthKit.fetchAverageCycleLength()
        let engine = CyclePhaseEngine()
        let base = engine.determinePhase(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        let daysLeft = engine.daysUntilNextPeriod(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        return CycleComplicationEntry(date: .now, phaseEmoji: base.phase.emoji,
                                      phaseName: base.phase.displayName, daysLeft: daysLeft)
    }
}

struct CycleComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: CycleComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(entry.phaseEmoji)
                    if let days = entry.daysLeft {
                        Text("\(days)").font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
            }
        case .accessoryCorner:
            Text(entry.phaseEmoji + (entry.daysLeft.map { " \($0)" } ?? ""))
        default: // accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.phaseEmoji + " " + entry.phaseName).font(.headline)
                if let days = entry.daysLeft {
                    Text(String(format: String(localized: "watch.complication.days_left %lld"), Int64(days)))
                        .font(.caption)
                }
            }
        }
    }
}

@main
struct CycleAdvisorComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CycleAdvisorComplication", provider: CycleComplicationProvider()) { entry in
            CycleComplicationView(entry: entry)
        }
        .configurationDisplayName("CycleAdvisor")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
