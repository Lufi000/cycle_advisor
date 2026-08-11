import Foundation

/// 周期阶段识别引擎
///
/// 基于最近一次经期开始日期和平均周期长度，推算当前所处的周期阶段。
/// 四阶段模型：经期 → 卵泡期 → 排卵期 → 黄体期
struct CyclePhaseEngine {

    /// 各阶段占周期的比例（基于医学文献的标准分布）
    struct PhaseRatios {
        let menstrual: Double   // 经期
        let follicular: Double  // 卵泡期
        let ovulation: Double   // 排卵期
        // 黄体期 = 剩余部分（通常固定 ~14 天）

        static let standard = PhaseRatios(
            // 注：这里的"卵泡期"指经后期（经期结束→排卵前），
            // 医学严格定义的卵泡期（月经第 1 天→排卵）约 14 天，包含经期。
            menstrual: 0.179,   // ~5 天 / 28 天
            follicular: 0.25,   // 比例参考；实际天数 = 周期 - 经期 - 排卵期 - 黄体期（28 天周期约 6 天）
            ovulation: 0.107    // ~3 天 / 28 天
        )
    }

    let ratios: PhaseRatios

    init(ratios: PhaseRatios = .standard) {
        self.ratios = ratios
    }

    // MARK: - Phase Duration Calculation

    /// 计算给定周期长度下各阶段的天数
    func phaseDurations(for cycleLength: Int) -> PhaseDurations {
        // 黄体期相对固定（12-16 天），经期和卵泡期随周期长度变化
        let lutealDays = min(max(cycleLength - 14, 10), 16) // 黄体期：14 天左右，但限制在 10-16 天
        let menstrualDays = max(Int(round(Double(cycleLength) * ratios.menstrual)), 3) // 至少 3 天
        let ovulationDays = max(Int(round(Double(cycleLength) * ratios.ovulation)), 2) // 至少 2 天

        // 卵泡期 = 周期长度 - 经期 - 排卵期 - 黄体期
        let follicularDays = max(cycleLength - menstrualDays - ovulationDays - lutealDays, 2) // 至少 2 天

        return PhaseDurations(
            menstrual: menstrualDays,
            follicular: follicularDays,
            ovulation: ovulationDays,
            luteal: lutealDays
        )
    }

    // MARK: - Phase Determination

    /// 根据经期开始日期和周期长度，计算指定日期的周期阶段
    func determinePhase(
        lastPeriodStart: Date,
        cycleLength: Int = 28,
        on date: Date = .now
    ) -> CycleContext {
        let calendar = Calendar.current
        let cycleDay = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastPeriodStart), to: calendar.startOfDay(for: date)).day! + 1

        let durations = phaseDurations(for: cycleLength)

        if cycleDay > cycleLength {
            // 超过一个周期但用户未录入新经期 → 停在黄体期末尾，标记为待录入
            return CycleContext(
                phase: .luteal,
                dayInPhase: durations.luteal,
                cycleDay: cycleLength,
                avgCycleLength: cycleLength,
                healthMetrics: .empty,
                isPredicted: true
            )
        }

        let (phase, dayInPhase) = phaseForDay(cycleDay, durations: durations)

        return CycleContext(
            phase: phase,
            dayInPhase: dayInPhase,
            cycleDay: cycleDay,
            avgCycleLength: cycleLength,
            healthMetrics: .empty,
            isPredicted: false
        )
    }

    /// 根据周期中的第几天确定阶段
    func phaseForDay(_ day: Int, durations: PhaseDurations) -> (phase: CyclePhase, dayInPhase: Int) {
        let menstrualEnd = durations.menstrual
        let follicularEnd = menstrualEnd + durations.follicular
        let ovulationEnd = follicularEnd + durations.ovulation

        if day <= menstrualEnd {
            return (.menstrual, day)
        } else if day <= follicularEnd {
            return (.follicular, day - menstrualEnd)
        } else if day <= ovulationEnd {
            return (.ovulation, day - follicularEnd)
        } else {
            return (.luteal, day - ovulationEnd)
        }
    }

    /// 计算下一次经期的预计开始日期
    func nextPeriodDate(lastPeriodStart: Date, cycleLength: Int = 28) -> Date {
        Calendar.current.date(byAdding: .day, value: cycleLength, to: lastPeriodStart)!
    }

    /// 计算距离下一次经期还有几天
    func daysUntilNextPeriod(lastPeriodStart: Date, cycleLength: Int = 28, from date: Date = .now) -> Int {
        let nextStart = nextPeriodDate(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        let calendar = Calendar.current
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: nextStart)).day ?? 0)
    }
}

// MARK: - Phase Durations

struct PhaseDurations: Equatable {
    let menstrual: Int
    let follicular: Int
    let ovulation: Int
    let luteal: Int

    var total: Int { menstrual + follicular + ovulation + luteal }

    /// 阶段起始天数（周期内第几天开始）
    func startDay(for phase: CyclePhase) -> Int {
        switch phase {
        case .menstrual:  return 1
        case .follicular: return menstrual + 1
        case .ovulation:  return menstrual + follicular + 1
        case .luteal:     return menstrual + follicular + ovulation + 1
        }
    }

    func duration(for phase: CyclePhase) -> Int {
        switch phase {
        case .menstrual:  return menstrual
        case .follicular: return follicular
        case .ovulation:  return ovulation
        case .luteal:     return luteal
        }
    }
}
