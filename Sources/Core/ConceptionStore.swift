import Foundation

/// 备孕数据本地存储：手动 BBT、统一症状库、验孕反馈。
/// 手表腕温 / RHR / HRV 不落本地，每次判定时从 HealthKit 现读。
/// 持久化模式与 UserProfileManager 相同（Documents 目录 JSON 文件）。
@Observable
final class ConceptionStore {

    static let shared = ConceptionStore()

    private(set) var manualTemperatures: [BasalTemperatureEntry] = []
    private(set) var symptomRecords: [SymptomRecord] = []
    private(set) var testFeedback: PregnancyTestFeedback?
    private(set) var dismissedUntil: Date?

    private let temperaturesURL: URL
    private let symptomsURL: URL
    private let feedbackURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        temperaturesURL = directory.appendingPathComponent("conception_temperatures.json")
        symptomsURL = directory.appendingPathComponent("conception_symptoms.json")
        feedbackURL = directory.appendingPathComponent("conception_feedback.json")
        load()
    }

    // MARK: - Temperature

    /// 录入手动 BBT。体温超出 35.0–38.0 拒绝（返回 false）；同日重复录入覆盖。
    @discardableResult
    func upsertManualTemperature(date: Date, celsius: Double, disturbances: Set<Disturbance>) -> Bool {
        guard BasalTemperatureEntry.validRange.contains(celsius) else { return false }
        let day = Calendar.current.startOfDay(for: date)
        manualTemperatures.removeAll { Calendar.current.isDate($0.date, inSameDayAs: day) }
        manualTemperatures.append(BasalTemperatureEntry(
            date: day, celsius: celsius, disturbances: disturbances, source: .manual
        ))
        manualTemperatures.sort { $0.date < $1.date }
        saveTemperatures()
        return true
    }

    func manualEntry(for date: Date) -> BasalTemperatureEntry? {
        manualTemperatures.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// 合并手表腕温与手动 BBT：同日以手表为准（夜间多次采样取均值，稳定性优于单次口温）。
    func mergedTemperatures(wrist: [BasalTemperatureEntry]) -> [BasalTemperatureEntry] {
        var byDay: [Date: BasalTemperatureEntry] = [:]
        for entry in manualTemperatures { byDay[entry.date] = entry }
        for entry in wrist { byDay[entry.date] = entry }
        return byDay.values.sorted { $0.date < $1.date }
    }

    // MARK: - Symptoms

    /// 写入症状，按 (日, 类型) 去重；冲突时保留高优先级来源。
    func addSymptoms(_ records: [SymptomRecord]) {
        guard !records.isEmpty else { return }
        for record in records {
            let normalized = SymptomRecord(
                date: Calendar.current.startOfDay(for: record.date),
                type: record.type,
                source: record.source
            )
            if let idx = symptomRecords.firstIndex(where: {
                Calendar.current.isDate($0.date, inSameDayAs: normalized.date) && $0.type == normalized.type
            }) {
                if normalized.source.priority > symptomRecords[idx].source.priority {
                    symptomRecords[idx] = normalized
                }
            } else {
                symptomRecords.append(normalized)
            }
        }
        symptomRecords.sort { $0.date < $1.date }
        saveSymptoms()
    }

    /// 某日起（含当日）的症状记录
    func symptoms(since start: Date) -> [SymptomRecord] {
        let day = Calendar.current.startOfDay(for: start)
        return symptomRecords.filter { $0.date >= day }
    }

    // MARK: - Feedback

    func recordFeedback(_ feedback: PregnancyTestFeedback) {
        testFeedback = feedback
        saveFeedback()
    }

    /// 忽略提示：days 天内不重复提示
    func dismissPrompt(forDays days: Int, from now: Date = .now) {
        dismissedUntil = Calendar.current.date(byAdding: .day, value: days, to: now)
        saveFeedback()
    }

    /// 检测到新经期开始后重置阴性反馈（新周期恢复提示）
    func clearFeedbackIfNewPeriod(lastPeriodStart: Date?) {
        guard let feedback = testFeedback,
              case .negative(_, let cycleStart) = feedback,
              let last = lastPeriodStart,
              let start = cycleStart,
              Calendar.current.startOfDay(for: last) > Calendar.current.startOfDay(for: start)
        else { return }
        testFeedback = nil
        dismissedUntil = nil
        saveFeedback()
    }

    // MARK: - Persistence

    private struct FeedbackState: Codable {
        var testFeedback: PregnancyTestFeedback?
        var dismissedUntil: Date?
    }

    private func saveTemperatures() {
        guard let data = try? JSONEncoder().encode(manualTemperatures) else { return }
        try? data.write(to: temperaturesURL, options: .atomic)
    }

    private func saveSymptoms() {
        guard let data = try? JSONEncoder().encode(symptomRecords) else { return }
        try? data.write(to: symptomsURL, options: .atomic)
    }

    private func saveFeedback() {
        let state = FeedbackState(testFeedback: testFeedback, dismissedUntil: dismissedUntil)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: feedbackURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: temperaturesURL),
           let saved = try? JSONDecoder().decode([BasalTemperatureEntry].self, from: data) {
            manualTemperatures = saved
        }
        if let data = try? Data(contentsOf: symptomsURL),
           let saved = try? JSONDecoder().decode([SymptomRecord].self, from: data) {
            symptomRecords = saved
        }
        if let data = try? Data(contentsOf: feedbackURL),
           let saved = try? JSONDecoder().decode(FeedbackState.self, from: data) {
            testFeedback = saved.testFeedback
            dismissedUntil = saved.dismissedUntil
        }
    }
}
