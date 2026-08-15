import SwiftUI
import WidgetKit

@Observable
final class HomeViewModel {

    var context: CycleContext       = MockData.lutealContext
    /// HealthKit 授权与读数、更新周期上下文期间为 true
    var isLoadingHealthData         = false
    var usingMockData               = false
    /// 根据当前阶段生成的推荐问题，供助手 Tab 首屏展示
    var suggestedQuestions: [String] = []

    // 节气
    var currentSolarTerm: SolarTermInfo?
    var nextSolarTerm: SolarTermInfo?
    var daysUntilNextSolarTerm: Int = 0

    /// 当前周期阶段，用于节气养生建议叠加显示；无真实周期数据时为 nil
    var currentPhase: CyclePhase? {
        usingMockData ? nil : context.phase
    }

    private let healthKit = HealthKitManager.shared
    private let engine    = CyclePhaseEngine()
    private let solarTermEngine = SolarTermEngine()
    private var hasLoaded           = false
    private var isLoadingQuestions  = false
    private let appGroupID          = "group.com.cycleadvisor.shared"
    private let widgetContextKey    = "widget.context"

    /// - Parameter force: `true` 时忽略「已成功加载」门禁，用于用户主动刷新健康数据。
    @MainActor
    func load(force: Bool = false) async {
        guard !isLoadingHealthData else { return }

        if !force {
            guard !hasLoaded else { return }
        }
        // 强制刷新时重置推荐问题，下次切到助手 Tab 时按新周期阶段重建
        if force { suggestedQuestions = [] }

        await performHealthKitUpdate()
        loadSolarTerms()

        hasLoaded = true
        persistWidgetSnapshot()
    }

    /// 由助手 Tab 首次出现时调用，按当前周期阶段提供静态推荐问题。
    @MainActor
    func loadSuggestedQuestionsIfNeeded() async {
        guard suggestedQuestions.isEmpty, !isLoadingQuestions else { return }
        guard !usingMockData else { return }
        isLoadingQuestions = true
        defer { isLoadingQuestions = false }
        suggestedQuestions = buildSuggestedQuestions(for: context.phase)
    }

    private func loadSolarTerms() {
        let now = Date()
        let (current, next) = solarTermEngine.currentAndNext(on: now)
        currentSolarTerm = current
        nextSolarTerm = next
        daysUntilNextSolarTerm = solarTermEngine.daysUntilNext(from: now)
    }

    @MainActor
    private func performHealthKitUpdate() async {
        isLoadingHealthData = true
        defer { isLoadingHealthData = false }

        guard healthKit.isAvailable else {
            usingMockData = true
            hasLoaded = true
            return
        }

        do {
            try await healthKit.requestAuthorization()
        } catch {
            usingMockData = true
            hasLoaded = true
            return
        }

        async let metricsTask      = healthKit.fetchHealthMetrics()
        async let periodStartTask  = healthKit.fetchLastPeriodStart()
        async let cycleLengthTask  = healthKit.fetchAverageCycleLength()

        let (metrics, periodStart, cycleLength) = await (metricsTask, periodStartTask, cycleLengthTask)

        // 获取经期症状（与周期数据并行获取后再取症状，因为需要 periodStart）
        let symptoms = await healthKit.fetchMenstrualSymptoms(since: periodStart)

        if let periodStart {
            let base = engine.determinePhase(lastPeriodStart: periodStart, cycleLength: cycleLength)
            context = CycleContext(
                phase:          base.phase,
                dayInPhase:     base.dayInPhase,
                cycleDay:       base.cycleDay,
                avgCycleLength: base.avgCycleLength,
                healthMetrics:  metrics,
                menstrualSymptoms: symptoms,
                isPredicted:    base.isPredicted
            )
        } else {
            // 还没有经期数据（首次使用）— 保留 mock 阶段，但填入真实健康指标
            usingMockData = true
            context = CycleContext(
                phase:          context.phase,
                dayInPhase:     context.dayInPhase,
                cycleDay:       context.cycleDay,
                avgCycleLength: context.avgCycleLength,
                healthMetrics:  metrics,
                menstrualSymptoms: symptoms
            )
        }

        // 积累用户档案（身体信息 + 运动 + 周期历史）
        await accumulateUserProfile(context: context)
    }

    private func accumulateUserProfile(context: CycleContext) async {
        async let bodyInfo = healthKit.fetchBodyInfo()
        async let workoutStats = healthKit.fetchWorkoutStats()
        async let cycleLengths = healthKit.fetchHistoricalCycleLengths()
        async let periodDurations = healthKit.fetchPeriodDurations()

        let (body, workouts, cycles, periods) = await (bodyInfo, workoutStats, cycleLengths, periodDurations)

        UserProfileManager.shared.accumulate(
            context: context,
            bodyInfo: body,
            workoutStats: workouts,
            cycleLengths: cycles,
            periodDurations: periods
        )
    }

    private func persistWidgetSnapshot() {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            return
        }
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let encoder = JSONEncoder()
        guard let contextData = try? encoder.encode(context) else { return }

        defaults.set(contextData, forKey: widgetContextKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func buildSuggestedQuestions(for phase: CyclePhase) -> [String] {
        switch phase {
        case .menstrual:
            return [
                "今天怎么安排运动更舒服？",
                "经期饮食有什么简单注意点？",
                "如果疲惫感明显，我该怎么调整作息？"
            ]
        case .follicular:
            return [
                "卵泡期适合提高训练强度吗？",
                "今天饮食怎么搭配更有精力？",
                "这个阶段有哪些可以养成的小习惯？"
            ]
        case .ovulation:
            return [
                "排卵期运动需要注意什么？",
                "今天身体状态波动正常吗？",
                "我该怎么观察这个阶段的信号？"
            ]
        case .luteal:
            return [
                "黄体期情绪波动时可以怎么做？",
                "今天适合什么强度的运动？",
                "睡眠和饮食上有什么优先调整？"
            ]
        }
    }
}
