import Foundation

/// 备孕洞察协调器：汇集手表腕温 / 手动 BBT / 生命体征 / 症状 / 经期数据，
/// 运行 PregnancyInsightEngine 并发布结果给 UI。手表数据以 HealthKit 为唯一数据源，现读现算。
@Observable
final class ConceptionInsightManager {

    static let shared = ConceptionInsightManager()

    private(set) var insight: PregnancyInsight = .insufficient
    /// 近 14 天合并体温（供首页迷你趋势图）
    private(set) var recentTemperatures: [BasalTemperatureEntry] = []
    /// 近 3 天有手表腕温数据（决定是否需要晨间测温提醒）
    private(set) var hasWristCoverage = false
    /// 手表基线是否已建立（腕温数据 ≥ 14 天才参与判定）
    private(set) var wristBaselineReady = false

    private let healthKit = HealthKitManager.shared
    private let store = ConceptionStore.shared
    private let engine = PregnancyInsightEngine()
    private let phaseEngine = CyclePhaseEngine()
    private var lastPeriodStart: Date?

    private init() {}

    @MainActor
    func refresh() async {
        let isTryingToConceive = UserProfileManager.shared.profile.isTryingToConceive
        guard isTryingToConceive else {
            insight = .insufficient
            recentTemperatures = []
            hasWristCoverage = false
            ConceptionReminderScheduler.refresh(isTryingToConceive: false, hasWristCoverage: false, reminderEnabled: false)
            return
        }

        let reminderEnabled = UserDefaults.standard.bool(forKey: ConceptionReminderScheduler.enabledDefaultsKey)

        async let wristTask = healthKit.fetchWristTemperatureSeries(daysBack: 60)
        async let vitalsTask = healthKit.fetchDailyVitals(daysBack: 60)
        async let periodTask = healthKit.fetchLastPeriodStart()
        async let lengthTask = healthKit.fetchAverageCycleLength()
        async let hkSymptomsTask = healthKit.fetchPregnancySymptoms(daysBack: 60)

        let (wrist, vitals, periodStart, cycleLength, hkSymptoms) = await (
            wristTask, vitalsTask, periodTask, lengthTask, hkSymptomsTask
        )

        // HealthKit 症状并入统一症状库（去重由 store 保证）
        if !hkSymptoms.isEmpty {
            store.addSymptoms(hkSymptoms)
        }
        store.clearFeedbackIfNewPeriod(lastPeriodStart: periodStart)
        lastPeriodStart = periodStart

        // 手表基线未建立（佩戴 < 14 天）→ 腕温暂不参与判定，走手动 BBT 过渡
        wristBaselineReady = wrist.count >= 14
        let merged = store.mergedTemperatures(wrist: wristBaselineReady ? wrist : [])

        let expectedPeriod = periodStart.map {
            phaseEngine.nextPeriodDate(lastPeriodStart: $0, cycleLength: cycleLength)
        }

        insight = engine.evaluate(PregnancyInsightEngine.Input(
            temperatures: merged,
            vitals: vitals,
            symptoms: store.symptomRecords,
            lastPeriodStart: periodStart,
            expectedPeriodStart: expectedPeriod,
            referenceDate: Date(),
            testFeedback: store.testFeedback,
            dismissedUntil: store.dismissedUntil
        ))

        let calendar = Calendar.current
        let chartCutoff = calendar.date(byAdding: .day, value: -14, to: Date())!
        recentTemperatures = merged.filter { $0.date >= chartCutoff }

        let coverageCutoff = calendar.date(byAdding: .day, value: -3, to: Date())!
        hasWristCoverage = wrist.contains { $0.date >= coverageCutoff }
        ConceptionReminderScheduler.refresh(
            isTryingToConceive: true,
            hasWristCoverage: hasWristCoverage,
            reminderEnabled: reminderEnabled
        )
    }

    // MARK: - 验孕结果反馈

    @MainActor
    func recordPositive() {
        store.recordFeedback(.positive(date: Date()))
        Task { await refresh() }
    }

    @MainActor
    func recordNegative() {
        store.recordFeedback(.negative(date: Date(), cycleStart: lastPeriodStart))
        Task { await refresh() }
    }

    @MainActor
    func dismissPrompt() {
        store.dismissPrompt(forDays: 7)
        Task { await refresh() }
    }
}
