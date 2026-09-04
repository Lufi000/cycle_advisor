import Foundation
import SwiftUI

/// Watch 端周期数据：直接读手表本地 HealthKit（经期数据经 iCloud 健康同步到手表），
/// 无 WatchConnectivity（spec §4.1）。
@Observable
final class WatchCycleViewModel {
    private(set) var context: CycleContext?
    private(set) var prediction: PeriodPrediction?
    private(set) var hasNoData = false

    func load() async {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAvailable else { hasNoData = true; return }
        try? await healthKit.requestAuthorization()

        async let periodStartTask = healthKit.fetchLastPeriodStart()
        async let cycleLengthTask = healthKit.fetchAverageCycleLength()
        guard let lastPeriodStart = await periodStartTask else {
            hasNoData = true
            return
        }
        let cycleLength = await cycleLengthTask
        let base = CyclePhaseEngine().determinePhase(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        let isInPeriod = base.phase == .menstrual && !base.isPredicted
        context = CycleContext(
            phase: base.phase,
            dayInPhase: base.dayInPhase,
            cycleDay: base.cycleDay,
            avgCycleLength: base.avgCycleLength,
            healthMetrics: .empty,
            isPredicted: base.isPredicted
        )
        prediction = PeriodPrediction.make(
            lastPeriodStart: lastPeriodStart,
            cycleLength: cycleLength,
            isInPeriod: isInPeriod,
            periodDay: base.cycleDay
        )
    }
}
