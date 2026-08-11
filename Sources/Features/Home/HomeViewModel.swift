import SwiftUI
import WidgetKit

enum SuggestionDataSource {
    case ai
    case fallback
}

@Observable
final class HomeViewModel {

    var context: CycleContext       = MockData.lutealContext
    var suggestions: SuggestionSet  = .empty(phase: MockData.lutealContext.phase)
    /// HealthKit 授权与读数、更新周期上下文期间为 true（与建议生成独立）
    var isLoadingHealthData         = false
    /// AI 生成首页建议期间为 true
    var isLoadingSuggestions        = false
    var usingMockData               = false
    var suggestionDataSource: SuggestionDataSource = .fallback
    var suggestionErrorMessage      = ""
    /// AI 根据当前阶段生成的推荐问题，供助手 Tab 首屏展示
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
    private let widgetSuggestionsKey = "widget.suggestions"

    /// - Parameter force: `true` 时忽略「已成功加载」门禁，用于用户主动刷新健康数据。
    @MainActor
    func load(force: Bool = false) async {
        guard !isLoadingHealthData else { return }

        if isLoadingSuggestions {
            if force {
                await performHealthKitUpdate()
                persistWidgetSnapshot()
            }
            return
        }

        // 首次加载后，若当前是回退结果，允许后续再次触发自动重试；`force` 时始终重拉
        if !force {
            guard !hasLoaded || suggestionDataSource == .fallback else { return }
        }
        // 强制刷新时重置推荐问题，下次切到助手 Tab 时懒加载新版本
        if force { suggestedQuestions = [] }

        await performHealthKitUpdate()
        loadSolarTerms()

        if suggestions.suggestions.isEmpty {
            suggestions = .empty(phase: context.phase)
        }

        guard BillingManager.shared.consumeSuggestionRefreshIfAvailable() else {
            suggestionDataSource = .fallback
            suggestionErrorMessage = String(localized: "billing.suggestion.quota_exhausted")
            hasLoaded = true
            persistWidgetSnapshot()
            return
        }

        // 首页建议生成（推荐问题移至助手 Tab 懒加载，不阻塞首页）
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        let snapshotContext = context
        let snapshotProfile = UserProfileManager.shared.profile
        async let suggestionsTask = LLMService.shared.generateSuggestions(for: snapshotContext, profile: snapshotProfile)

        do {
            suggestions = try await suggestionsTask
            suggestionDataSource = .ai
            suggestionErrorMessage = ""
            suggestedQuestions = buildSuggestedQuestionsFromCards(suggestions)
            persistWidgetSnapshot()
        } catch {
            print("[HomeViewModel] AI suggestions failed: \(error)")
            suggestions = .empty(phase: context.phase)
            suggestionDataSource = .fallback
            suggestionErrorMessage = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            persistWidgetSnapshot()
        }

        hasLoaded = true
    }

    /// 由助手 Tab 首次出现时调用，懒加载推荐问题，避免在首页加载时浪费 API 请求。
    @MainActor
    func loadSuggestedQuestionsIfNeeded() async {
        guard suggestedQuestions.isEmpty, !isLoadingQuestions else { return }
        guard !usingMockData else { return }
        isLoadingQuestions = true
        defer { isLoadingQuestions = false }
        suggestedQuestions = buildSuggestedQuestionsFromCards(suggestions)
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
        guard let contextData = try? encoder.encode(context),
              let suggestionsData = try? encoder.encode(suggestions)
        else { return }

        defaults.set(contextData, forKey: widgetContextKey)
        defaults.set(suggestionsData, forKey: widgetSuggestionsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func buildSuggestedQuestionsFromCards(_ set: SuggestionSet) -> [String] {
        guard !set.suggestions.isEmpty else { return [] }
        var questions: [String] = []
        for suggestion in set.suggestions.prefix(3) {
            switch suggestion.dimension {
            case .diet:
                questions.append("今天在饮食上我该先做哪一步？")
            case .exercise:
                questions.append("按我今天状态，运动强度怎么安排更稳妥？")
            case .mood:
                questions.append("情绪波动时，我可以立刻做什么？")
            case .sleep:
                questions.append("今晚想睡得更稳，我该怎么调整？")
            }
        }
        if questions.count < 3 {
            questions.append(contentsOf: [
                "如果只能做一件事，优先做什么？",
                "有没有一个今天就能执行的简化版？",
                "需要避免的常见误区有哪些？"
            ])
        }
        var deduped: [String] = []
        var seen = Set<String>()
        for q in questions where !seen.contains(q) {
            deduped.append(q)
            seen.insert(q)
            if deduped.count == 3 { break }
        }
        return deduped
    }
}
