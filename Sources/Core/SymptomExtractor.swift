import Foundation

/// 聊天症状抽取协调：节流 → 调 LLMService → 写入症状库。
/// 失败静默，不影响聊天主链路，不重试（下条消息自然带来新机会）。
actor SymptomExtractor {

    static let shared = SymptomExtractor()

    private let defaultsKeyPrefix = "conception.extracted."

    private init() {}

    func extractAndStore(message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return }

        // 同日已抽取过的消息不重复请求
        let dayKey = Self.dayKey(for: Date())
        let defaultsKey = defaultsKeyPrefix + dayKey
        var extracted = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        guard !extracted.contains(trimmed) else { return }
        extracted.append(trimmed)
        UserDefaults.standard.set(extracted, forKey: defaultsKey)

        do {
            let symptoms = try await LLMService.shared.extractSymptoms(from: trimmed)
            let records = symptoms.map { $0.record() }
            if !records.isEmpty {
                ConceptionStore.shared.addSymptoms(records)
            }
        } catch {
            // 静默丢弃：网络失败 / 解析失败都不影响聊天
        }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
