import Foundation

// MARK: - API Types (OpenAI-compatible)

struct LLMMessage: Codable {
    let role: String    // "system" | "user" | "assistant"
    let content: String
}

struct LLMRequest: Encodable {
    let model: String
    let messages: [LLMMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat?

    struct ResponseFormat: Encodable {
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens     = "max_tokens"
        case responseFormat = "response_format"
    }
}

struct LLMResponse: Decodable {
    let choices: [LLMChoice]
}

struct LLMChoice: Decodable {
    let message: LLMMessage?
    let delta: LLMDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message, delta
        case finishReason = "finish_reason"
    }
}

struct LLMDelta: Decodable {
    let content: String?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}

struct LLMTokenUsage: Equatable {
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}

struct LLMChatStreamResult: Equatable {
    let content: String
    let usage: LLMTokenUsage
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return String(localized: "error.empty_response")
        case .invalidResponse:
            return String(localized: "error.invalid_response")
        case .httpError(let code):
            if code == 401 || code == 403 {
                return String(localized: "error.auth_failed")
            }
            return String(format: String(localized: "error.http_format"), code)
        case .decodingFailed:
            return String(localized: "error.decoding")
        case .networkUnavailable:
            return String(localized: "error.network_unavailable")
        }
    }
}

// MARK: - Thinking Mode

enum ThinkingMode: String, CaseIterable, Identifiable {
    case fast = "fast"
    case deep = "deep"

    var id: String { rawValue }

    var modelName: String {
        switch self {
        case .fast: return "deepseek-chat"
        case .deep: return "deepseek-reasoner"
        }
    }

    var displayName: String {
        switch self {
        case .fast: return String(localized: "thinking.fast")
        case .deep: return String(localized: "thinking.deep")
        }
    }

    var iconName: String {
        switch self {
        case .fast: return "hare.fill"
        case .deep: return "brain.head.profile"
        }
    }

    /// 深度模式有 <think> 推理块
    var hasThinking: Bool { self == .deep }

    /// 流式对话的 max_tokens 上限。
    /// DeepSeek 推理模型把思考（reasoning_content）和正式回答合并计入 max_tokens，
    /// 800 容易被思考耗光导致正式回答为空（finish_reason="length"），深度模式需要更大额度。
    var chatMaxTokens: Int {
        switch self {
        case .fast: return 800
        case .deep: return 4096
        }
    }
}

// MARK: - Service

