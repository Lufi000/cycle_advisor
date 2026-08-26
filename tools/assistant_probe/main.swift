import Foundation

// MARK: - Spec (stdin JSON)
//
// 输入（stdin）：
// {
//   "id": "case_xxx",
//   "task": "chat" | "followup" | "suggested",
//   "mode": "fast" | "deep",
//   "language": "zh" | "en" | "auto",
//   "user_message": "...",
//   "context_preset": "...",
//   "profile_preset": "...",
//   "assistant_reply": "..."   // followup 任务使用
// }
//
// 输出（stdout）：JSON，包含与 App 完全相同的 prompt 文本，
// 供 assistant_acceptance_runner.py 调用真实 API 使用。

private struct Spec: Codable {
    var id: String
    var task: String
    var mode: String
    var language: String
    var userMessage: String
    var contextPreset: String
    var profilePreset: String
    var assistantReply: String?

    enum CodingKeys: String, CodingKey {
        case id, task, mode, language
        case userMessage = "user_message"
        case contextPreset = "context_preset"
        case profilePreset = "profile_preset"
        case assistantReply = "assistant_reply"
    }
}

private struct ProbeOutput: Encodable {
    var id: String
    var task: String
    var mode: String
    var detectedLanguage: String
    var systemPrompt: String
    var userMessage: String
    var contextLines: [String]
    var profileSummary: String
    var responseLanguageName: String
}

// MARK: - Context presets（与 App 真实数据形状一致）

private func makeContext(_ preset: String) -> CycleContext {
    switch preset {
    case "menstrual_day2_cramps":
        return CycleContext(
            phase: .menstrual,
            dayInPhase: 2,
            cycleDay: 2,
            avgCycleLength: 28,
            healthMetrics: HealthMetrics(
                hrvCurrent: 42,
                hrvWeeklyAvg: 48,
                hrvTrend: .declining,
                restingHR: 68,
                daylightMinutes: 95,
                daylightTrend: .stable,
                exerciseMinutes: 25,
                exerciseTrend: .stable,
                sleepHours: 6.5,
                sleepTrend: .declining,
                waterMilliliters: 600,
                mindfulMinutesWeekly: 20,
                activeCalories: 320,
                steps: 4230,
                activityTrend: .stable
            ),
            menstrualSymptoms: MenstrualSymptoms(
                flowLevel: .medium,
                recentSymptoms: [
                    SymptomEntry(id: "cramps", type: .abdominalCramps, severity: .moderate, date: .now),
                    SymptomEntry(id: "fatigue", type: .fatigue, severity: .mild, date: .now),
                    SymptomEntry(id: "headache", type: .headache, severity: .mild, date: .now),
                ]
            )
        )
    case "follicular_day3":
        return CycleContext(
            phase: .follicular,
            dayInPhase: 3,
            cycleDay: 8,
            avgCycleLength: 28,
            healthMetrics: HealthMetrics(
                hrvCurrent: 58,
                hrvWeeklyAvg: 52,
                hrvTrend: .rising,
                restingHR: 62,
                daylightMinutes: 120,
                daylightTrend: .rising,
                exerciseMinutes: 45,
                exerciseTrend: .rising,
                sleepHours: 7.5,
                sleepTrend: .rising,
                waterMilliliters: 900,
                mindfulMinutesWeekly: 30,
                activeCalories: 480,
                steps: 8500,
                activityTrend: .rising
            )
        )
    case "follicular_morning_low_activity":
        // 上午低活动场景：用于验证「不得因今日数据暂时偏低而施压」
        return CycleContext(
            phase: .follicular,
            dayInPhase: 3,
            cycleDay: 8,
            avgCycleLength: 28,
            healthMetrics: HealthMetrics(
                hrvCurrent: 55,
                hrvWeeklyAvg: 52,
                hrvTrend: .rising,
                restingHR: 63,
                daylightMinutes: 20,
                daylightTrend: .stable,
                exerciseMinutes: 0,
                exerciseTrend: nil,
                sleepHours: 7.0,
                sleepTrend: .stable,
                waterMilliliters: 300,
                mindfulMinutesWeekly: 5,
                activeCalories: 45,
                steps: 620,
                activityTrend: .stable
            )
        )
    case "ovulation_day1":
        return CycleContext(
            phase: .ovulation,
            dayInPhase: 1,
            cycleDay: 13,
            avgCycleLength: 28,
            healthMetrics: HealthMetrics(
                hrvCurrent: 62,
                hrvWeeklyAvg: 55,
                hrvTrend: .rising,
                restingHR: 60,
                daylightMinutes: 130,
                daylightTrend: .rising,
                exerciseMinutes: 40,
                exerciseTrend: .rising,
                sleepHours: 7.2,
                sleepTrend: .stable,
                waterMilliliters: 1000,
                mindfulMinutesWeekly: 25,
                activeCalories: 520,
                steps: 9200,
                activityTrend: .rising
            )
        )
    case "luteal_day7_tired":
        return CycleContext(
            phase: .luteal,
            dayInPhase: 7,
            cycleDay: 22,
            avgCycleLength: 28,
            healthMetrics: HealthMetrics(
                hrvCurrent: 35,
                hrvWeeklyAvg: 42,
                hrvTrend: .declining,
                restingHR: 72,
                daylightMinutes: 40,
                daylightTrend: .declining,
                exerciseMinutes: 10,
                exerciseTrend: .declining,
                sleepHours: 5.5,
                sleepTrend: .declining,
                waterMilliliters: 500,
                mindfulMinutesWeekly: 10,
                activeCalories: 180,
                steps: 2800,
                activityTrend: .declining
            ),
            menstrualSymptoms: MenstrualSymptoms(
                flowLevel: nil,
                recentSymptoms: [
                    SymptomEntry(id: "bloating", type: .bloating, severity: .moderate, date: .now),
                    SymptomEntry(id: "mood", type: .moodChanges, severity: .mild, date: .now),
                    SymptomEntry(id: "breast", type: .breastPain, severity: .mild, date: .now),
                ]
            )
        )
    case "luteal_day7_predicted":
        var ctx = makeContext("luteal_day7_tired")
        ctx.isPredicted = true
        return ctx
    case "no_health_data":
        return CycleContext(
            phase: .follicular,
            dayInPhase: 3,
            cycleDay: 8,
            avgCycleLength: 28,
            healthMetrics: .empty
        )
    default:
        return makeContext("no_health_data")
    }
}

