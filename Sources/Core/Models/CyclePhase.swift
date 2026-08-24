import Foundation
import SwiftUI

// MARK: - Cycle Phase

enum CyclePhase: String, Codable, CaseIterable {
    case menstrual   // 经期
    case follicular  // 卵泡期
    case ovulation   // 排卵期
    case luteal      // 黄体期

    var displayName: String {
        switch self {
        case .menstrual:  return String(localized: "phase.menstrual")
        case .follicular: return String(localized: "phase.follicular")
        case .ovulation:  return String(localized: "phase.ovulation")
        case .luteal:     return String(localized: "phase.luteal")
        }
    }

    var description: String {
        switch self {
        case .menstrual:  return String(localized: "phase.menstrual.desc")
        case .follicular: return String(localized: "phase.follicular.desc")
        case .ovulation:  return String(localized: "phase.ovulation.desc")
        case .luteal:     return String(localized: "phase.luteal.desc")
        }
    }

    /// 节气养生建议的阶段性叠加提示
    var wellnessOverlay: String {
        switch self {
        case .menstrual:  return String(localized: "phase.menstrual.overlay")
        case .follicular: return String(localized: "phase.follicular.overlay")
        case .ovulation:  return String(localized: "phase.ovulation.overlay")
        case .luteal:     return String(localized: "phase.luteal.overlay")
        }
    }

    var color: Color {
        switch self {
        case .menstrual:  return Theme.phaseMenstrual
        case .follicular: return Theme.phaseFollicular
        case .ovulation:  return Theme.phaseOvulation
        case .luteal:     return Theme.phaseLuteal
        }
    }

    var emoji: String {
        switch self {
        case .menstrual:  return "🌙"
        case .follicular: return "🌱"
        case .ovulation:  return "🌸"
        case .luteal:     return "🍂"
        }
    }

    /// 该阶段在标准 28 天周期中的默认天数
    var defaultDuration: Int {
        switch self {
        case .menstrual:  return 5
        case .follicular: return 7
        case .ovulation:  return 3
        case .luteal:     return 13
        }
    }
}

// MARK: - Cycle Context

struct CycleContext: Codable, Equatable {
    let phase: CyclePhase
    let dayInPhase: Int
    let cycleDay: Int
    let avgCycleLength: Int
    let healthMetrics: HealthMetrics
    /// 经期相关症状与出血量
    var menstrualSymptoms: MenstrualSymptoms = .empty
    /// 当前阶段是否为推算（非本周期实际记录）。
    /// 当距离上次经期超过一个周期长度时，后续周期均为推算。
    var isPredicted: Bool = false

    /// 周期进度（0.0 ~ 1.0）
    var cycleProgress: Double {
        Double(cycleDay) / Double(avgCycleLength)
    }
}

// MARK: - Trend

enum Trend: String, Codable, Equatable {
    case rising
    case stable
    case declining

    var symbol: String {
        switch self {
        case .rising:    return "↗"
        case .stable:    return "→"
        case .declining: return "↘"
        }
    }
}

// MARK: - Health Metrics

struct HealthMetrics: Codable, Equatable {
    // HRV & 心率
    var hrvCurrent: Double?
    var hrvWeeklyAvg: Double?
    var hrvTrend: Trend?
    var restingHR: Double?

    /// 今日日照时间累计（分钟），来自 HealthKit Time in Daylight
    var daylightMinutes: Double?
    var daylightTrend: Trend?

    /// 今日 Apple 锻炼分钟（圆环运动时间）
    var exerciseMinutes: Int?
    var exerciseTrend: Trend?

    /// 昨夜/最近一次睡眠总时长（小时），来自 HealthKit Sleep Analysis
    var sleepHours: Double?
    var sleepTrend: Trend?

    /// 今日饮水量（毫升），来自 HealthKit Dietary Water
    var waterMilliliters: Double?

    /// 近 7 天正念/放松记录总时长（分钟），来自 HealthKit Mindful Session
    var mindfulMinutesWeekly: Double?

    // 活动
    var activeCalories: Double?
    var steps: Int?
    var activityTrend: Trend?

    static let empty = HealthMetrics()

    /// 格式化日照时间。首页健康卡统一以分钟展示。
    var formattedDaylightDuration: String? {
        guard let m = daylightMinutes else { return nil }
        if m <= 0 { return String(localized: "unit.duration.minute_zero") }
        return String(format: String(localized: "unit.duration.minute %lld"), Int64(m.rounded()))
    }

    /// 格式化锻炼时长。首页健康卡统一以分钟展示。
    var formattedExerciseDuration: String? {
        guard let ex = exerciseMinutes else { return nil }
        if ex == 0 { return String(localized: "unit.duration.minute_zero") }
        return String(format: String(localized: "unit.duration.minute %lld"), Int64(ex))
    }

    /// 格式化睡眠时长。prompt 使用中文，不经 UI 本地化。
    var formattedSleepDurationForPrompt: String? {
        guard let sleepHours else { return nil }
        if sleepHours <= 0 { return nil }
        let totalMinutes = Int((sleepHours * 60.0).rounded()).roundedToNearestFive()
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours <= 0 { return "\(minutes)分钟" }
        if minutes <= 0 { return "\(hours)小时" }
        return "\(hours)小时\(minutes)分钟"
    }

    /// 格式化睡眠时长。首页健康卡与助手页标签统一以本地化文案展示。
    var formattedSleepDuration: String? {
        guard let sleepHours else { return nil }
        if sleepHours <= 0 { return String(localized: "unit.duration.minute_zero") }
        let totalMinutes = Int((sleepHours * 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours <= 0 {
            return String(format: String(localized: "unit.duration.minute %lld"), Int64(minutes))
        }
        if minutes <= 0 {
            return String(format: String(localized: "unit.duration.hour %lld"), Int64(hours))
        }
        return String(format: String(localized: "unit.duration.hour_minute %lld %lld"), Int64(hours), Int64(minutes))
    }

    /// 格式化饮水量。prompt 使用中文，不经 UI 本地化。
    var formattedWaterIntakeForPrompt: String? {
        guard let waterMilliliters else { return nil }
        if waterMilliliters <= 0 { return "0毫升" }
        return "\(Int(waterMilliliters.rounded()))毫升"
    }

    /// 格式化正念时长。prompt 使用中文，不经 UI 本地化。
    var formattedMindfulDurationForPrompt: String? {
        guard let mindfulMinutesWeekly else { return nil }
        if mindfulMinutesWeekly <= 0 { return "0分钟" }
        return "\(Int(mindfulMinutesWeekly.rounded()))分钟"
    }

    /// 格式化步数。保持完整步数，避免把 1700 步显示成 1.7 千步 / 1.7k。
    var formattedSteps: String? {
        guard let steps else { return nil }
        return String(format: String(localized: "unit.steps.count %lld"), Int64(steps))
    }
}

private extension Int {
    func roundedToNearestFive() -> Int {
        Int((Double(self) / 5.0).rounded() * 5.0)
    }
}
