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

    // MARK: - Suggestions

    static let sampleSuggestions = SuggestionSet(
        phase: .luteal,
        suggestions: [
            Suggestion(
                id: "diet-1", dimension: .diet,
                title: String(localized: "mock.diet.title"),
                details: [
                    String(localized: "mock.diet.detail.1"),
                    String(localized: "mock.diet.detail.2"),
                    String(localized: "mock.diet.detail.3")
                ],
                referenceIds: ["ref-001"]
            ),
            Suggestion(
                id: "exercise-1", dimension: .exercise,
                title: String(localized: "mock.exercise.title"),
                details: [
                    String(localized: "mock.exercise.detail.1"),
                    String(localized: "mock.exercise.detail.2"),
                    String(localized: "mock.exercise.detail.3")
                ],
                referenceIds: ["ref-002"]
            ),
            Suggestion(
                id: "mood-1", dimension: .mood,
                title: String(localized: "mock.mood.title"),
                details: [
                    String(localized: "mock.mood.detail.1"),
                    String(localized: "mock.mood.detail.2"),
                    String(localized: "mock.mood.detail.3")
                ],
                referenceIds: []
            ),
            Suggestion(
                id: "sleep-1", dimension: .sleep,
                title: String(localized: "mock.sleep.title"),
                details: [
                    String(localized: "mock.sleep.detail.1"),
                    String(localized: "mock.sleep.detail.2"),
                    String(localized: "mock.sleep.detail.3")
                ],
                referenceIds: ["ref-003"]
            ),
        ],
        generatedAt: .now
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
        weeklyFrequency: 3.2,
        avgDurationMinutes: 41,
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
        workoutStats: climbingWorkoutStats,
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

    // MARK: - Research References

    static let sampleReferences: [ResearchReference] = [
        ResearchReference(
            id: "ref-001",
            title: "Magnesium supplementation and premenstrual symptoms",
            authors: "Quaranta S, Buscaglia MA, Meroni MG",
            journal: "Gynecological Endocrinology",
            year: 2007,
            doi: "10.1080/09513590701672311",
            summary: "镁补充可显著减轻经前综合征症状",
            phases: [.luteal],
            dimensions: [.diet],
            keyFindings: [
                "每日补充 250mg 镁可缓解 PMS 症状",
                "镁与 B6 联合效果更佳"
            ]
        ),
        ResearchReference(
            id: "ref-002",
            title: "Exercise and premenstrual symptomatology",
            authors: "Daley AJ",
            journal: "Journal of Psychosomatic Obstetrics & Gynecology",
            year: 2009,
            doi: "10.1080/01674820802507324",
            summary: "规律有氧运动可缓解经前综合征症状",
            phases: [.luteal, .menstrual],
            dimensions: [.exercise],
            keyFindings: [
                "每周 3 次中等强度有氧运动可改善 PMS",
                "运动通过提高内啡肽水平改善情绪"
            ]
        ),
        ResearchReference(
            id: "ref-003",
            title: "Sleep quality changes across the menstrual cycle",
            authors: "Baker FC, Driver HS",
            journal: "Sleep Medicine Reviews",
            year: 2007,
            doi: "10.1016/j.smrv.2007.01.003",
            summary: "黄体期睡眠质量通常下降，深睡比例减少",
            phases: [.luteal],
            dimensions: [.sleep],
            keyFindings: [
                "黄体期核心体温升高影响入睡",
                "建议降低卧室温度、提前入睡时间"
            ]
        ),
    ]
}
