import Foundation

/// 经期预测：上次经期开始日 + 平均周期长度推算。纯函数，无 HealthKit 依赖，iPhone / Watch 共用。
struct PeriodPrediction: Equatable {
    enum State: Equatable {
        case upcoming(days: Int)   // 还有 X 天
        case today                 // 预计今天来潮
        case inPeriod(day: Int)    // 经期第 X 天
        case overdue(days: Int)    // 可能推迟了 X 天
    }

    let predictedDate: Date
    let state: State

    static func make(lastPeriodStart: Date, cycleLength: Int, isInPeriod: Bool, periodDay: Int,
                     today: Date = .now, calendar: Calendar = .current) -> PeriodPrediction {
        let nextStart = calendar.date(byAdding: .day, value: cycleLength, to: lastPeriodStart)!
        let startToday = calendar.startOfDay(for: today)
        let startNext = calendar.startOfDay(for: nextStart)
        let diff = calendar.dateComponents([.day], from: startToday, to: startNext).day ?? 0

        let state: State
        if isInPeriod {
            state = .inPeriod(day: max(1, periodDay))
        } else if diff > 0 {
            state = .upcoming(days: diff)
        } else if diff == 0 {
            state = .today
        } else {
            state = .overdue(days: -diff)
        }
        return PeriodPrediction(predictedDate: startNext, state: state)
    }

    /// 按当前 Locale 格式化预测日期（如 "9月12日" / "Sep 12"）
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    /// 主页周期模块与 Watch 速览共用的一行文案
    var text: String {
        switch state {
        case .upcoming(let days):
            return String(format: String(localized: "home.prediction.upcoming %@ %lld"),
                          Self.dateText(predictedDate), Int64(days))
        case .today:
            return String(localized: "home.prediction.today")
        case .inPeriod(let day):
            return String(format: String(localized: "home.prediction.in_period %lld"), Int64(day))
        case .overdue(let days):
            return String(format: String(localized: "home.prediction.overdue %lld"), Int64(days))
        }
    }
}
