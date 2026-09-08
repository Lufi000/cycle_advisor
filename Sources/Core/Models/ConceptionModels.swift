import Foundation

// MARK: - 干扰标记（仅手动录入可标记）

enum Disturbance: String, Codable, CaseIterable, Identifiable {
    case lateNight
    case alcohol
    case illness
    case insomnia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lateNight: return String(localized: "conception.bbt.disturbance.late_night")
        case .alcohol:   return String(localized: "conception.bbt.disturbance.alcohol")
        case .illness:   return String(localized: "conception.bbt.disturbance.illness")
        case .insomnia:  return String(localized: "conception.bbt.disturbance.insomnia")
        }
    }
}

// MARK: - 基础体温

enum TemperatureSource: String, Codable {
    case wristTemperature   // 手表自动（HealthKit 腕温）
    case manual             // 手动录入兜底
}

struct BasalTemperatureEntry: Codable, Equatable {
    /// 测量日（日粒度，startOfDay）
    var date: Date
    var celsius: Double
    var disturbances: Set<Disturbance>
    var source: TemperatureSource

    /// 合法录入范围，超出拒绝
    static let validRange: ClosedRange<Double> = 35.0...38.0
}

// MARK: - 手表每日生命体征

struct DailyVitals: Codable, Equatable {
    var date: Date
    /// bpm，当日均值
    var restingHeartRate: Double?
    /// ms，当日均值
    var hrvSDNN: Double?
}

// MARK: - 统一症状库

enum SymptomSource: String, Codable {
    case healthKit
    case manual
    case chatExtracted

    /// 去重冲突时保留高优先级来源
    var priority: Int {
        switch self {
        case .manual:        return 3
        case .healthKit:     return 2
        case .chatExtracted: return 1
        }
    }
}

enum PregnancySymptomType: String, Codable, CaseIterable {
    case nausea
    case vomiting
    case fatigue
    case breastTenderness
    case bloating
    case abdominalCramps
    case headache
    case spotting
    case appetiteChange
    case moodChange
    case dizziness

    /// 早孕佐证症状子集（当周期去重计数 ≥ 2 构成一项佐证信号）
    static let earlyPregnancySignals: Set<PregnancySymptomType> = [
        .nausea, .vomiting, .fatigue, .breastTenderness, .spotting
    ]
}

struct SymptomRecord: Codable, Equatable {
    /// 症状发生日（日粒度）
    var date: Date
    var type: PregnancySymptomType
    var source: SymptomSource
}

// MARK: - 验孕结果反馈

enum PregnancyTestFeedback: Codable, Equatable {
    /// 阳性：停止提示
    case positive(date: Date)
    /// 阴性：本周期内不再提示；cycleStart 为反馈时的当周期经期开始日（可能为 nil）
    case negative(date: Date, cycleStart: Date?)
}
