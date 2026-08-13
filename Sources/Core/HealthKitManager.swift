import Foundation
import HealthKit

/// 负责 HealthKit 授权和数据读取
@Observable
final class HealthKitManager {

    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.timeInDaylight),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.dietaryWater),
        HKCategoryType(.menstrualFlow),
        HKCategoryType(.sleepAnalysis),
        HKCategoryType(.mindfulSession),
        // Menstrual symptoms
        HKCategoryType(.abdominalCramps),
        HKCategoryType(.bloating),
        HKCategoryType(.breastPain),
        HKCategoryType(.headache),
        HKCategoryType(.acne),
        HKCategoryType(.lowerBackPain),
        HKCategoryType(.pelvicPain),
        HKCategoryType(.moodChanges),
        HKCategoryType(.fatigue),
        HKCategoryType(.appetiteChanges),
        // Body measurements for profile
        HKQuantityType(.bodyMass),
        HKQuantityType(.height),
        // Characteristics (dateOfBirth, biologicalSex) don't need read authorization
        // Workouts
        HKWorkoutType.workoutType(),
    ]

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Menstrual Cycle

    /// 返回最近一次经期的起始日期
    func fetchLastPeriodStart() async -> Date? {
        let type = HKCategoryType(.menstrualFlow)
        let samples = await fetchCategorySamples(type: type, limit: 60, ascending: false)
        guard !samples.isEmpty else { return nil }

        let calendar = Calendar.current
        let sorted = samples.sorted { $0.startDate > $1.startDate }

        // 找到最近这次经期连续的开始日：允许 ≤2 天间隔
        var streakStart = sorted[0].startDate
        var prevDay = calendar.startOfDay(for: streakStart)

        for sample in sorted.dropFirst() {
            let day = calendar.startOfDay(for: sample.startDate)
            let gap = calendar.dateComponents([.day], from: day, to: prevDay).day ?? 99
            if gap <= 2 {
                streakStart = sample.startDate
                prevDay = day
            } else {
                break
            }
        }
        return calendar.startOfDay(for: streakStart)
    }

    /// 根据历史经期数据估算平均周期长度
    func fetchAverageCycleLength() async -> Int {
        let type = HKCategoryType(.menstrualFlow)
        let samples = await fetchCategorySamples(type: type, limit: 180, ascending: false)
        guard samples.count >= 2 else { return 28 }

        let calendar = Calendar.current
        var periodStarts: [Date] = []
        var streakStart = samples[0].startDate
        var prevDay = calendar.startOfDay(for: streakStart)

        for sample in samples.dropFirst() {
            let day = calendar.startOfDay(for: sample.startDate)
            let gap = calendar.dateComponents([.day], from: day, to: prevDay).day ?? 99
            if gap > 2 {
                periodStarts.append(calendar.startOfDay(for: streakStart))
                streakStart = sample.startDate
            }
            prevDay = day
        }
        periodStarts.append(calendar.startOfDay(for: streakStart))

        let sorted = periodStarts.sorted()
        guard sorted.count >= 2 else { return 28 }

        let gaps: [Int] = zip(sorted, sorted.dropFirst()).compactMap { a, b in
            let d = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            return (21...45).contains(d) ? d : nil
        }
        guard !gaps.isEmpty else { return 28 }
        return gaps.reduce(0, +) / gaps.count
    }

    // MARK: - Health Metrics

    func fetchHealthMetrics() async -> HealthMetrics {
        async let hrv      = fetchHRVMetrics()
        async let hr       = fetchLatestQuantity(type: HKQuantityType(.restingHeartRate),
                                                 unit: HKUnit.count().unitDivided(by: .minute()),
                                                 daysBack: 7)
        async let daylight = fetchDaylightMetrics()
        async let activity = fetchActivityMetrics()
        async let sleep    = fetchSleepMetrics()
        async let water    = fetchWaterIntake()
        async let mindful  = fetchMindfulMinutesWeekly()

        let (h, restingHR, d, a, s, w, mindfulMinutes) = await (hrv, hr, daylight, activity, sleep, water, mindful)

        return HealthMetrics(
            hrvCurrent:        h.current,
            hrvWeeklyAvg:      h.weeklyAvg,
            hrvTrend:          h.trend,
            restingHR:         restingHR,
            daylightMinutes:   d.minutes,
            daylightTrend:     d.trend,
            exerciseMinutes:   a.exerciseMinutes,
            exerciseTrend:     a.exerciseTrend,
            sleepHours:        s.hours,
            sleepTrend:        s.trend,
            waterMilliliters:  w,
            mindfulMinutesWeekly: mindfulMinutes,
            activeCalories:    a.calories,
            steps:             a.steps,
            activityTrend:     a.trend
        )
    }

    // MARK: - HRV

    private struct HRVResult {
        var current: Double?; var weeklyAvg: Double?; var trend: Trend?
    }

    private func fetchHRVMetrics() async -> HRVResult {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let unit = HKUnit.secondUnit(with: .milli)
        let now  = Date()
        let t3   = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let t7   = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let recent = await fetchQuantitySamples(type: type, start: t3, end: now)
            .map { $0.quantity.doubleValue(for: unit) }
        let older  = await fetchQuantitySamples(type: type, start: t7, end: t3)
            .map { $0.quantity.doubleValue(for: unit) }
        let all = recent + older

        let current    = recent.last
        let weeklyAvg  = all.isEmpty   ? nil : all.reduce(0, +)    / Double(all.count)
        let recentAvg  = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        let olderAvg   = older.isEmpty  ? nil : older.reduce(0, +)  / Double(older.count)

        var trend: Trend?
        if let r = recentAvg, let o = olderAvg {
            trend = r > o * 1.05 ? .rising : r < o * 0.95 ? .declining : .stable
        } else if !all.isEmpty {
            trend = .stable
        }
        return HRVResult(current: current, weeklyAvg: weeklyAvg, trend: trend)
    }

    // MARK: - Daylight (Time in Daylight)

    private struct DaylightResult {
        var minutes: Double?
        var trend: Trend?
    }

    private func fetchDaylightMetrics() async -> DaylightResult {
        let type = HKQuantityType(.timeInDaylight)
        let unit = HKUnit.minute()
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        async let todaySum = fetchSum(type: type, unit: unit, start: startOfDay, end: now)

        var priorDaily: [Double] = []
        for i in 1...7 {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -i, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let v = await fetchSum(type: type, unit: unit, start: dayStart, end: dayEnd) ?? 0
            priorDaily.append(v)
        }

        let today = await todaySum

        let avgPrior = priorDaily.reduce(0, +) / 7.0
        var trend: Trend?
        if let t = today, avgPrior > 0 {
            trend = t > avgPrior * 1.05 ? .rising : t < avgPrior * 0.95 ? .declining : .stable
        } else if let t = today, avgPrior == 0, t > 0 {
            trend = .rising
        }

        return DaylightResult(minutes: today, trend: trend)
    }

    // MARK: - Activity

    private struct ActivityResult {
        var calories: Double?
        var exerciseMinutes: Int?
        var exerciseTrend: Trend?
        var steps: Int?
        var trend: Trend?
    }

    private func fetchActivityMetrics() async -> ActivityResult {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        let t7  = calendar.date(byAdding: .day, value: -7, to: startOfDay)!

        let exerciseType = HKQuantityType(.appleExerciseTime)
        let minuteUnit = HKUnit.minute()

        async let todaySteps    = fetchSum(type: HKQuantityType(.stepCount),
                                           unit: .count(), start: startOfDay, end: now)
        async let todayCals     = fetchSum(type: HKQuantityType(.activeEnergyBurned),
                                           unit: .kilocalorie(), start: startOfDay, end: now)
        async let todayExercise = fetchSum(type: exerciseType,
                                           unit: minuteUnit, start: startOfDay, end: now)
        async let weeklySteps   = fetchSum(type: HKQuantityType(.stepCount),
                                           unit: .count(), start: t7, end: startOfDay)

        var priorExercise: [Double] = []
        for i in 1...7 {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -i, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let v = await fetchSum(type: exerciseType, unit: minuteUnit, start: dayStart, end: dayEnd) ?? 0
            priorExercise.append(v)
        }

        let (steps, cals, ex, wSteps) = await (todaySteps, todayCals, todayExercise, weeklySteps)

        var trend: Trend?
        if let s = steps, let ws = wSteps, ws > 0 {
            let dailyAvg = ws / 7
            trend = s > dailyAvg * 1.1 ? .rising : s < dailyAvg * 0.9 ? .declining : .stable
        }

        let exInt = ex.map { Int($0) }
        let avgEx = priorExercise.reduce(0, +) / 7.0
        var exerciseTrend: Trend?
        if let te = ex, avgEx > 0 {
            exerciseTrend = te > avgEx * 1.05 ? .rising : te < avgEx * 0.95 ? .declining : .stable
        } else if let te = ex, avgEx == 0, te > 0 {
            exerciseTrend = .rising
        }

        return ActivityResult(
            calories:        cals,
            exerciseMinutes: exInt,
            exerciseTrend:   exerciseTrend,
            steps:           steps.map { Int($0) },
            trend:           trend
        )
    }

    // MARK: - Sleep, Hydration, Mindfulness

    private struct SleepResult {
        var hours: Double?
        var trend: Trend?
    }

    private func fetchSleepMetrics() async -> SleepResult {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let lastNightStart = calendar.date(byAdding: .hour, value: -18, to: todayStart) ?? todayStart
        let recentSleep = await fetchAsleepHours(start: lastNightStart, end: now)

        var priorNights: [Double] = []
        for i in 1...7 {
            guard let nightEnd = calendar.date(byAdding: .day, value: -i + 1, to: todayStart),
                  let nightStart = calendar.date(byAdding: .hour, value: -18, to: nightEnd)
            else { continue }
            let hours = await fetchAsleepHours(start: nightStart, end: nightEnd)
            if let hours, hours > 0 { priorNights.append(hours) }
        }

        var trend: Trend?
        if let current = recentSleep, !priorNights.isEmpty {
            let avg = priorNights.reduce(0, +) / Double(priorNights.count)
            trend = current > avg * 1.08 ? .rising : current < avg * 0.92 ? .declining : .stable
        } else if recentSleep != nil {
            trend = .stable
        }

        return SleepResult(hours: recentSleep, trend: trend)
    }

    private func fetchAsleepHours(start: Date, end: Date) async -> Double? {
        let type = HKCategoryType(.sleepAnalysis)
        let samples = await fetchCategorySamples(
            type: type,
            start: start,
            end: end,
            limit: HKObjectQueryNoLimit,
            ascending: true
        )
        let asleepIntervals = samples.filter { sample in
            sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
            sample.value != HKCategoryValueSleepAnalysis.awake.rawValue
        }
        let seconds = asleepIntervals.reduce(0.0) { total, sample in
            total + max(0, sample.endDate.timeIntervalSince(sample.startDate))
        }
        guard seconds > 0 else { return nil }
        return seconds / 3600.0
    }

    private func fetchWaterIntake() async -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return await fetchSum(
            type: HKQuantityType(.dietaryWater),
            unit: .literUnit(with: .milli),
            start: startOfDay,
            end: Date()
        )
    }

    private func fetchMindfulMinutesWeekly() async -> Double? {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let type = HKCategoryType(.mindfulSession)
        let samples = await fetchCategorySamples(
            type: type,
            start: start,
            end: now,
            limit: HKObjectQueryNoLimit,
            ascending: true
        )
        let minutes = samples.reduce(0.0) { total, sample in
            total + max(0, sample.endDate.timeIntervalSince(sample.startDate)) / 60.0
        }
        return samples.isEmpty ? nil : minutes
    }

    // MARK: - Query Helpers

    private func fetchQuantitySamples(type: HKQuantityType, start: Date, end: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType,
                                       start: Date? = nil,
                                       end: Date? = nil,
                                       limit: Int,
                                       ascending: Bool) async -> [HKCategorySample] {
        await withCheckedContinuation { continuation in
            let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: end) }
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    // Overload used internally with explicit start/end
    private func fetchCategorySamples(type: HKCategoryType,
                                       start: Date,
                                       end: Date,
                                       limit: Int,
                                       ascending: Bool) async -> [HKCategorySample] {
        await fetchCategorySamples(type: type, start: Optional(start), end: end,
                                    limit: limit, ascending: ascending)
    }

    private func fetchLatestQuantity(type: HKQuantityType, unit: HKUnit, daysBack: Int) async -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let samples = await fetchQuantitySamples(type: type, start: start, end: Date())
        return samples.last.map { $0.quantity.doubleValue(for: unit) }
    }

    private func fetchSum(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Menstrual Symptoms

    /// 获取最近经期的出血量（最近一条 menstrualFlow 记录的 value）
    func fetchCurrentFlowLevel() async -> FlowLevel? {
        let type = HKCategoryType(.menstrualFlow)
        let samples = await fetchCategorySamples(type: type, limit: 1, ascending: false)
        guard let sample = samples.first else { return nil }

        // 只返回最近 3 天内的记录
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        guard sample.startDate >= threeDaysAgo else { return nil }

        switch sample.value {
        case HKCategoryValueMenstrualFlow.light.rawValue:  return .light
        case HKCategoryValueMenstrualFlow.medium.rawValue: return .medium
        case HKCategoryValueMenstrualFlow.heavy.rawValue:  return .heavy
        case HKCategoryValueMenstrualFlow.none.rawValue:   return FlowLevel.none
        default: return .unspecified
        }
    }

    /// 获取当前周期内记录的症状（从 periodStart 开始，或最近 30 天）
    func fetchMenstrualSymptoms(since periodStart: Date?) async -> MenstrualSymptoms {
        let lookbackStart = periodStart ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let now = Date()

        async let flow = fetchCurrentFlowLevel()

        let symptomTypes: [(HKCategoryType, SymptomEntry.SymptomType)] = [
            (HKCategoryType(.abdominalCramps), .abdominalCramps),
            (HKCategoryType(.bloating),        .bloating),
            (HKCategoryType(.breastPain),      .breastPain),
            (HKCategoryType(.headache),        .headache),
            (HKCategoryType(.acne),            .acne),
            (HKCategoryType(.lowerBackPain),   .lowerBackPain),
            (HKCategoryType(.pelvicPain),      .pelvicPain),
            (HKCategoryType(.moodChanges),     .moodChanges),
            (HKCategoryType(.fatigue),         .fatigue),
            (HKCategoryType(.appetiteChanges), .appetiteChanges),
        ]

        var entries: [SymptomEntry] = []

        // 并行获取各类症状的最新记录
        await withTaskGroup(of: SymptomEntry?.self) { group in
            for (hkType, symptomType) in symptomTypes {
                group.addTask {
                    let samples = await self.fetchCategorySamples(
                        type: hkType, start: lookbackStart, end: now,
                        limit: 1, ascending: false
                    )
                    guard let sample = samples.first else { return nil }
                    let severity = Self.mapSeverity(sample.value)
                    return SymptomEntry(
                        id: "\(symptomType.rawValue)-\(Int(sample.startDate.timeIntervalSince1970))",
                        type: symptomType,
                        severity: severity,
                        date: sample.startDate
                    )
                }
            }
            for await entry in group {
                if let entry { entries.append(entry) }
            }
        }

        let flowLevel = await flow

        return MenstrualSymptoms(
            flowLevel: flowLevel,
            recentSymptoms: entries
        )
    }

    private static func mapSeverity(_ value: Int) -> SymptomSeverity {
        switch value {
        case HKCategoryValueSeverity.mild.rawValue:     return .mild
        case HKCategoryValueSeverity.moderate.rawValue:  return .moderate
        case HKCategoryValueSeverity.severe.rawValue:    return .severe
        case HKCategoryValueSeverity.notPresent.rawValue: return .notPresent
        default: return .mild // unspecified → treat as mild
        }
    }

    // MARK: - Body Info (Profile)

    /// 读取 HealthKit 特征值和最新体征量
    func fetchBodyInfo() async -> BodyInfo {
        var info = BodyInfo()

        // 特征值（不需要授权，直接读取）
        info.dateOfBirth = try? store.dateOfBirthComponents().date

        if let bioSex = try? store.biologicalSex().biologicalSex {
            switch bioSex {
            case .female:       info.biologicalSex = "female"
            case .male:         info.biologicalSex = "male"
            case .other:        info.biologicalSex = "other"
            case .notSet:       break
            @unknown default:   break
            }
        }

        // 最新体征量
        async let weight = fetchLatestQuantity(
            type: HKQuantityType(.bodyMass), unit: .gramUnit(with: .kilo), daysBack: 90
        )
        async let height = fetchLatestQuantity(
            type: HKQuantityType(.height), unit: .meterUnit(with: .centi), daysBack: 365
        )

        info.weightKG = await weight
        info.heightCM = await height

        return info
    }

    // MARK: - Workout Stats (Profile)

    /// 统计最近 30 天运动记录
    func fetchWorkoutStats() async -> WorkoutStats {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -30, to: now)!
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!

        let workouts = await fetchWorkouts(start: start, end: now)
        guard !workouts.isEmpty else { return .empty }

        // 统计运动类型
        var activitySummaries: [String: WorkoutActivitySummary] = [:]
        var totalDuration: TimeInterval = 0

        for workout in workouts {
            let descriptor = Self.workoutDescriptor(for: workout.workoutActivityType)
            var summary = activitySummaries[descriptor.key] ?? WorkoutActivitySummary(descriptor: descriptor)
            summary.count += 1
            activitySummaries[descriptor.key] = summary
            totalDuration += workout.duration
        }

        let topActivities = activitySummaries.values
            .sorted(by: Self.compareWorkoutActivitySummaries)
            .prefix(5)
            .map { $0.workoutActivity() }

        let weeklyWorkouts = workouts.filter { $0.startDate >= weekStart }
        var weeklyActivitySummaries: [String: WorkoutActivitySummary] = [:]
        var weeklyTotalDuration: TimeInterval = 0

        for workout in weeklyWorkouts {
            let descriptor = Self.workoutDescriptor(for: workout.workoutActivityType)
            var summary = weeklyActivitySummaries[descriptor.key] ?? WorkoutActivitySummary(descriptor: descriptor)
            summary.count += 1
            summary.totalDuration += workout.duration
            weeklyActivitySummaries[descriptor.key] = summary
            weeklyTotalDuration += workout.duration
        }

        let weeklyActivities = weeklyActivitySummaries.values
            .sorted(by: Self.compareWorkoutActivitySummaries)
            .prefix(5)
            .map { $0.workoutActivity(includeDuration: true) }

        let weeks = max(1.0, Double(calendar.dateComponents([.day], from: start, to: now).day ?? 30) / 7.0)
        let weeklyFreq = Double(workouts.count) / weeks
        let avgDuration = totalDuration / Double(workouts.count) / 60.0
        let weeklyAvgDuration = weeklyWorkouts.isEmpty ? nil : weeklyTotalDuration / Double(weeklyWorkouts.count) / 60.0

        return WorkoutStats(
            topActivities: Array(topActivities),
            weeklyActivities: Array(weeklyActivities),
            weeklyWorkoutCount: weeklyWorkouts.count,
            weeklyTotalDurationMinutes: weeklyTotalDuration / 60.0,
            weeklyAvgDurationMinutes: weeklyAvgDuration,
            weeklyFrequency: weeklyFreq,
            avgDurationMinutes: avgDuration,
            lastUpdated: now
        )
    }

    private func fetchWorkouts(start: Date, end: Date) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private struct WorkoutActivityDescriptor {
        let key: String
        let rawValue: UInt
        let fallbackName: String

        var displayName: String {
            let localizationKey = "workout.activity.\(key)"
            let localized = NSLocalizedString(localizationKey, comment: "")
            return localized == localizationKey ? fallbackName : localized
        }
    }

    private struct WorkoutActivitySummary {
        let descriptor: WorkoutActivityDescriptor
        var count: Int = 0
        var totalDuration: TimeInterval = 0

        func workoutActivity(includeDuration: Bool = false) -> WorkoutStats.WorkoutActivity {
            WorkoutStats.WorkoutActivity(
                key: descriptor.key,
                rawValue: descriptor.rawValue,
                name: descriptor.displayName,
                count: count,
                totalDurationMinutes: includeDuration ? totalDuration / 60.0 : nil
            )
        }
    }

    private static func compareWorkoutActivitySummaries(
        _ lhs: WorkoutActivitySummary,
        _ rhs: WorkoutActivitySummary
    ) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        if lhs.totalDuration != rhs.totalDuration {
            return lhs.totalDuration > rhs.totalDuration
        }
        return lhs.descriptor.key < rhs.descriptor.key
    }

    private static func workoutDescriptor(for type: HKWorkoutActivityType) -> WorkoutActivityDescriptor {
        let rawValue = type.rawValue
        if let known = knownWorkoutActivities[rawValue] {
            return WorkoutActivityDescriptor(key: known.key, rawValue: rawValue, fallbackName: known.fallbackName)
        }

        return WorkoutActivityDescriptor(
            key: "unknown_\(rawValue)",
            rawValue: rawValue,
            fallbackName: "其他运动"
        )
    }

    private static let knownWorkoutActivities: [UInt: (key: String, fallbackName: String)] = [
        1: ("american_football", "美式橄榄球"),
        2: ("archery", "射箭"),
        3: ("australian_football", "澳式足球"),
        4: ("badminton", "羽毛球"),
        5: ("baseball", "棒球"),
        6: ("basketball", "篮球"),
        7: ("bowling", "保龄球"),
        8: ("boxing", "拳击"),
        9: ("climbing", "攀岩"),
        10: ("cricket", "板球"),
        11: ("cross_training", "交叉训练"),
        12: ("curling", "冰壶"),
        13: ("cycling", "骑行"),
        14: ("dance", "舞蹈"),
        15: ("dance_inspired_training", "舞蹈训练"),
        16: ("elliptical", "椭圆机"),
        17: ("equestrian_sports", "马术"),
        18: ("fencing", "击剑"),
        19: ("fishing", "钓鱼"),
        20: ("functional_strength_training", "功能性力量训练"),
        21: ("golf", "高尔夫"),
        22: ("gymnastics", "体操"),
        23: ("handball", "手球"),
        24: ("hiking", "徒步"),
        25: ("hockey", "曲棍球"),
        26: ("hunting", "狩猎"),
        27: ("lacrosse", "长曲棍球"),
        28: ("martial_arts", "武术"),
        29: ("mind_and_body", "身心训练"),
        30: ("mixed_metabolic_cardio_training", "混合代谢有氧训练"),
        31: ("paddle_sports", "桨板运动"),
        32: ("play", "玩耍活动"),
        33: ("preparation_and_recovery", "热身与恢复"),
        34: ("racquetball", "短柄墙球"),
        35: ("rowing", "划船"),
        36: ("rugby", "橄榄球"),
        37: ("running", "跑步"),
        38: ("sailing", "帆船"),
        39: ("skating_sports", "滑冰运动"),
        40: ("snow_sports", "雪上运动"),
        41: ("soccer", "足球"),
        42: ("softball", "垒球"),
        43: ("squash", "壁球"),
        44: ("stair_climbing", "爬楼梯"),
        45: ("surfing_sports", "冲浪"),
        46: ("swimming", "游泳"),
        47: ("table_tennis", "乒乓球"),
        48: ("tennis", "网球"),
        49: ("track_and_field", "田径"),
        50: ("traditional_strength_training", "传统力量训练"),
        51: ("volleyball", "排球"),
        52: ("walking", "步行"),
        53: ("water_fitness", "水中健身"),
        54: ("water_polo", "水球"),
        55: ("water_sports", "水上运动"),
        56: ("wrestling", "摔跤"),
        57: ("yoga", "瑜伽"),
        58: ("barre", "芭蕾塑形"),
        59: ("core_training", "核心训练"),
        60: ("cross_country_skiing", "越野滑雪"),
        61: ("downhill_skiing", "高山滑雪"),
        62: ("flexibility", "柔韧训练"),
        63: ("high_intensity_interval_training", "HIIT"),
        64: ("jump_rope", "跳绳"),
        65: ("kickboxing", "踢拳"),
        66: ("pilates", "普拉提"),
        67: ("snowboarding", "单板滑雪"),
        68: ("stairs", "楼梯训练"),
        69: ("step_training", "踏板训练"),
        70: ("wheelchair_walk_pace", "轮椅步行配速"),
        71: ("wheelchair_run_pace", "轮椅跑步配速"),
        72: ("tai_chi", "太极"),
        73: ("mixed_cardio", "有氧运动"),
        74: ("hand_cycling", "手摇车"),
        75: ("disc_sports", "飞盘运动"),
        76: ("fitness_gaming", "健身游戏"),
        77: ("cardio_dance", "有氧舞蹈"),
        78: ("social_dance", "社交舞"),
        79: ("pickleball", "匹克球"),
        80: ("cooldown", "放松整理"),
        82: ("swim_bike_run", "铁人三项"),
        83: ("transition", "转换区"),
        84: ("underwater_diving", "潜水"),
        3000: ("other", "其他运动")
    ]

    // MARK: - Historical Cycle Data (Profile)

    /// 返回历史周期长度数组（用于档案积累）
    func fetchHistoricalCycleLengths() async -> [Int] {
        let type = HKCategoryType(.menstrualFlow)
        let samples = await fetchCategorySamples(type: type, limit: 180, ascending: false)
        guard samples.count >= 2 else { return [] }

        let periodStarts = Self.detectPeriodStarts(from: samples)
        let sorted = periodStarts.sorted()
        guard sorted.count >= 2 else { return [] }

        return zip(sorted, sorted.dropFirst()).compactMap { a, b in
            let d = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
            return (21...45).contains(d) ? d : nil
        }
    }

    /// 返回历史经期天数数组
    func fetchPeriodDurations() async -> [Int] {
        let type = HKCategoryType(.menstrualFlow)
        let samples = await fetchCategorySamples(type: type, limit: 180, ascending: false)
        guard !samples.isEmpty else { return [] }

        let calendar = Calendar.current
        let sorted = samples.sorted { $0.startDate < $1.startDate }

        var durations: [Int] = []
        var streakStart = sorted[0].startDate
        var prevDay = calendar.startOfDay(for: streakStart)
        var streakDays = 1

        for sample in sorted.dropFirst() {
            let day = calendar.startOfDay(for: sample.startDate)
            let gap = calendar.dateComponents([.day], from: prevDay, to: day).day ?? 99
            if gap <= 2 {
                streakDays += gap
            } else {
                if (2...10).contains(streakDays) { durations.append(streakDays) }
                streakStart = sample.startDate
                streakDays = 1
            }
            prevDay = day
        }
        if (2...10).contains(streakDays) { durations.append(streakDays) }

        return durations
    }

    /// 从经期样本中检测各次经期的起始日期
    private static func detectPeriodStarts(from samples: [HKCategorySample]) -> [Date] {
        let calendar = Calendar.current
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var periodStarts: [Date] = []
        var streakStart = sorted[0].startDate
        var prevDay = calendar.startOfDay(for: streakStart)

        for sample in sorted.dropFirst() {
            let day = calendar.startOfDay(for: sample.startDate)
            let gap = calendar.dateComponents([.day], from: prevDay, to: day).day ?? 99
            if gap > 2 {
                periodStarts.append(calendar.startOfDay(for: streakStart))
                streakStart = sample.startDate
            }
            prevDay = day
        }
        periodStarts.append(calendar.startOfDay(for: streakStart))
        return periodStarts
    }
}