// MARK: - Profile presets

private func makeProfile(_ preset: String) -> UserProfile {
    let now = Date()
    switch preset {
    case "vegan_lactose_caffeine":
        return UserProfile(
            bodyInfo: BodyInfo(
                dateOfBirth: Calendar.current.date(byAdding: .year, value: -29, to: now),
                biologicalSex: "female",
                heightCM: 165,
                weightKG: 55
            ),
            accumulatedStats: AccumulatedCycleStats(
                cycleLengths: [29, 30, 28, 31, 29],
                periodDurations: [5, 4, 5, 5, 4],
                flowPatternByDay: ["1": FlowLevel.medium.rawValue, "2": FlowLevel.heavy.rawValue, "3": FlowLevel.medium.rawValue],
                symptomFrequencies: [
                    CyclePhase.luteal.rawValue: [
                        SymptomEntry.SymptomType.bloating.rawValue: 4,
                        SymptomEntry.SymptomType.moodChanges.rawValue: 3,
                    ]
                ],
                recentSymptoms48h: nil,
                currentCycleSymptoms: nil,
                currentCycleFlowLevel: nil,
                cyclesRecorded: 5,
                lastAccumulationDate: now
            ),
            workoutStats: WorkoutStats(
                topActivities: [
                    WorkoutStats.WorkoutActivity(name: "攀岩", count: 6),
                    WorkoutStats.WorkoutActivity(name: "步行", count: 4),
                    WorkoutStats.WorkoutActivity(name: "拉伸", count: 2),
                ],
                weeklyActivities: [
                    WorkoutStats.WorkoutActivity(name: "攀岩", count: 3, totalDurationMinutes: 135),
                    WorkoutStats.WorkoutActivity(name: "步行", count: 2, totalDurationMinutes: 55),
                ],
                weeklyWorkoutCount: 5,
                weeklyTotalDurationMinutes: 190,
                weeklyAvgDurationMinutes: 38,
                weeklyFrequency: 3.5,
                avgDurationMinutes: 40,
                lastUpdated: now
            ),
            lifestyle: Lifestyle(
                sleepPattern: "通常 23:00-7:00",
                sleepPatternObservedAt: now.addingTimeInterval(-86400 * 2),
                dietaryPreferences: ["素食", "乳糖不耐"],
                knownSensitivities: ["咖啡因影响睡眠"],
                lastExtractedAt: now.addingTimeInterval(-86400 * 2)
            ),
            knownConditions: [],
            lastUpdated: now,
            version: 1
        )
    case "runner_yoga_cramps_history":
        return UserProfile(
            bodyInfo: BodyInfo(
                dateOfBirth: Calendar.current.date(byAdding: .year, value: -27, to: now),
                biologicalSex: "female",
                heightCM: 170,
                weightKG: 58
            ),
            accumulatedStats: AccumulatedCycleStats(
                cycleLengths: [28, 27, 29, 28],
                periodDurations: [5, 5, 6, 5],
                flowPatternByDay: ["1": FlowLevel.medium.rawValue, "2": FlowLevel.medium.rawValue],
                symptomFrequencies: [
                    CyclePhase.menstrual.rawValue: [
                        SymptomEntry.SymptomType.abdominalCramps.rawValue: 6,
                        SymptomEntry.SymptomType.fatigue.rawValue: 2,
                    ]
                ],
                recentSymptoms48h: nil,
                currentCycleSymptoms: nil,
                currentCycleFlowLevel: nil,
                cyclesRecorded: 4,
                lastAccumulationDate: now
            ),
            workoutStats: WorkoutStats(
                topActivities: [
                    WorkoutStats.WorkoutActivity(name: "跑步", count: 8),
                    WorkoutStats.WorkoutActivity(name: "瑜伽", count: 5),
                ],
                dailyActivities: [
                    WorkoutStats.WorkoutActivity(name: "跑步", count: 1, totalDurationMinutes: 45),
                    WorkoutStats.WorkoutActivity(name: "瑜伽", count: 1, totalDurationMinutes: 40),
                ],
                todayWorkoutCount: 2,
                todayTotalDurationMinutes: 85,
                todayAvgDurationMinutes: 42.5,
                weeklyActivities: [
                    WorkoutStats.WorkoutActivity(name: "跑步", count: 3, totalDurationMinutes: 150),
                    WorkoutStats.WorkoutActivity(name: "瑜伽", count: 2, totalDurationMinutes: 80),
                ],
                weeklyWorkoutCount: 5,
                weeklyTotalDurationMinutes: 230,
                weeklyAvgDurationMinutes: 46,
                weeklyFrequency: 4.2,
                avgDurationMinutes: 42,
                lastUpdated: now
            ),
            lifestyle: Lifestyle(
                sleepPattern: "通常 22:30-6:30",
                sleepPatternObservedAt: now.addingTimeInterval(-86400),
                dietaryPreferences: [],
                knownSensitivities: [],
                lastExtractedAt: now.addingTimeInterval(-86400)
            ),
            knownConditions: ["痛经史"],
            lastUpdated: now,
            version: 1
        )
    case "basic_general":
        return UserProfile(
            bodyInfo: BodyInfo(
                dateOfBirth: Calendar.current.date(byAdding: .year, value: -31, to: now),
                biologicalSex: "female",
                heightCM: 160,
                weightKG: 52
            ),
            accumulatedStats: AccumulatedCycleStats(
                cycleLengths: [28, 29, 28],
                periodDurations: [5, 5, 5],
                flowPatternByDay: [:],
                symptomFrequencies: [:],
                recentSymptoms48h: nil,
                currentCycleSymptoms: nil,
                currentCycleFlowLevel: nil,
                cyclesRecorded: 3,
                lastAccumulationDate: now
            ),
            workoutStats: .empty,
            lifestyle: Lifestyle(
                sleepPattern: "通常 00:00-8:00",
                sleepPatternObservedAt: now.addingTimeInterval(-86400 * 5),
                dietaryPreferences: [],
                knownSensitivities: [],
                lastExtractedAt: now.addingTimeInterval(-86400 * 5)
            ),
            knownConditions: [],
            lastUpdated: now,
            version: 1
        )
    default:
        return .empty
    }
}

