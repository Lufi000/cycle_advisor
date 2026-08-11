import Foundation

// MARK: - Menstrual Flow Level

enum FlowLevel: String, Codable, CaseIterable {
    case unspecified
    case light
    case medium
    case heavy
    case none

    var displayName: String {
        switch self {
        case .unspecified: return String(localized: "flow.unspecified")
        case .light:       return String(localized: "flow.light")
        case .medium:      return String(localized: "flow.medium")
        case .heavy:       return String(localized: "flow.heavy")
        case .none:        return String(localized: "flow.none")
        }
    }

    var emoji: String {
        switch self {
        case .unspecified: return "❓"
        case .light:       return "💧"
        case .medium:      return "💧💧"
        case .heavy:       return "💧💧💧"
        case .none:        return "✨"
        }
    }
}

// MARK: - Symptom Severity

enum SymptomSeverity: String, Codable, CaseIterable {
    case notPresent
    case mild
    case moderate
    case severe

    var displayName: String {
        switch self {
        case .notPresent: return String(localized: "severity.not_present")
        case .mild:       return String(localized: "severity.mild")
        case .moderate:   return String(localized: "severity.moderate")
        case .severe:     return String(localized: "severity.severe")
        }
    }

    var level: Int {
        switch self {
        case .notPresent: return 0
        case .mild:       return 1
        case .moderate:   return 2
        case .severe:     return 3
        }
    }
}

// MARK: - Symptom Entry

struct SymptomEntry: Codable, Equatable, Identifiable {
    let id: String
    let type: SymptomType
    let severity: SymptomSeverity
    let date: Date

    enum SymptomType: String, Codable, CaseIterable {
        case abdominalCramps
        case bloating
        case breastPain
        case headache
        case acne
        case lowerBackPain
        case pelvicPain
        case moodChanges
        case fatigue
        case appetiteChanges

        var displayName: String {
            switch self {
            case .abdominalCramps: return String(localized: "symptom.abdominal_cramps")
            case .bloating:        return String(localized: "symptom.bloating")
            case .breastPain:      return String(localized: "symptom.breast_pain")
            case .headache:        return String(localized: "symptom.headache")
            case .acne:            return String(localized: "symptom.acne")
            case .lowerBackPain:   return String(localized: "symptom.lower_back_pain")
            case .pelvicPain:      return String(localized: "symptom.pelvic_pain")
            case .moodChanges:     return String(localized: "symptom.mood_changes")
            case .fatigue:         return String(localized: "symptom.fatigue")
            case .appetiteChanges: return String(localized: "symptom.appetite_changes")
            }
        }

        var emoji: String {
            switch self {
            case .abdominalCramps: return "🤕"
            case .bloating:        return "🫧"
            case .breastPain:      return "😣"
            case .headache:        return "🤯"
            case .acne:            return "😖"
            case .lowerBackPain:   return "😩"
            case .pelvicPain:      return "😓"
            case .moodChanges:     return "🎭"
            case .fatigue:         return "😴"
            case .appetiteChanges: return "🍽️"
            }
        }

        var iconName: String {
            switch self {
            case .abdominalCramps: return "bolt.heart"
            case .bloating:        return "wind"
            case .breastPain:      return "heart.circle"
            case .headache:        return "brain.head.profile"
            case .acne:            return "face.dashed"
            case .lowerBackPain:   return "figure.stand"
            case .pelvicPain:      return "staroflife"
            case .moodChanges:     return "theatermasks"
            case .fatigue:         return "moon.zzz"
            case .appetiteChanges: return "fork.knife"
            }
        }
    }
}

// MARK: - Menstrual Symptoms (aggregated snapshot)

struct MenstrualSymptoms: Codable, Equatable {
    /// 当前/最近的出血量
    var flowLevel: FlowLevel?
    /// 最近记录的症状列表（当前周期内）
    var recentSymptoms: [SymptomEntry]

    static let empty = MenstrualSymptoms(flowLevel: nil, recentSymptoms: [])

    /// 按严重程度排序的症状（严重的在前）
    var symptomsBySeverity: [SymptomEntry] {
        recentSymptoms.sorted { $0.severity.level > $1.severity.level }
    }

    /// 当前存在的症状（排除 notPresent）
    var activeSymptoms: [SymptomEntry] {
        recentSymptoms.filter { $0.severity != .notPresent }
    }

    /// 用于 AI 上下文的摘要文本
    var contextSummary: String {
        var parts: [String] = []

        if let flow = flowLevel {
            parts.append("出血量：\(flow.displayName)")
        }

        let active = activeSymptoms
        if !active.isEmpty {
            let symptomTexts = active.map { "\($0.type.displayName)(\($0.severity.displayName))" }
            parts.append("症状：\(symptomTexts.joined(separator: "、"))")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "；")
    }
}
