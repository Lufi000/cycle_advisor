import Foundation

// MARK: - UserProfile

struct UserProfile: Codable, Equatable {
    /// 身体基本信息（HealthKit 特征值 + 体征量）
    var bodyInfo: BodyInfo
    /// 历史周期统计（HealthKit 自动积累）
    var accumulatedStats: AccumulatedCycleStats
    /// 运动统计（HealthKit 最近 30 天）
    var workoutStats: WorkoutStats
    /// 生活方式（AI 对话提取）
    var lifestyle: Lifestyle
    /// 已知健康状况（AI 对话提取，如 PCOS、痛经史）
    var knownConditions: [String]
    /// 备孕模式开关（默认 false）
    var isTryingToConceive: Bool
    var lastUpdated: Date
    var version: Int

    static let empty = UserProfile(
        bodyInfo: .empty,
        accumulatedStats: .empty,
        workoutStats: .empty,
        lifestyle: .empty,
        knownConditions: [],
        isTryingToConceive: false,
        lastUpdated: .distantPast,
        version: 1
    )

    /// 档案是否基本为空（还没积累过数据）
    var isEmpty: Bool {
        bodyInfo == .empty
            && accumulatedStats.cyclesRecorded == 0
            && workoutStats.topActivities.isEmpty
            && lifestyle == .empty
            && knownConditions.isEmpty
    }

    /// AI 对话提取部分是否还有空字段
    var hasEmptyLifestyleFields: Bool {
        lifestyle.sleepPattern == nil
            || lifestyle.dietaryPreferences.isEmpty
            || knownConditions.isEmpty
    }

    /// 返回还缺少的字段名（中文），供 AI 提示
    var missingFieldNames: [String] {
        var fields: [String] = []
        if lifestyle.sleepPattern == nil { fields.append("睡眠习惯") }
        if lifestyle.dietaryPreferences.isEmpty { fields.append("饮食偏好或禁忌") }
        if knownConditions.isEmpty { fields.append("已知健康状况") }
        if lifestyle.knownSensitivities.isEmpty { fields.append("特殊敏感因素") }
        return fields
    }
}

// 自定义解码放在 extension 中，以保留编译器合成的成员wise init（encode 仍自动合成）。
extension UserProfile {
    private enum CodingKeys: String, CodingKey {
        case bodyInfo, accumulatedStats, workoutStats, lifestyle
        case knownConditions, lastUpdated, version, isTryingToConceive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyInfo = try container.decode(BodyInfo.self, forKey: .bodyInfo)
        accumulatedStats = try container.decode(AccumulatedCycleStats.self, forKey: .accumulatedStats)
        workoutStats = try container.decode(WorkoutStats.self, forKey: .workoutStats)
        lifestyle = try container.decode(Lifestyle.self, forKey: .lifestyle)
        knownConditions = try container.decode([String].self, forKey: .knownConditions)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        version = try container.decode(Int.self, forKey: .version)
        isTryingToConceive = try container.decodeIfPresent(Bool.self, forKey: .isTryingToConceive) ?? false
    }
}

// MARK: - BodyInfo

struct BodyInfo: Codable, Equatable {
    var dateOfBirth: Date?
    var biologicalSex: String?
    var heightCM: Double?
    var weightKG: Double?

    static let empty = BodyInfo()

    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }

    var bmi: Double? {
        guard let h = heightCM, let w = weightKG, h > 0 else { return nil }
        let hm = h / 100.0
        return w / (hm * hm)
    }
}

// MARK: - AccumulatedCycleStats

struct AccumulatedCycleStats: Codable, Equatable {
    /// 历史周期长度列表
    var cycleLengths: [Int]
    /// 历史经期天数列表
    var periodDurations: [Int]
    /// 按经期天数的典型出血量（key = 经期第几天）
    var flowPatternByDay: [String: String]
    /// 按阶段的症状频次：phase.rawValue -> symptomType.rawValue -> count
    var symptomFrequencies: [String: [String: Int]]
    /// 最近 48 小时内仍可视为「当前」的症状快照。
    var recentSymptoms48h: [SymptomEntry]?
    /// 当前周期内记录过的症状快照，仅用于本周期回顾，不等同于当前症状。
    var currentCycleSymptoms: [SymptomEntry]?
    /// 当前周期最近一次出血量快照。
    var currentCycleFlowLevel: FlowLevel?
    /// 已记录的周期数
    var cyclesRecorded: Int
    /// 上次积累日期（每天最多一次）
    var lastAccumulationDate: Date?

    static let empty = AccumulatedCycleStats(
        cycleLengths: [],
        periodDurations: [],
        flowPatternByDay: [:],
        symptomFrequencies: [:],
        recentSymptoms48h: nil,
        currentCycleSymptoms: nil,
        currentCycleFlowLevel: nil,
        cyclesRecorded: 0,
        lastAccumulationDate: nil
    )

    var averageCycleLength: Double? {
        cycleLengths.isEmpty ? nil : Double(cycleLengths.reduce(0, +)) / Double(cycleLengths.count)
    }

