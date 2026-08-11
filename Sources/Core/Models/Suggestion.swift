import Foundation
import SwiftUI

// MARK: - Suggestion Dimension

enum SuggestionDimension: String, Codable, CaseIterable, Identifiable {
    case diet         // 饮食
    case exercise     // 运动
    case mood         // 情绪
    case sleep        // 睡眠

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diet:     return String(localized: "dim.diet")
        case .exercise: return String(localized: "dim.exercise")
        case .mood:     return String(localized: "dim.mood")
        case .sleep:    return String(localized: "dim.sleep")
        }
    }

    var emoji: String {
        switch self {
        case .diet:     return "🍽"
        case .exercise: return "🏃"
        case .mood:     return "💭"
        case .sleep:    return "😴"
        }
    }

    var iconName: String {
        switch self {
        case .diet:     return "fork.knife"
        case .exercise: return "figure.run"
        case .mood:     return "brain.head.profile"
        case .sleep:    return "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .diet:     return Theme.phaseOvulation
        case .exercise: return Theme.phaseFollicular
        case .mood:     return Theme.phaseLuteal
        case .sleep:    return Theme.phaseMenstrual
        }
    }
}

// MARK: - Suggestion

struct Suggestion: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let dimension: SuggestionDimension
    let title: String
    let details: [String]
    let referenceIds: [String]

    /// 卡片上展示的精简摘要
    var summary: String { title }

    var citationSources: [CitationSource] {
        let explicitSources = ReferenceLibrary.sources(forIDs: referenceIds)
        return explicitSources.isEmpty ? ReferenceLibrary.sources(for: dimension) : explicitSources
    }
}

// MARK: - Suggestion Set

struct SuggestionSet: Codable, Equatable {
    let phase: CyclePhase
    let suggestions: [Suggestion]
    let generatedAt: Date

    func suggestion(for dimension: SuggestionDimension) -> Suggestion? {
        suggestions.first { $0.dimension == dimension }
    }

    /// 尚无 AI 结果时的占位（与 `context.phase` 对齐即可）。
    static func empty(phase: CyclePhase) -> SuggestionSet {
        SuggestionSet(phase: phase, suggestions: [], generatedAt: Date(timeIntervalSince1970: 0))
    }
}