actor LLMService {

    static let shared = LLMService()

    private let baseURL = URL(string: Secrets.baseURL)!
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// 当前思考模式，通过 UserDefaults 持久化
    nonisolated var thinkingMode: ThinkingMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "thinkingMode") ?? "fast"
            return ThinkingMode(rawValue: raw) ?? .fast
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "thinkingMode")
        }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config)
    }

    // MARK: - Private Helpers

    private func sendRequest<T: Decodable>(_ body: LLMRequest, timeout: TimeInterval? = nil) async throws -> T {
        let urlRequest = try buildURLRequest(for: body, timeout: timeout)
        print("[LLM] sendRequest → \(urlRequest.url?.absoluteString ?? "nil")")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            print("[LLM] network error: \(error)")
            throw LLMError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            print("[LLM] invalid response type")
            throw LLMError.invalidResponse
        }
        print("[LLM] status: \(http.statusCode)")
        guard http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                print("[LLM] error body: \(body)")
            }
            throw LLMError.httpError(statusCode: http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func buildURLRequest(for body: LLMRequest, timeout: TimeInterval? = nil) throws -> URLRequest {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.appToken, forHTTPHeaderField: "X-App-Token")
        if let timeout {
            req.timeoutInterval = timeout
        }
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    /// 兼容 `data: xxx` 与 `data:xxx` 两种 SSE 行格式，忽略 [DONE]
    private nonisolated static func sseData(from line: String) -> Data? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }
        return payload.data(using: .utf8)
    }

    /// 从 AI 响应内容中清理出纯 JSON
    private nonisolated static func cleanContent(_ raw: String) -> String {
        var s = raw
        // 去除 <think>...</think> 推理块（DeepSeek reasoning）
        if let thinkEnd = s.range(of: "</think>") {
            s = String(s[thinkEnd.upperBound...])
        }
        // 去除 markdown 代码块围栏
        s = s.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    // MARK: - Chat (multi-turn, plain text)

    /// 多轮对话流式调用。onToken 接收增量文本片段，onThinking 接收推理块（Deep 模式）。
    func streamChat(
        history: [LLMMessage],
        systemPrompt: String,
        onToken: @escaping (String) -> Void,
        onThinking: @escaping (String) -> Void
    ) async throws -> LLMChatStreamResult {
        let request = LLMRequest(
            model: thinkingMode.modelName,
            messages: [LLMMessage(role: "system", content: systemPrompt)] + history,
            stream: true,
            temperature: 0.70,
            maxTokens: thinkingMode.chatMaxTokens,
            responseFormat: nil
        )

        let urlRequest = try buildURLRequest(for: request)
        let asyncBytes: URLSession.AsyncBytes
        let httpResponse: URLResponse
        do {
            (asyncBytes, httpResponse) = try await session.bytes(for: urlRequest)
        } catch {
            print("[LLM] streamChat network error: \(error)")
            throw LLMError.networkUnavailable
        }

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (httpResponse as? HTTPURLResponse)?.statusCode ?? -1
            print("[LLM] streamChat status: \(code)")
            throw LLMError.httpError(statusCode: code)
        }

        var fullContent = ""
        var fullReasoning = ""
        var emittedLength = 0

        do {
            for try await line in asyncBytes.lines {
                guard let data = Self.sseData(from: line),
                      let parsed = try? decoder.decode(LLMResponse.self, from: data)
                else { continue }

                let choice = parsed.choices.first

                // DeepSeek reasoner 把推理过程放在独立字段；非推理模型该字段为空，分支自然跳过
                if let reasoning = choice?.delta?.reasoningContent, !reasoning.isEmpty {
                    fullReasoning += reasoning
                    onThinking(fullReasoning)
                }

                let chunk = choice?.delta?.content ?? choice?.message?.content ?? ""
                if !chunk.isEmpty {
                    fullContent += chunk
                    let cleaned = Self.cleanContent(fullContent)
                    if cleaned.count > emittedLength {
                        let newPart = String(cleaned.dropFirst(emittedLength))
                        onToken(newPart)
                        emittedLength = cleaned.count
                    }
                }

                if choice?.finishReason == "stop" { break }
            }
        } catch {
            print("[LLM] streamChat read error: \(error)")
            throw LLMError.networkUnavailable
        }

        let cleaned = Self.cleanContent(fullContent)
        guard !cleaned.isEmpty else {
            throw LLMError.emptyResponse
        }
        let inputTokens = Self.estimateTokenCount(messages: request.messages)
        let outputTokens = Self.estimateTokenCount(from: cleaned)
        return LLMChatStreamResult(
            content: cleaned,
            usage: LLMTokenUsage(inputTokens: inputTokens, outputTokens: outputTokens)
        )
    }

    // MARK: - Suggested Questions Generation

    private static let utilityModelName = ThinkingMode.fast.modelName
    private static let questionsMaxTokens = 300

    func generateSuggestedQuestions(for context: CycleContext) async throws -> [String] {
        let request = LLMRequest(
            model: Self.utilityModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildSuggestedQuestionsSystemPrompt()),
                LLMMessage(role: "user", content: Self.buildContextLines(context: context).joined(separator: "\n"))
            ],
            stream: false,
            temperature: 0.65,
            maxTokens: Self.questionsMaxTokens,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request)
        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }
        return (try? Self.parseQuestions(from: content)) ?? []
    }

    /// 根据本轮问答与周期上下文，生成 3 条衔接自然的后续提问（非流式、fast 模型）
    func generateChatFollowUpQuestions(
        context: CycleContext,
        userQuestion: String,
        assistantReply: String,
        recentDialogue: String = "",
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) async throws -> [String] {
        let request = LLMRequest(
            model: Self.utilityModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildChatFollowUpQuestionsSystemPrompt(responseLanguage: responseLanguage)),
                LLMMessage(
                    role: "user",
                    content: Self.buildChatFollowUpUserPrompt(
                        context: context,
                        userQuestion: userQuestion,
                        assistantReply: assistantReply,
                        recentDialogue: recentDialogue,
                        responseLanguage: responseLanguage
                    )
                )
            ],
            stream: false,
            temperature: 0.62,
            maxTokens: Self.questionsMaxTokens,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request)
        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }
        let parsed = (try? Self.parseQuestions(from: content)) ?? []
        return Array(parsed.prefix(3))
    }

    func generateWorkoutSummary(
        context: CycleContext,
        profile: UserProfile?,
        featuredActivity: WorkoutStats.WorkoutActivity,
        count: Int,
        totalDurationMinutes: Double,
        periodLabel: String,
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) async throws -> String {
        let request = LLMRequest(
            model: Self.utilityModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildWorkoutSummarySystemPrompt(responseLanguage: responseLanguage)),
                LLMMessage(
                    role: "user",
                    content: Self.buildWorkoutSummaryUserPrompt(
                        context: context,
                        profile: profile,
                        featuredActivity: featuredActivity,
                        count: count,
                        totalDurationMinutes: totalDurationMinutes,
                        periodLabel: periodLabel,
                        responseLanguage: responseLanguage
                    )
                )
            ],
            stream: false,
            temperature: 0.72,
            maxTokens: 140,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request, timeout: 20)
        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }
        return try Self.parseWorkoutSummary(from: content)
    }

    private nonisolated static func parseQuestions(from content: String) throws -> [String] {
        let cleaned = cleanContent(content)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        // 优先：直接 JSON 数组
        if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [String] {
            return arr.filter { !$0.isEmpty }
        }
        // 兼容：{ "questions": [...] } 或 { "问题": [...] }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let arr = (obj["questions"] as? [String]) ?? (obj["问题"] as? [String]) ?? []
            return arr.filter { !$0.isEmpty }
        }
        return []
    }

    private nonisolated static func parseWorkoutSummary(from content: String) throws -> String {
        let cleaned = cleanContent(content)
        guard let data = cleaned.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let summary = obj["summary"] as? String
        else {
            throw LLMError.decodingFailed(cleaned)
        }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    // MARK: - Prompt Builders

    enum ResponseLanguage: Equatable {
        case simplifiedChinese
        case traditionalChinese
        case english
        case japanese
        case korean
        case spanish
        case french

        var displayName: String {
            switch self {
            case .simplifiedChinese: return "简体中文"
            case .traditionalChinese: return "繁體中文"
            case .english: return "English"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .spanish: return "Español"
            case .french: return "Français"
            }
        }

        var followUpFallbackQuestions: [String] {
            switch self {
            case .simplifiedChinese:
                return [
                    "能给我一个今天就能执行的版本吗？",
                    "如果作息被打乱，怎么调整更稳妥？",
                    "有哪些常见误区我需要先避开？",
                ]
            case .traditionalChinese:
                return [
                    "能給我一個今天就能執行的版本嗎？",
                    "如果作息被打亂，怎麼調整更穩妥？",
                    "有哪些常見誤區我需要先避開？",
                ]
            case .english:
                return [
                    "Can you make this actionable for today?",
                    "How should I adjust if my routine changes?",
                    "What common mistakes should I avoid?",
                ]
            case .japanese:
                return [
                    "今日すぐ実践できるバージョンにしてもらえますか？",
                    "生活リズムが崩れたときは、どう調整するのが安心ですか？",
                    "避けておきたいよくある誤解はありますか？",
                ]
            case .korean:
                return [
                    "오늘 바로 실행할 수 있는 버전으로 알려줄 수 있나요?",
                    "생활 리듬이 흐트러지면 어떻게 조정하는 게 안전할까요?",
                    "미리 피해야 할 흔한 오해가 있을까요?",
                ]
            case .spanish:
                return [
                    "¿Puedes darme una versión que pueda aplicar hoy mismo?",
                    "¿Cómo debería ajustarlo si mi rutina se altera?",
                    "¿Qué errores comunes debería evitar?",
                ]
            case .french:
                return [
                    "Pouvez-vous me donner une version applicable dès aujourd'hui ?",
                    "Comment dois-je m'adapter si ma routine est perturbée ?",
                    "Quelles erreurs courantes dois-je éviter ?",
                ]
            }
        }
    }

    /// 语言完全跟随系统：按当前 Locale 推断 AI 回复语言，不支持的语种回退英文。
    nonisolated static func preferredResponseLanguage(
        locale: Locale = .current
    ) -> ResponseLanguage {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("fr") { return .french }
        if identifier.hasPrefix("zh") {
            // zh-Hant / zh-HK / zh-TW / zh-MO 等按繁体处理，其余中文按简体。
            return identifier.contains("hant") || identifier.contains("-hk") || identifier.contains("-tw") || identifier.contains("-mo")
                ? .traditionalChinese
                : .simplifiedChinese
        }
        return .english
    }

    nonisolated static func responseLanguage(
        for text: String,
        fallback: ResponseLanguage = .simplifiedChinese
    ) -> ResponseLanguage {
        let normalized = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if normalized.allSatisfy(["hello", "hi", "hey", "yo"].contains),
           (1...2).contains(normalized.count) {
            return fallback
        }

        var cjkCount = 0
        var latinCount = 0
        var kanaCount = 0
        var hangulCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                cjkCount += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                kanaCount += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                hangulCount += 1
            default:
                continue
            }
        }

        // 平假名/片假名是日语的强信号；谚文是韩语的强信号。优先于汉字与拉丁字母判断。
        if kanaCount > 0 {
            return .japanese
        }

        if hangulCount > 0 {
            return .korean
        }

        if cjkCount > 0 {
            return .simplifiedChinese
        }

        if latinCount > 0 {
            return .english
        }
        return fallback
    }

    /// 提取用户当前状态的文本行（供多个 prompt builder 复用）
    nonisolated static func buildContextLines(context: CycleContext) -> [String] {
        let m = context.healthMetrics
        var lines: [String] = []

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let timeHM = String(format: "%d:%02d", hour, minute)

        let phaseNames: [CyclePhase: String] = [
            .menstrual: "经期",
            .follicular: "卵泡期",
            .ovulation: "排卵期",
            .luteal: "黄体期"
        ]
        let phaseName = phaseNames[context.phase] ?? context.phase.rawValue

        let predNote = context.isPredicted ? "（推算，用户未录入新经期）" : ""
        lines.append("当前周期阶段：\(phaseName)（阶段第 \(context.dayInPhase) 天）\(predNote)")
        lines.append("本次周期第 \(context.cycleDay) 天，平均周期 \(context.avgCycleLength) 天")

        if let hrv = m.hrvCurrent {
            var hrvLine = "HRV：\(Int(hrv))ms"
            if let avg = m.hrvWeeklyAvg { hrvLine += "（周均 \(Int(avg))ms）" }
            if let trend = m.hrvTrend { hrvLine += " 趋势\(trend.symbol)" }
            lines.append(hrvLine)
        }

        if let hr = m.restingHR {
            lines.append("静息心率：\(Int(hr)) bpm")
        }

        if let daylight = m.formattedDaylightDuration {
            var sunLine = "今日日照时间：\(daylight)"
            if let trend = m.daylightTrend { sunLine += " 趋势\(trend.symbol)" }
            lines.append(sunLine)
        }

        if let exercise = m.formattedExerciseDuration {
            var exLine = "今日锻炼时长：\(exercise)（Apple 健身记录运动分钟）"
            if let trend = m.exerciseTrend { exLine += " 趋势\(trend.symbol)" }
            lines.append(exLine)
        }

        if let todayWorkouts = m.todayWorkouts, !todayWorkouts.isEmpty {
            let desc = todayWorkouts.map { activity -> String in
                if let duration = activity.totalDurationMinutes, duration > 0 {
                    return "\(activity.name) \(Self.formatWorkoutDuration(duration))"
                }
                return activity.name
            }
            .joined(separator: "、")
            lines.append("今日具体运动：\(desc)（来自 HealthKit 运动记录；与 Apple 健身圆环锻炼分钟口径不同）")
        }

        if let sleep = m.formattedSleepDurationForPrompt {
            var sleepLine = "最近一次睡眠：\(sleep)"
            if let trend = m.sleepTrend { sleepLine += " 趋势\(trend.symbol)" }
            lines.append(sleepLine)
        }

        if let water = m.formattedWaterIntakeForPrompt {
            lines.append("今日饮水：\(water)（截至目前累计）")
        }

        if let mindful = m.formattedMindfulDurationForPrompt {
            lines.append("近7天正念/放松记录：\(mindful)")
        }

        if let steps = m.formattedSteps {
            var actLine = "今日活动：\(steps) 步"
            if let cal = m.activeCalories { actLine += " 消耗 \(Int(cal)) kcal" }
            // 上午/午间前「今日」累计天然偏低，避免模型解读为「活动不足」并引发焦虑
            if hour < 12 {
                actLine += "（截至目前累计；上午该数值通常仍低，不代表全天活动不足）"
            } else if hour < 15 {
                actLine += "（截至目前累计，全日活动数据仍在更新）"
            }
            lines.append(actLine)
        }

        if hour < 12 {
            lines.append("【表述约束】当前为上午（本地约 \(timeHM)），今日步数/消耗为截至目前累计；请勿在输出中暗示用户今日活动太少、懈怠，或使用易引发焦虑的评判语气。")
        } else if hour < 15 {
            lines.append("【表述约束】当前约 \(timeHM)，今日活动数据仍在累积；请勿仅凭当前累计步数/消耗断定用户「活动不足」或施压。")
        }

        // 经期症状档案：当前症状只取最近 48 小时；本周期症状仅作为周期回顾。
        if context.phase == .menstrual {
            if let flow = context.menstrualSymptoms.flowLevel {
                lines.append("当前经期出血量：\(flow.displayName)")
            }

            let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
            let currentSymptoms = context.menstrualSymptoms.activeSymptoms.filter { $0.date >= twoDaysAgo }
            if !currentSymptoms.isEmpty {
                let desc = currentSymptoms.map { "\($0.type.displayName)(\($0.severity.displayName))" }
                    .joined(separator: "、")
                lines.append("当前症状（最近48小时）：\(desc)")
            }

            let cycleSymptoms = context.menstrualSymptoms.activeSymptoms
            if currentSymptoms.isEmpty, !cycleSymptoms.isEmpty {
                let desc = cycleSymptoms.map { "\($0.type.displayName)(\($0.severity.displayName)，\(Self.relativeDayLabel(for: $0.date, now: now)))" }
                    .joined(separator: "、")
                lines.append("本周期曾记录症状（历史记录，仅作周期回顾参考；非当前症状，回答时必须带「当时/过去」时间表述，不要说成现在有）：\(desc)")
            }
        }

        return lines
    }

    nonisolated static func buildWorkoutSummarySystemPrompt(
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) -> String {
        """
        你是周期生活应用里的运动小结文案模块。请根据用户的健康数据和运动记录，生成一段显示在运动称号标题下方的短小结。

        要求：
        - 回复语言必须使用：\(responseLanguage.displayName)
        - 只输出 JSON：{"summary":"..."}
        - summary 只写 1 句，中文 35-55 字；英文 18-28 words
        - 语气温柔、具体、有画面感，不评判、不催促、不制造焦虑
        - 可以结合主要运动类型，但不要每种运动都套同一句模板
        - 提到运动时长时，超过 1 小时请用「小时」表达（如“约 10 小时”），不要写成几百分钟的原始数字
        - 严格使用输入中的运动周期（本周/本月/今年 或对应英文）来组织文案；文案中提到时间范围时只能使用该周期，不要写成「这周」或其他周期
        - 周期状态只作为内部参考，用来把强度和语气放轻重；summary 里不要直接写出周期阶段
        - 禁止出现这些阶段词：经期、月经期、卵泡期、排卵期、黄体期、menstrual、period、follicular、ovulation、luteal
        - 不使用「治疗」「诊断」「医嘱」等医疗措辞
        - 不夸大运动与周期/症状的因果关系
        - 不要提到“AI”“数据”“HealthKit”“标题下方”
        """
    }

    nonisolated static func buildWorkoutSummaryUserPrompt(
        context: CycleContext,
        profile: UserProfile?,
        featuredActivity: WorkoutStats.WorkoutActivity,
        count: Int,
        totalDurationMinutes: Double,
        periodLabel: String,
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) -> String {
        let contextSummary = buildContextLines(context: context).joined(separator: "\n")
        let profileSummary = buildProfileSummary(profile: profile)
        let activityDuration = featuredActivity.totalDurationMinutes.map { Self.formatWorkoutDuration($0, language: responseLanguage) } ?? "未记录时长"

        let sectionHeader: String
        let countLine: String
        let durationLine: String
        let periodInstruction: String
        switch responseLanguage {
        case .simplifiedChinese:
            sectionHeader = "【\(periodLabel)运动】"
            countLine = "\(periodLabel)运动总次数：\(count)"
            durationLine = "\(periodLabel)运动总时长：\(Self.formatWorkoutDuration(totalDurationMinutes))"
            periodInstruction = "这是\(periodLabel)的运动小结：文案中若提到时间范围，请使用「\(periodLabel)」，不要写成其他周期（例如「这周」）。"
        case .traditionalChinese:
            sectionHeader = "【\(periodLabel)運動】"
            countLine = "\(periodLabel)運動總次數：\(count)"
            durationLine = "\(periodLabel)運動總時長：\(Self.formatWorkoutDuration(totalDurationMinutes, language: .traditionalChinese))"
            periodInstruction = "這是\(periodLabel)的運動小結：文案中若提到時間範圍，請使用「\(periodLabel)」，不要寫成其他週期（例如「這週」）。"
        case .english:
            sectionHeader = "【\(periodLabel) workouts】"
            countLine = "Total workouts in \(periodLabel): \(count)"
            durationLine = "Total duration in \(periodLabel): \(Self.formatWorkoutDuration(totalDurationMinutes, language: .english))"
            periodInstruction = "This is the \(periodLabel) workout summary. If you mention a time span, use '\(periodLabel)' only — do not write 'this week' or any other period."
        case .japanese:
            sectionHeader = "【\(periodLabel)のワークアウト】"
            countLine = "\(periodLabel)のワークアウト回数：\(count)"
            durationLine = "\(periodLabel)のワークアウト総時間：\(Self.formatWorkoutDuration(totalDurationMinutes, language: .japanese))"
            periodInstruction = "これは\(periodLabel)のワークアウトまとめです。時間範囲に触れる場合は「\(periodLabel)」だけを使い、「今週」など別の周期で書かないでください。"
        case .korean:
            sectionHeader = "【\(periodLabel) 운동】"
            countLine = "\(periodLabel) 운동 총 횟수: \(count)"
            durationLine = "\(periodLabel) 운동 총 시간: \(Self.formatWorkoutDuration(totalDurationMinutes, language: .korean))"
            periodInstruction = "이것은 \(periodLabel) 운동 요약입니다. 시간 범위를 언급할 때는 '\(periodLabel)'만 사용하고, '이번 주'처럼 다른 주기로 쓰지 마세요."
        case .spanish:
            sectionHeader = "【\(periodLabel) entrenamientos】"
            countLine = "Entrenamientos totales en \(periodLabel): \(count)"
            durationLine = "Duración total en \(periodLabel): \(Self.formatWorkoutDuration(totalDurationMinutes, language: .spanish))"
            periodInstruction = "Este es el resumen de entrenamientos de \(periodLabel). Si mencionas un período de tiempo, usa solo '\(periodLabel)'; no escribas 'esta semana' ni ningún otro período."
        case .french:
            sectionHeader = "【\(periodLabel) entraînements】"
            countLine = "Nombre total d'entraînements sur \(periodLabel) : \(count)"
            durationLine = "Durée totale sur \(periodLabel) : \(Self.formatWorkoutDuration(totalDurationMinutes, language: .french))"
            periodInstruction = "Voici le résumé des entraînements de \(periodLabel). Si tu mentionnes une période, utilise uniquement « \(periodLabel) » — n'écris pas « cette semaine » ni aucune autre période."
        }

        return """
        【内部参考：用户当前状态，不要在输出中点名周期阶段】
        \(contextSummary)
        \(profileSummary)

        \(sectionHeader)
        主运动：\(featuredActivity.name)
        主运动次数：\(featuredActivity.count)
        主运动时长：\(activityDuration)
        \(countLine)
        \(durationLine)
        \(periodInstruction)

        请生成 \(responseLanguage.displayName) 的 summary。只输出 JSON，不要其他说明。
        """
    }

    /// 把分钟数格式化成文案里更自然的时长：超过 1 小时用「小时」表达。
    nonisolated static func formatWorkoutDuration(
        _ minutes: Double,
        language: ResponseLanguage = .simplifiedChinese
    ) -> String {
        let total = max(0, Int(minutes.rounded()))
        let hours = total / 60
        let mins = total % 60
        switch language {
        case .simplifiedChinese:
            if hours > 0, mins > 0 { return "约 \(hours) 小时 \(mins) 分钟" }
            if hours > 0 { return "约 \(hours) 小时" }
            return "约 \(mins) 分钟"
        case .traditionalChinese:
            if hours > 0, mins > 0 { return "約 \(hours) 小時 \(mins) 分鐘" }
            if hours > 0 { return "約 \(hours) 小時" }
            return "約 \(mins) 分鐘"
        case .english:
            if hours > 0, mins > 0 { return "about \(hours) hours \(mins) minutes" }
            if hours > 0 { return "about \(hours) hours" }
            return "about \(mins) minutes"
        case .japanese:
            if hours > 0, mins > 0 { return "約 \(hours) 時間 \(mins) 分" }
            if hours > 0 { return "約 \(hours) 時間" }
            return "約 \(mins) 分"
        case .korean:
            if hours > 0, mins > 0 { return "약 \(hours)시간 \(mins)분" }
            if hours > 0 { return "약 \(hours)시간" }
            return "약 \(mins)분"
        case .spanish:
            if hours > 0, mins > 0 { return "aprox. \(hours) h \(mins) min" }
            if hours > 0 { return "aprox. \(hours) h" }
            return "aprox. \(mins) min"
        case .french:
            if hours > 0, mins > 0 { return "environ \(hours) h \(mins) min" }
            if hours > 0 { return "environ \(hours) h" }
            return "environ \(mins) min"
        }
    }

    /// 对话助手的 System Prompt：注入周期上下文 + 用户档案，设定温暖体贴语气
    nonisolated static func buildChatSystemPrompt(
        context: CycleContext,
        profile: UserProfile? = nil,
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) -> String {
        let contextSummary = buildContextLines(context: context).joined(separator: "\n")
        let profileSummary = buildProfileSummary(profile: profile)
        let missingHint = buildMissingFieldsHint(profile: profile)
        return """
        你是月经周期生活方式顾问"周期助理"，语气温暖体贴，像关心朋友的闺蜜，偶尔使用 emoji 增加亲切感。

        规则：
        - 提供可操作的生活方式建议，含具体做法/份量/时间
        - 禁用「治疗」「诊断」「医嘱」等医疗措辞，不做医学因果断定
        - 若摘要中注明上午或活动数据仍在累积：不得因今日步数/消耗暂时偏低而批评用户；避免「活动太少」「不够」等施压表述
        - 若用户状态包含「当前症状（最近48小时）」：当用户问题与该症状相关时，回答要充分考虑用户当前的经期症状和出血量，针对性地提供缓解建议，语气要更加温柔体贴
        - 症状默认不主动提起：用户没提到的话题相关症状（如腰痛、头痛等），除非用户当前问题与之直接相关（主动提到该症状、问运动强度是否合适、问近期身体状态等），否则不要把症状写进回答；症状只作为内部背景来调整语气和建议，不要罗列
        - 若只出现「本周期曾记录症状」或「历史高频症状」：只能作为历史参考，不要说成用户现在有这些症状
        - 时间口径必须严格按数据标注表述（今日 / 最近48小时 / 过去7天 / 近30天 / 本周期 / 历史）：只有标注「当前/今日/最近48小时」的数据才算现在的事实；「过去7天」「近30天」「本周期曾记录」「历史」等一律是过去参考，引用时必须带上明确时间范围（如「上周」「近一个月」），严禁把过去的数据说成今天或当前状态
        - 若提供了「用户个人画像」：回答应结合用户的身体数据、运动偏好、历史周期规律等个人化信息
        - 遇到诊断/疾病相关问题：先一句话直接说明需要医生判断，再简短提供生活层面可参考的内容
        - 输出纯文本，可用加粗和换行，不输出 JSON 或 markdown 代码块
        - 回复语言必须使用：\(responseLanguage.displayName)。即使系统提示、用户状态或用户画像是中文，也要用该语言回复；不要因为上下文是中文而切换语言

        画像使用要求：
        - 回答前优先看：当前周期阶段/当前症状 > 用户这次问题 > 用户个人画像 > 历史参考；不要把历史症状或旧版画像当作当前事实
        - 当用户问题与饮食、运动、睡眠、症状、周期规律相关时，答案必须至少引用 1 条相关画像信息，例如饮食偏好、敏感因素、常做运动、近期睡眠、历史周期规律或当前症状
        - 若画像中有禁忌/偏好（如素食、乳糖不耐、咖啡因影响睡眠），建议必须避开冲突方案，并主动给出匹配替代选项
        - 若用户提到咖啡因影响睡眠，下午/晚上饮食建议要避开咖啡、奶茶、浓茶、可可和巧克力，优先给无咖啡因替代
        - 若画像中有用户常做运动，优先把建议改写成用户熟悉的运动形式；不要泛泛建议“去运动”
        - 若当前症状包含疼痛/痉挛/疲劳，运动建议要明确写出“低强度”或“降低强度”，并说明今天先不跑步/不做高强度
        - 如果用户画像/状态重点含有“咖啡因”，回答必须明确出现“咖啡因”，并说明下午/晚上避开含咖啡因选择
        - 只有当用户画像/状态重点明确含有“历史”或“非当前状态”时，才使用“历史记录”措辞；这种情况下第一段必须写清楚“不代表你现在有这些症状”
        - 如果用户画像/状态重点没有“历史”或“非当前状态”，不要使用“历史记录”开头
        - 若画像信息不足，只问 1 个最有助于回答当前问题的澄清问题，并同时给出可先执行的保守建议
        - 不要为了显得个性化而复述所有画像；只使用与当前问题直接相关的信息

        用户当前状态：
        \(contextSummary)
        \(profileSummary)
        \(missingHint)
        """
    }

    /// 推荐问题的 System Prompt
    nonisolated static func buildSuggestedQuestionsSystemPrompt() -> String {
        """
        根据用户当前周期状态和今日健康数据，生成 3 个用户最可能想问的问题。
        要求：贴合当前阶段特点，涵盖不同维度（运动/饮食/情绪/睡眠），语气口语化，像真人会自然提出的问题。
        若用户摘要中注明上午或今日活动尚在累积：不要生成围绕「今天活动/步数是不是太少」的焦虑导向问题。
        只输出纯 JSON 数组，不含其他文字，格式：{"questions":["问题1","问题2","问题3"]}
        """
    }

    /// 对话追问推荐：基于刚结束的问答与用户状态，避免与上文完全重复
    nonisolated static func buildChatFollowUpQuestionsSystemPrompt(
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) -> String {
        """
        你是月经周期生活方式顾问的「追问推荐」模块，输出仅供用户点击参考，非医疗诊断。

        必须先完整阅读【助手上一答】全文与【近期对话摘录】后，再生成恰好 3 个用户很可能接着问的问题。
        要求：
        - 问题语言必须使用：\(responseLanguage.displayName)
        - 与上文话题自然衔接，可延伸细节、原理、执行步骤、替代方案、注意事项，或与周期/睡眠/情绪/饮食的关联
        - 3 个问题尽量覆盖不同角度，避免句式雷同或与用户原问题高度重复
        - 口语化、简短（中文单条原则上不超过 28 字；英文单条原则上不超过 60 characters）
        - 不出现「治疗」「诊断」「医嘱」等医疗措辞；不暗示替代就医
        - 不得编造用户当前状态摘要中没有出现的具体指标、周期信息或症状

        只输出 JSON，格式：{"questions":["问题1","问题2","问题3"]}
        """
    }

    nonisolated static func buildChatFollowUpUserPrompt(
        context: CycleContext,
        userQuestion: String,
        assistantReply: String,
        recentDialogue: String,
        responseLanguage: ResponseLanguage = .simplifiedChinese
    ) -> String {
        let lines = buildContextLines(context: context).joined(separator: "\n")
        let cap = 3600
        let reply = assistantReply.count > cap
            ? String(assistantReply.prefix(cap)) + "\n…（下文已省略）"
            : assistantReply
        let dialogueBlock: String
        if recentDialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dialogueBlock = "（无多轮摘录，仅以上一轮为准）"
        } else {
            dialogueBlock = recentDialogue
        }
        return """
        【用户当前状态】
        \(lines)

        【近期对话摘录】（含本轮，用于理解语境）
        \(dialogueBlock)

        【用户上一问】
        \(userQuestion)

        【助手上一答】
        \(reply)

        请生成 \(responseLanguage.displayName) 问题。只输出 JSON，不要其他说明。
        """
    }

    // MARK: - Profile Prompt Builders

    /// 将用户档案格式化为 prompt 文本
    nonisolated static func buildProfileSummary(profile: UserProfile?) -> String {
        guard let profile, !profile.isEmpty else { return "" }
        var lines: [String] = []

        // 身体信息
        let body = profile.bodyInfo
        var bodyParts: [String] = []
        if let age = body.age { bodyParts.append("年龄：\(age)") }
        if let h = body.heightCM { bodyParts.append("身高：\(String(format: "%.0f", h))cm") }
        if let w = body.weightKG { bodyParts.append("体重：\(String(format: "%.1f", w))kg") }
        if !bodyParts.isEmpty { lines.append(bodyParts.joined(separator: "，")) }

        // 周期统计
        let stats = profile.accumulatedStats
        if let avg = stats.averageCycleLength {
            lines.append("历史平均周期：\(String(format: "%.0f", avg)) 天（基于 \(stats.cyclesRecorded) 个周期）")
        }
        if let avg = stats.averagePeriodDuration {
            lines.append("平均经期时长：\(String(format: "%.0f", avg)) 天")
        }
        if !stats.flowPatternByDay.isEmpty {
            let sorted = stats.flowPatternByDay.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
            let desc = sorted.compactMap { day, flow -> String? in
                guard let level = FlowLevel(rawValue: flow) else { return nil }
                return "第\(day)天\(level.displayName)"
            }.joined(separator: "、")
            if !desc.isEmpty { lines.append("典型出血量模式：\(desc)") }
        }

        // 高频症状：历史参考，不能描述成当前症状
        let historyWindowLabel = stats.cyclesRecorded > 0
            ? "（近 \(stats.cyclesRecorded) 个周期记录；历史参考，非当前状态）"
            : "（历史参考，非当前状态，不代表现在有）"
        for phase in CyclePhase.allCases {
            let top = stats.topSymptoms(for: phase, limit: 3)
            if !top.isEmpty {
                let desc = top.map { item in
                    let name = SymptomEntry.SymptomType(rawValue: item.symptom)?.displayName ?? item.symptom
                    return "\(name)(\(item.count)次)"
                }.joined(separator: "、")
                lines.append("历史\(phase.displayName)高频症状\(historyWindowLabel)：\(desc)")
            }
        }

        // 运动统计
        let workouts = profile.workoutStats
        let weekRange = Self.rollingDateRangeLabel(daysBack: 7)
        if let weeklyCount = workouts.weeklyWorkoutCount {
            if weeklyCount > 0 {
                let activities = (workouts.weeklyActivities ?? [])
                    .map { activity -> String in
                        if let duration = activity.totalDurationMinutes, duration > 0 {
                            return "\(activity.name) \(activity.count)次/\(Self.formatWorkoutDuration(duration))"
                        }
                        return "\(activity.name) \(activity.count)次"
                    }
                    .joined(separator: "、")
                let total = workouts.weeklyTotalDurationMinutes.map { "，总时长\(Self.formatWorkoutDuration($0))" } ?? ""
                let desc = activities.isEmpty ? "\(weeklyCount) 次" : activities
                lines.append("过去7天（\(weekRange)）运动：\(desc)\(total)")
            } else {
                lines.append("过去7天（\(weekRange)）运动：暂无 HealthKit 运动记录")
            }
        }
        if !workouts.topActivities.isEmpty {
            let activities = workouts.topActivities.map { "\($0.name) \($0.count)次" }.joined(separator: "、")
            lines.append("近30天（\(Self.rollingDateRangeLabel(daysBack: 30))）运动基线：\(activities)，每周约 \(String(format: "%.1f", workouts.weeklyFrequency)) 次，平均每次 \(String(format: "%.0f", workouts.avgDurationMinutes)) 分钟")
        }

        // AI 提取的生活方式
        if let sleep = profile.lifestyle.sleepPattern {
            if let observedAt = profile.lifestyle.sleepPatternObservedAt {
                let age = Calendar.current.dateComponents([.day], from: observedAt, to: Date()).day ?? 0
                if age <= 14 {
                    lines.append("近期睡眠状态（\(Self.relativeDayLabel(for: observedAt))提取）：\(sleep)")
                } else {
                    lines.append("之前提到的睡眠习惯（\(Self.relativeDayLabel(for: observedAt))，可能已变化）：\(sleep)")
                }
            } else {
                lines.append("旧版睡眠画像（无提取时间，回答时不要当作近期状态）：\(sleep)")
            }
        }
        if !profile.lifestyle.dietaryPreferences.isEmpty {
            lines.append("饮食偏好：\(profile.lifestyle.dietaryPreferences.joined(separator: "、"))")
        }
        if !profile.lifestyle.knownSensitivities.isEmpty {
            lines.append("敏感因素：\(profile.lifestyle.knownSensitivities.joined(separator: "、"))")
        }
        if !profile.knownConditions.isEmpty {
            lines.append("已知健康状况：\(profile.knownConditions.joined(separator: "、"))")
        }

        guard !lines.isEmpty else { return "" }
        return "\n用户个人画像：\n" + lines.joined(separator: "\n")
    }

    nonisolated private static func relativeDayLabel(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0

        switch days {
        case ..<0:
            return "未来日期"
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2:
            return "前天"
        default:
            return "\(days)天前"
        }
    }

    /// 滚动时间窗的日期范围标签，例如「8月19日—8月26日」，用于让模型明确区分时间口径。
    nonisolated private static func rollingDateRangeLabel(daysBack: Int, now: Date = Date()) -> String {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: start))—\(formatter.string(from: now))"
    }

    /// 提示 AI 主动询问缺失的档案字段
    nonisolated static func buildMissingFieldsHint(profile: UserProfile?) -> String {
        guard let profile else { return "" }
        let missing = profile.missingFieldNames
        guard !missing.isEmpty else { return "" }
        return """

        你还不太了解用户的：\(missing.joined(separator: "、"))。
        在自然对话中如果话题相关可以顺便问一下（每次最多问一个，不要像问卷一样连续提问）。
        """
    }

    // MARK: - Profile Extraction from Chat

    /// 从用户对话中提取档案信息（fast 模型，JSON mode）
    func extractProfileFields(userMessage: String, assistantReply: String) async throws -> ExtractedProfileFields {
        let request = LLMRequest(
            model: Self.utilityModelName,
            messages: [
                LLMMessage(role: "system", content: """
                从以下对话片段中提取用户的个人生活信息。只提取用户明确提到的信息，不要推测。
                输出 JSON：
                {
                  "sleep_pattern": null 或字符串描述（如"通常23点睡7点起"），
                  "dietary_preferences": [] 或字符串数组（如["素食","乳糖不耐"]），
                  "known_conditions": [] 或字符串数组（如["痛经","PCOS"]），
                  "known_sensitivities": [] 或字符串数组（如["咖啡因影响睡眠"]）
                }
                所有字段均可为 null/空数组，只填用户明确提到的。
                """),
                LLMMessage(role: "user", content: """
                用户说：\(userMessage)
                助手回复：\(String(assistantReply.prefix(800)))
                """)
            ],
            stream: false,
            temperature: 0.1,
            maxTokens: 200,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request, timeout: 15)
        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }

        let cleaned = Self.cleanContent(content)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Cannot convert to data")
        }
        return try JSONDecoder().decode(ExtractedProfileFields.self, from: data)
    }

    // MARK: - Token Estimation (for billing settlement)

    /// 轻量 token 估算：按字符长度估算，优先保证不漏算成本（宁可稍保守）。
    nonisolated static func estimateTokenCount(from text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let scalarCount = trimmed.unicodeScalars.count
        return max(1, Int(ceil(Double(scalarCount) / 1.6)))
    }

    nonisolated static func estimateTokenCount(messages: [LLMMessage]) -> Int {
        messages.reduce(0) { partial, message in
            partial + estimateTokenCount(from: message.content)
        }
    }
}