    var averagePeriodDuration: Double? {
        periodDurations.isEmpty ? nil : Double(periodDurations.reduce(0, +)) / Double(periodDurations.count)
    }

    /// 某阶段的高频症状（按次数降序，最多取前 5）
    func topSymptoms(for phase: CyclePhase, limit: Int = 5) -> [(symptom: String, count: Int)] {
        guard let freqs = symptomFrequencies[phase.rawValue] else { return [] }
        return freqs.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (symptom: $0.key, count: $0.value) }
    }
}

// MARK: - WorkoutStats

struct WorkoutStats: Codable, Equatable {
    /// 最近 30 天高频运动类型
    var topActivities: [WorkoutActivity]
    /// 今日高频运动类型
    var dailyActivities: [WorkoutActivity]? = nil
    /// 今日运动次数
    var dailyWorkoutCount: Int? = nil
    /// 今日运动总时长（分钟）
    var dailyTotalDurationMinutes: Double? = nil
    /// 今日平均每次运动时长（分钟）
    var dailyAvgDurationMinutes: Double? = nil
    /// 过去 7 天高频运动类型
    var weeklyActivities: [WorkoutActivity]?
    /// 过去 7 天运动次数
    var weeklyWorkoutCount: Int?
    /// 过去 7 天运动总时长（分钟）
    var weeklyTotalDurationMinutes: Double?
    /// 过去 7 天平均每次运动时长（分钟）
    var weeklyAvgDurationMinutes: Double?
    /// 过去 30 天高频运动类型
    var monthlyActivities: [WorkoutActivity]? = nil
    /// 过去 30 天运动次数
    var monthlyWorkoutCount: Int? = nil
    /// 过去 30 天运动总时长（分钟）
    var monthlyTotalDurationMinutes: Double? = nil
    /// 过去 30 天平均每次运动时长（分钟）
    var monthlyAvgDurationMinutes: Double? = nil
    /// 过去 365 天高频运动类型
    var yearlyActivities: [WorkoutActivity]? = nil
    /// 过去 365 天运动次数
    var yearlyWorkoutCount: Int? = nil
    /// 过去 365 天运动总时长（分钟）
    var yearlyTotalDurationMinutes: Double? = nil
    /// 过去 365 天平均每次运动时长（分钟）
    var yearlyAvgDurationMinutes: Double? = nil
    /// 本周（周一起）高频运动类型
    var calendarWeekActivities: [WorkoutActivity]? = nil
    /// 本周（周一起）运动次数
    var calendarWeekWorkoutCount: Int? = nil
    /// 本周（周一起）运动总时长（分钟）
    var calendarWeekTotalDurationMinutes: Double? = nil
    /// 本周（周一起）平均每次运动时长（分钟）
    var calendarWeekAvgDurationMinutes: Double? = nil
    /// 本月（1号起）高频运动类型
    var calendarMonthActivities: [WorkoutActivity]? = nil
    /// 本月（1号起）运动次数
    var calendarMonthWorkoutCount: Int? = nil
    /// 本月（1号起）运动总时长（分钟）
    var calendarMonthTotalDurationMinutes: Double? = nil
    /// 本月（1号起）平均每次运动时长（分钟）
    var calendarMonthAvgDurationMinutes: Double? = nil
    /// 今年（1月1日起）高频运动类型
    var calendarYearActivities: [WorkoutActivity]? = nil
    /// 今年（1月1日起）运动次数
    var calendarYearWorkoutCount: Int? = nil
    /// 今年（1月1日起）运动总时长（分钟）
    var calendarYearTotalDurationMinutes: Double? = nil
    /// 今年（1月1日起）平均每次运动时长（分钟）
    var calendarYearAvgDurationMinutes: Double? = nil
    /// 每周平均运动次数
    var weeklyFrequency: Double
    /// 平均每次运动时长（分钟）
    var avgDurationMinutes: Double
    var lastUpdated: Date?

    static let empty = WorkoutStats(
        topActivities: [],
        dailyActivities: nil,
        dailyWorkoutCount: nil,
        dailyTotalDurationMinutes: nil,
        dailyAvgDurationMinutes: nil,
        weeklyActivities: nil,
        weeklyWorkoutCount: nil,
        weeklyTotalDurationMinutes: nil,
        weeklyAvgDurationMinutes: nil,
        monthlyActivities: nil,
        monthlyWorkoutCount: nil,
        monthlyTotalDurationMinutes: nil,
        monthlyAvgDurationMinutes: nil,
        yearlyActivities: nil,
        yearlyWorkoutCount: nil,
        yearlyTotalDurationMinutes: nil,
        yearlyAvgDurationMinutes: nil,
        calendarWeekActivities: nil,
        calendarWeekWorkoutCount: nil,
        calendarWeekTotalDurationMinutes: nil,
        calendarWeekAvgDurationMinutes: nil,
        calendarMonthActivities: nil,
        calendarMonthWorkoutCount: nil,
        calendarMonthTotalDurationMinutes: nil,
        calendarMonthAvgDurationMinutes: nil,
        calendarYearActivities: nil,
        calendarYearWorkoutCount: nil,
        calendarYearTotalDurationMinutes: nil,
        calendarYearAvgDurationMinutes: nil,
        weeklyFrequency: 0,
        avgDurationMinutes: 0,
        lastUpdated: nil
    )

