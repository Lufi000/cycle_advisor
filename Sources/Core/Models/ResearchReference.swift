import Foundation

struct ResearchReference: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let authors: String
    let journal: String
    let year: Int
    let doi: String?
    var url: URL? = nil
    let summary: String
    let phases: [CyclePhase]
    let dimensions: [SuggestionDimension]
    let keyFindings: [String]

    /// 简短引用格式："Author et al, Year"
    var shortCitation: String {
        let firstAuthor = authors.components(separatedBy: ",").first ?? authors
        return "\(firstAuthor) et al, \(year)"
    }

    /// 完整引用格式
    var fullCitation: String {
        "\(authors) (\(year)). \(title). \(journal)."
    }
}

struct CitationSource: Identifiable, Hashable {
    let id: String
    let title: String
    let publisher: String
    let summary: String
    let url: URL
}

enum ReferenceLibrary {
    static let menstrualCycleID = "owh-menstrual-cycle"
    static let pmsID = "owh-pms"
    static let activityID = "cdc-physical-activity"
    static let sleepID = "nih-sleep"
    static let nutritionID = "dga-nutrition"
    static let tcmID = "nccih-tcm"

    static var all: [CitationSource] {
        [
            menstrualCycle,
            pms,
            activity,
            sleep,
            nutrition,
            traditionalChineseMedicine
        ]
    }

    static var coreHealth: [CitationSource] {
        [menstrualCycle, pms, nutrition, activity, sleep]
    }

    static var solarTerms: [CitationSource] {
        [traditionalChineseMedicine, nutrition, activity, sleep]
    }

    static func sources(for dimension: SuggestionDimension) -> [CitationSource] {
        switch dimension {
        case .diet:
            return [nutrition, pms, menstrualCycle]
        case .exercise:
            return [activity, pms, menstrualCycle]
        case .mood:
            return [pms, sleep, menstrualCycle]
        case .sleep:
            return [sleep, pms, menstrualCycle]
        }
    }

    static func sources(for phase: CyclePhase) -> [CitationSource] {
        switch phase {
        case .menstrual:
            return [menstrualCycle, pms, nutrition, activity]
        case .follicular, .ovulation:
            return [menstrualCycle, nutrition, activity]
        case .luteal:
            return [menstrualCycle, pms, sleep, nutrition]
        }
    }

    static func sources(forIDs ids: [String]) -> [CitationSource] {
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    static func referenceIDs(for dimension: SuggestionDimension) -> [String] {
        sources(for: dimension).map(\.id)
    }

    private static var menstrualCycle: CitationSource {
        CitationSource(
            id: menstrualCycleID,
            title: String(localized: "citation.owh_menstrual.title"),
            publisher: String(localized: "citation.owh.publisher"),
            summary: String(localized: "citation.owh_menstrual.summary"),
            url: URL(string: "https://womenshealth.gov/menstrual-cycle")!
        )
    }

    private static var pms: CitationSource {
        CitationSource(
            id: pmsID,
            title: String(localized: "citation.owh_pms.title"),
            publisher: String(localized: "citation.owh.publisher"),
            summary: String(localized: "citation.owh_pms.summary"),
            url: URL(string: "https://womenshealth.gov/menstrual-cycle/premenstrual-syndrome")!
        )
    }

    private static var activity: CitationSource {
        CitationSource(
            id: activityID,
            title: String(localized: "citation.cdc_activity.title"),
            publisher: String(localized: "citation.cdc.publisher"),
            summary: String(localized: "citation.cdc_activity.summary"),
            url: URL(string: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")!
        )
    }

    private static var sleep: CitationSource {
        CitationSource(
            id: sleepID,
            title: String(localized: "citation.nih_sleep.title"),
            publisher: String(localized: "citation.nih.publisher"),
            summary: String(localized: "citation.nih_sleep.summary"),
            url: URL(string: "https://www.nhlbi.nih.gov/health/sleep-deprivation")!
        )
    }

    private static var nutrition: CitationSource {
        CitationSource(
            id: nutritionID,
            title: String(localized: "citation.dga_nutrition.title"),
            publisher: String(localized: "citation.dga.publisher"),
            summary: String(localized: "citation.dga_nutrition.summary"),
            url: URL(string: "https://www.dietaryguidelines.gov/")!
        )
    }

    private static var traditionalChineseMedicine: CitationSource {
        CitationSource(
            id: tcmID,
            title: String(localized: "citation.nccih_tcm.title"),
            publisher: String(localized: "citation.nccih.publisher"),
            summary: String(localized: "citation.nccih_tcm.summary"),
            url: URL(string: "https://www.nccih.nih.gov/health/traditional-chinese-medicine-what-you-need-to-know")!
        )
    }
}
