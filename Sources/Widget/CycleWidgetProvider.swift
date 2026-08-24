import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct CycleWidgetEntry: TimelineEntry {
    let date: Date
    let context: CycleContext
}

// MARK: - Timeline Provider

struct CycleWidgetProvider: TimelineProvider {

    typealias Entry = CycleWidgetEntry
    private let appGroupID = "group.com.cycleadvisor.shared"
    private let widgetContextKey = "widget.context"
    private let widgetAnchorDateKey = "widget.anchor.date"
    private let widgetAnchorCycleLengthKey = "widget.anchor.cycleLength"
    private let engine = CyclePhaseEngine()

    func placeholder(in context: Context) -> CycleWidgetEntry {
        CycleWidgetEntry(
            date: .now,
            context: MockData.follicularContext
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
            context: MockData.lutealContext
        )

        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            return fallback
        }
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let contextData = defaults.data(forKey: widgetContextKey)
        else {
            return fallback
        }

        guard let storedContext = try? JSONDecoder().decode(CycleContext.self, from: contextData) else {
            return fallback
        }

        // 用「最近一次经期开始日期 + 平均周期长度」按当前日期重新推算阶段，
        // 避免 Widget 一直停留在 App 上次写入的旧阶段（即使几天没打开 App 也会随日期推进）。
        let anchorInterval = defaults.double(forKey: widgetAnchorDateKey)
        let anchorCycleLength = defaults.integer(forKey: widgetAnchorCycleLengthKey)
        let context: CycleContext
        if anchorInterval > 0, anchorCycleLength > 0 {
            let lastPeriodStart = Date(timeIntervalSince1970: anchorInterval)
            context = refreshedContext(
                from: storedContext,
                lastPeriodStart: lastPeriodStart,
                cycleLength: anchorCycleLength
            )
        } else {
            context = storedContext
        }

        return CycleWidgetEntry(date: .now, context: context)
    }

    /// 与 App 内 performHealthKitUpdate 相同的阶段推算逻辑；
    /// 健康指标与症状沿用 App 最近一次快照，避免 Widget 端重复请求 HealthKit。
    private func refreshedContext(
        from stored: CycleContext,
        lastPeriodStart: Date,
        cycleLength: Int
    ) -> CycleContext {
        let base = engine.determinePhase(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength, on: .now)
        return CycleContext(
            phase: base.phase,
            dayInPhase: base.dayInPhase,
            cycleDay: base.cycleDay,
            avgCycleLength: base.avgCycleLength,
            healthMetrics: stored.healthMetrics,
            menstrualSymptoms: stored.menstrualSymptoms,
            isPredicted: base.isPredicted
        )
    }
}
