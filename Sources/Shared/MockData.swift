import Foundation

/// 模拟数据，用于 SwiftUI Preview 和无 HealthKit 环境
enum MockData {

    // MARK: - Cycle Context

    static let menstrualContext = CycleContext(
        phase: .menstrual,
        dayInPhase: 2,
        cycleDay: 2,
        avgCycleLength: 28,
        healthMetrics: sampleMetrics,
        menstrualSymptoms: sampleSymptoms
    )

    static let follicularContext = CycleContext(
        phase: .follicular,
        dayInPhase: 3,
        cycleDay: 8,
        avgCycleLength: 28,
        healthMetrics: sampleMetrics
    )

    static let ovulationContext = CycleContext(
        phase: .ovulation,
        dayInPhase: 1,
        cycleDay: 13,
        avgCycleLength: 28,
        healthMetrics: energeticMetrics
    )

    static let lutealContext = CycleContext(
        phase: .luteal,
        dayInPhase: 7,
        cycleDay: 22,
        avgCycleLength: 28,
        healthMetrics: tiredMetrics,
        menstrualSymptoms: lutealSymptoms
    )

    /// 没有任何健康数据与运动记录的上下文，用于预览「无运动记录」空状态。
    static let noHealthContext = CycleContext(
        phase: .follicular,
        dayInPhase: 3,
        cycleDay: 8,
        avgCycleLength: 28,
        healthMetrics: .empty
    )

    // MARK: - Health Metrics

    static let sampleMetrics = HealthMetrics(
        hrvCurrent: 42,
        hrvWeeklyAvg: 48,
        hrvTrend: .declining,
        restingHR: 68,
        daylightMinutes: 95,
        daylightTrend: .stable,
        exerciseMinutes: 25,
        exerciseTrend: .stable,
        activeCalories: 320,
        steps: 4230,
        activityTrend: .stable
    )

    static let energeticMetrics = HealthMetrics(
        hrvCurrent: 58,
        hrvWeeklyAvg: 52,
        hrvTrend: .rising,
        restingHR: 62,
        daylightMinutes: 120,
        daylightTrend: .rising,
        exerciseMinutes: 45,
        exerciseTrend: .rising,
        activeCalories: 480,
        steps: 8500,
        activityTrend: .rising
    )

    static let tiredMetrics = HealthMetrics(
        hrvCurrent: 35,
        hrvWeeklyAvg: 42,
        hrvTrend: .declining,
        restingHR: 72,
        daylightMinutes: 40,
        daylightTrend: .declining,
        exerciseMinutes: 10,
        exerciseTrend: .declining,
        activeCalories: 180,
        steps: 2800,
        activityTrend: .declining
    )

    // MARK: - Menstrual Symptoms

    static let sampleSymptoms = MenstrualSymptoms(
        flowLevel: .medium,
        recentSymptoms: [
            SymptomEntry(id: "cramps-mock", type: .abdominalCramps, severity: .moderate, date: .now),
            SymptomEntry(id: "fatigue-mock", type: .fatigue, severity: .mild, date: .now),
            SymptomEntry(id: "headache-mock", type: .headache, severity: .mild, date: .now),
        ]
    )

    static let lutealSymptoms = MenstrualSymptoms(
        flowLevel: nil,
        recentSymptoms: [
            SymptomEntry(id: "bloating-mock", type: .bloating, severity: .moderate, date: .now),
            SymptomEntry(id: "mood-mock", type: .moodChanges, severity: .mild, date: .now),
            SymptomEntry(id: "breast-mock", type: .breastPain, severity: .mild, date: .now),
        ]
    )

    // MARK: - User Profile

    static let climbingWorkoutStats = WorkoutStats(
        topActivities: [
            .init(name: "攀岩", count: 6),
            .init(name: "步行", count: 4),
            .init(name: "拉伸", count: 2),
        ],
        weeklyActivities: [
            .init(name: "攀岩", count: 3, totalDurationMinutes: 135),
            .init(name: "步行", count: 2, totalDurationMinutes: 55),
        ],
        weeklyWorkoutCount: 5,
        weeklyTotalDurationMinutes: 190,
        weeklyAvgDurationMinutes: 38,
        monthlyActivities: [
            .init(name: "攀岩", count: 12, totalDurationMinutes: 560),
            .init(name: "步行", count: 9, totalDurationMinutes: 210),
            .init(name: "拉伸", count: 5, totalDurationMinutes: 90),
        ],
        monthlyWorkoutCount: 26,
        monthlyTotalDurationMinutes: 860,
        monthlyAvgDurationMinutes: 33,
        yearlyActivities: [
            .init(name: "攀岩", count: 80, totalDurationMinutes: 3600),
            .init(name: "步行", count: 60, totalDurationMinutes: 1400),
            .init(name: "拉伸", count: 30, totalDurationMinutes: 540),
        ],
        yearlyWorkoutCount: 170,
        yearlyTotalDurationMinutes: 5540,
        yearlyAvgDurationMinutes: 32,
        weeklyFrequency: 3.2,
        avgDurationMinutes: 41,
        lastUpdated: Date()
    )

