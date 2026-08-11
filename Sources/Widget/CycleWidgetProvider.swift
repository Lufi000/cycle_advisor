import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct CycleWidgetEntry: TimelineEntry {
    let date: Date
    let context: CycleContext
    let suggestion: Suggestion?
}

// MARK: - Timeline Provider

struct CycleWidgetProvider: TimelineProvider {

    typealias Entry = CycleWidgetEntry
    private let appGroupID = "group.com.cycleadvisor.shared"
    private let widgetContextKey = "widget.context"

    func placeholder(in context: Context) -> CycleWidgetEntry {
        CycleWidgetEntry(
            date: .now,
            context: MockData.follicularContext,
            suggestion: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CycleWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CycleWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh at next midnight so phase label stays accurate
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let nextRefresh = Calendar.current.startOfDay(for: tomorrow)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: - Private

    private func currentEntry() -> CycleWidgetEntry {
        let fallback = CycleWidgetEntry(
            date: .now,
            context: MockData.lutealContext,
            suggestion: nil
        )

        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            return fallback
        }
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let contextData = defaults.data(forKey: widgetContextKey)
        else {
            return fallback
        }

        let decoder = JSONDecoder()
        guard let context = try? decoder.decode(CycleContext.self, from: contextData) else {
            return fallback
        }

        return CycleWidgetEntry(date: .now, context: context, suggestion: nil)
    }
}