    struct WorkoutActivity: Codable, Equatable {
        let key: String
        let rawValue: UInt?
        let name: String
        let count: Int
        let totalDurationMinutes: Double?

        init(key: String? = nil, rawValue: UInt? = nil, name: String, count: Int, totalDurationMinutes: Double? = nil) {
            self.key = key ?? name
            self.rawValue = rawValue
            self.name = name
            self.count = count
            self.totalDurationMinutes = totalDurationMinutes
        }

        enum CodingKeys: String, CodingKey {
            case key, rawValue, name, count, totalDurationMinutes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(String.self, forKey: .name)

            self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? name
            self.rawValue = try container.decodeIfPresent(UInt.self, forKey: .rawValue)
            self.name = name
            self.count = try container.decode(Int.self, forKey: .count)
            self.totalDurationMinutes = try container.decodeIfPresent(Double.self, forKey: .totalDurationMinutes)
        }
    }
}

// MARK: - Lifestyle (AI 对话提取)

struct Lifestyle: Codable, Equatable {
    /// 睡眠习惯描述，如"通常 23:00-7:00"
    var sleepPattern: String?
    /// 睡眠习惯提取时间；为空表示旧版本长期画像。
    var sleepPatternObservedAt: Date?
    /// 饮食偏好/禁忌，如["素食", "乳糖不耐"]
    var dietaryPreferences: [String]
    /// 特殊敏感因素，如["咖啡因影响睡眠"]
    var knownSensitivities: [String]
    /// AI 最近一次写入生活方式信息的时间。
    var lastExtractedAt: Date?

    static let empty = Lifestyle(
        sleepPattern: nil,
        sleepPatternObservedAt: nil,
        dietaryPreferences: [],
        knownSensitivities: [],
        lastExtractedAt: nil
    )
}

// MARK: - Credits Billing

struct CreditsPricingPackage: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let priceCNYFen: Int
    let credits: Int
    let sortOrder: Int
}

enum CreditOrderStatus: String, Codable, Equatable {
    case created
    case paying
    case paid
    case failed
    case closed
}

struct CreditRechargeOrder: Codable, Equatable, Identifiable {
    let id: String
    let packageID: String
    let priceCNYFen: Int
    let credits: Int
    var status: CreditOrderStatus
    let createdAt: Date
    var updatedAt: Date
}

enum CreditLedgerEntryType: String, Codable, Equatable {
    case recharge
    case consume
    case refund
    case hold
    case gift
}

enum CreditLedgerSource: String, Codable, Equatable {
    case assistantChat
    case aiSuggestion
    case system
}

struct CreditLedgerEntry: Codable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let type: CreditLedgerEntryType
    let source: CreditLedgerSource
    /// 账本变更（正数为增加，负数为扣减）
    let delta: Int
    /// 变更后的余额快照
    let balanceAfter: Int
    let note: String
    let referenceID: String?
}

struct BillingDailyMetric: Codable, Equatable {
    let dateKey: String
    var assistantChatCount: Int
    var creditsConsumed: Int
    var rechargeOrderCount: Int
    var paidAmountCNYFen: Int
    var refundCredits: Int

    static func empty(dateKey: String) -> BillingDailyMetric {
        BillingDailyMetric(
            dateKey: dateKey,
            assistantChatCount: 0,
            creditsConsumed: 0,
            rechargeOrderCount: 0,
            paidAmountCNYFen: 0,
            refundCredits: 0
        )
    }
}

struct BillingAccountState: Codable, Equatable {
    var creditsBalance: Int
    var freeChatQuotaTotal: Int
    var freeChatQuotaUsed: Int
    /// yyyy-MM-dd -> used free assistant chats
    var freeChatUsageByDay: [String: Int]?
    var subscriptionExpirationDate: Date?
    var subscriptionProductID: String?
    var lowBalanceThresholdCredits: Int
    var orders: [CreditRechargeOrder]
    var ledger: [CreditLedgerEntry]
    var dailyMetrics: [String: BillingDailyMetric]
    var lastAssistantRequestAt: Date?
    var version: Int

    static let initial = BillingAccountState(
        creditsBalance: 0,
        freeChatQuotaTotal: 10,
        freeChatQuotaUsed: 0,
        freeChatUsageByDay: [:],
        subscriptionExpirationDate: nil,
        subscriptionProductID: nil,
        lowBalanceThresholdCredits: 40,
        orders: [],
        ledger: [],
        dailyMetrics: [:],
        lastAssistantRequestAt: nil,
        version: 1
    )

    var freeChatRemaining: Int {
        max(0, freeChatQuotaTotal - freeChatQuotaUsed)
    }
}