// MARK: - Main

private func run() throws {
    let raw = FileHandle.standardInput.readDataToEndOfFile()
    guard !raw.isEmpty,
          let spec = try? JSONDecoder().decode(Spec.self, from: raw)
    else {
        throw ProbeError.invalidSpec
    }

    // 与 App 的 LanguageManager 行为一致：按用例语言设置系统偏好，
    // 让 String(localized:) / 单位格式化解析到对应 lproj。
    switch spec.language {
    case "en":
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
    case "zh":
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
    default:
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    let context = makeContext(spec.contextPreset)
    let profile = makeProfile(spec.profilePreset)

    let fallback: LLMService.ResponseLanguage =
        spec.language == "en" ? .english : .simplifiedChinese
    let detected: LLMService.ResponseLanguage =
        spec.language == "auto"
            ? LLMService.responseLanguage(for: spec.userMessage, fallback: .simplifiedChinese)
            : fallback

    let systemPrompt: String
    let userPrompt: String
    let task: String

    switch spec.task {
    case "followup":
        task = "followup"
        systemPrompt = LLMService.buildChatFollowUpQuestionsSystemPrompt(responseLanguage: detected)
        userPrompt = LLMService.buildChatFollowUpUserPrompt(
            context: context,
            userQuestion: spec.userMessage,
            assistantReply: spec.assistantReply ?? "",
            recentDialogue: "",
            responseLanguage: detected
        )
    case "suggested":
        task = "suggested"
        systemPrompt = LLMService.buildSuggestedQuestionsSystemPrompt()
        userPrompt = LLMService.buildContextLines(context: context).joined(separator: "\n")
    default:
        task = "chat"
        systemPrompt = LLMService.buildChatSystemPrompt(
            context: context,
            profile: profile,
            responseLanguage: detected
        )
        userPrompt = spec.userMessage
    }

    let output = ProbeOutput(
        id: spec.id,
        task: task,
        mode: spec.mode,
        detectedLanguage: detected == .english ? "english" : "simplifiedChinese",
        systemPrompt: systemPrompt,
        userMessage: userPrompt,
        contextLines: LLMService.buildContextLines(context: context),
        profileSummary: LLMService.buildProfileSummary(profile: profile),
        responseLanguageName: detected.displayName
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    let data = try encoder.encode(output)
    FileHandle.standardOutput.write(data)
}

private enum ProbeError: Error {
    case invalidSpec
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("probe error: \(error)".utf8))
    exit(1)
}