    static let tennisWorkoutStats = WorkoutStats(
        topActivities: [
            .init(key: "tennis", name: String(localized: "workout.activity.tennis"), count: 6),
            .init(key: "running", name: String(localized: "workout.activity.running"), count: 3),
            .init(key: "walking", name: String(localized: "workout.activity.walking"), count: 2),
        ],
        weeklyActivities: [
            .init(key: "tennis", name: String(localized: "workout.activity.tennis"), count: 3, totalDurationMinutes: 150),
            .init(key: "running", name: String(localized: "workout.activity.running"), count: 1, totalDurationMinutes: 30),
        ],
        weeklyWorkoutCount: 4,
        weeklyTotalDurationMinutes: 180,
        weeklyAvgDurationMinutes: 45,
        monthlyActivities: [
            .init(key: "tennis", name: String(localized: "workout.activity.tennis"), count: 12, totalDurationMinutes: 620),
            .init(key: "running", name: String(localized: "workout.activity.running"), count: 5, totalDurationMinutes: 140),
        ],
        monthlyWorkoutCount: 17,
        monthlyTotalDurationMinutes: 760,
        monthlyAvgDurationMinutes: 45,
        yearlyActivities: [
            .init(key: "tennis", name: String(localized: "workout.activity.tennis"), count: 90, totalDurationMinutes: 4600),
            .init(key: "running", name: String(localized: "workout.activity.running"), count: 40, totalDurationMinutes: 1100),
            .init(key: "walking", name: String(localized: "workout.activity.walking"), count: 25, totalDurationMinutes: 600),
        ],
        yearlyWorkoutCount: 155,
        yearlyTotalDurationMinutes: 6300,
        yearlyAvgDurationMinutes: 41,
        weeklyFrequency: 4,
        avgDurationMinutes: 42,
        lastUpdated: Date()
    )

    static let sampleProfile = UserProfile(
        bodyInfo: BodyInfo(
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -28, to: Date()),
            biologicalSex: "female",
            heightCM: 165,
            weightKG: 55
        ),
        accumulatedStats: AccumulatedCycleStats(
            cycleLengths: [28, 29, 27, 30, 28, 29],
            periodDurations: [5, 4, 5, 5, 4, 5],
            flowPatternByDay: ["1": "light", "2": "heavy", "3": "medium", "4": "light", "5": "light"],
            symptomFrequencies: [
                "luteal": ["bloating": 4, "moodChanges": 3, "breastPain": 2],
                "menstrual": ["abdominalCramps": 5, "fatigue": 3, "headache": 2],
            ],
            recentSymptoms48h: [
                SymptomEntry(id: "profile-cramps-now", type: .abdominalCramps, severity: .moderate, date: Date()),
                SymptomEntry(id: "profile-fatigue-now", type: .fatigue, severity: .mild, date: Date()),
            ],
            currentCycleSymptoms: [
                SymptomEntry(id: "profile-cramps-now", type: .abdominalCramps, severity: .moderate, date: Date()),
                SymptomEntry(id: "profile-headache-old", type: .headache, severity: .mild, date: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()),
            ],
            currentCycleFlowLevel: .medium,
            cyclesRecorded: 6,
            lastAccumulationDate: Date()
        ),
        workoutStats: tennisWorkoutStats,
        lifestyle: Lifestyle(
            sleepPattern: "通常 23:00-7:00",
            sleepPatternObservedAt: Date(),
            dietaryPreferences: ["素食", "乳糖不耐"],
            knownSensitivities: ["咖啡因影响睡眠"],
            lastExtractedAt: Date()
        ),
        knownConditions: ["轻度痛经"],
        lastUpdated: Date(),
        version: 1
    )

}
