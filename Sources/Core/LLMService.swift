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

// MARK: - Suggestion JSON Schema (private)

private struct AISuggestionResponse: Decodable {
    let suggestions: [AISuggestion]
}

private struct AISuggestion: Decodable {
    let dimension: String   // "diet" | "exercise" | "mood" | "sleep"
    let title: String
    let details: [String]
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case emptyResponse
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return String(localized: "error.empty_response")
        case .invalidResponse:
            return String(localized: "error.invalid_response")
        case .httpError(let code):
            return String(format: String(localized: "error.http_format"), code)
        case .decodingFailed:
            return String(localized: "error.decoding")
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

    // MARK: - Suggestion Generation (non-streaming, JSON Mode)

    /// 首页建议固定用 fast 模型，与「思考模式」其它用途解耦，保证延迟与成本可控。
    private static let suggestionModelName = ThinkingMode.fast.modelName

    /// 每维度最多 5 句 details × 4 维度 + JSON 结构；过小易截断。
    private static let suggestionMaxTokens = 3400

    func generateSuggestions(for context: CycleContext, profile: UserProfile? = nil) async throws -> SuggestionSet {
        let request = LLMRequest(
            model: Self.suggestionModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildSuggestionSystemPrompt()),
                LLMMessage(role: "user", content: Self.buildSuggestionUserPrompt(context: context, profile: profile))
            ],
            stream: false,
            temperature: 0.55,
            maxTokens: Self.suggestionMaxTokens,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request)

        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }

        return try parseSuggestions(from: content, phase: context.phase)
    }

    // MARK: - Suggestion Streaming (with think callback)

    func streamSuggestions(
        for context: CycleContext,
        profile: UserProfile? = nil,
        onThinking: @escaping (String) -> Void
    ) async throws -> SuggestionSet {
        let request = LLMRequest(
            model: Self.suggestionModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildSuggestionSystemPrompt()),
                LLMMessage(role: "user", content: Self.buildSuggestionUserPrompt(context: context, profile: profile))
            ],
            stream: true,
            temperature: 0.55,
            maxTokens: Self.suggestionMaxTokens,
            responseFormat: .init(type: "json_object")
        )

        let urlRequest = try buildURLRequest(for: request)
        let (asyncBytes, httpResponse) = try await session.bytes(for: urlRequest)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (httpResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMError.httpError(statusCode: code)
        }

        var fullContent = ""
        var inThink = false
        var thinkResolved = false

        for try await line in asyncBytes.lines {
            guard let data = Self.sseData(from: line),
                  let parsed = try? decoder.decode(LLMResponse.self, from: data)
            else { continue }

            let choice = parsed.choices.first
            let chunk = choice?.delta?.content ?? choice?.message?.content ?? ""
            if !chunk.isEmpty {
                fullContent += chunk

                // 实时提取并回调 think 内容
                if !thinkResolved {
                    if !inThink && fullContent.contains("<think>") {
                        inThink = true
                    }
                    if inThink {
                        if let range = fullContent.range(of: "</think>") {
                            // think 结束
                            let thinkContent = String(fullContent[fullContent.range(of: "<think>")!.upperBound..<range.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            onThinking(thinkContent)
                            thinkResolved = true
                        } else {
                            // think 进行中，提取已有内容
                            if let start = fullContent.range(of: "<think>") {
                                let partial = String(fullContent[start.upperBound...])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !partial.isEmpty {
                                    onThinking(partial)
                                }
                            }
                        }
                    } else if fullContent.count > 10 {
                        thinkResolved = true
                    }
                }
            }

            if choice?.finishReason == "stop" { break }
        }

        return try parseSuggestions(from: fullContent, phase: context.phase)
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
            throw error
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

    private func parseSuggestions(from content: String, phase: CyclePhase) throws -> SuggestionSet {
        let cleaned = Self.cleanContent(content)
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.decodingFailed("Cannot convert response to data")
        }
        let timestamp = Int(Date().timeIntervalSince1970)

        // 优先走严格 schema，失败时走兼容解析（应对模型偶发格式漂移）
        let suggestions: [Suggestion]
        if let aiResponse = try? decoder.decode(AISuggestionResponse.self, from: data) {
            suggestions = aiResponse.suggestions.compactMap { item -> Suggestion? in
                guard let dimension = Self.parseDimension(item.dimension) else { return nil }
                let trimmedDetails = item.details.map { Self.stripLeadingOrdinal($0) }
                    .filter { !$0.isEmpty }
                return Suggestion(
                    id: "\(dimension.rawValue)-ai-\(timestamp)",
                    dimension: dimension,
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    details: Array(trimmedDetails.prefix(5)),
                    referenceIds: ReferenceLibrary.referenceIDs(for: dimension)
                )
            }
        } else {
            suggestions = try Self.parseSuggestionsFlexibly(from: data, timestamp: timestamp)
        }

        guard !suggestions.isEmpty else {
            throw LLMError.decodingFailed("No valid suggestions in response")
        }

        return SuggestionSet(phase: phase, suggestions: suggestions, generatedAt: .now)
    }

    private nonisolated static func parseSuggestionsFlexibly(from data: Data, timestamp: Int) throws -> [Suggestion] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingFailed("JSON root is not object")
        }

        // 兼容结构1：{ "suggestions": [...] }
        if let arr = json["suggestions"] as? [[String: Any]] {
            let parsed = arr.compactMap { item -> Suggestion? in
                guard let dimensionRaw = item["dimension"] as? String,
                      let dimension = parseDimension(dimensionRaw)
                else { return nil }

                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? dimension.displayName
                let details = normalizeDetails(from: item["details"]).prefix(5)
                return details.isEmpty ? nil : Suggestion(
                    id: "\(dimension.rawValue)-ai-\(timestamp)",
                    dimension: dimension,
                    title: title.isEmpty ? dimension.displayName : title,
                    details: Array(details),
                    referenceIds: ReferenceLibrary.referenceIDs(for: dimension)
                )
            }
            if !parsed.isEmpty { return parsed }
        }

        // 兼容结构2：{ "dimensions": { "饮食营养": { "建议": [...] }, ... } }
        let dimObject = (json["dimensions"] as? [String: Any]) ?? (json["维度"] as? [String: Any])
        if let dimObject {
            let parsed = dimObject.compactMap { key, value -> Suggestion? in
                guard let dimension = parseDimension(key) else { return nil }
                guard let obj = value as? [String: Any] else { return nil }
                let titleRaw = (obj["title"] as? String) ?? (obj["标题"] as? String) ?? key
                let title = titleRaw.trimmingCharacters(in: .whitespacesAndNewlines)

                let detailsSource = obj["details"] ?? obj["建议"] ?? obj["tips"] ?? obj["items"]
                let details = normalizeDetails(from: detailsSource).prefix(5)
                guard !details.isEmpty else { return nil }

                return Suggestion(
                    id: "\(dimension.rawValue)-ai-\(timestamp)",
                    dimension: dimension,
                    title: title.isEmpty ? dimension.displayName : title,
                    details: Array(details),
                    referenceIds: ReferenceLibrary.referenceIDs(for: dimension)
                )
            }
            if !parsed.isEmpty { return parsed }
        }

        throw LLMError.decodingFailed("Unsupported suggestion JSON schema")
    }

    private nonisolated static func normalizeDetails(from any: Any?) -> [String] {
        if let lines = any as? [String] {
            return lines.map { stripLeadingOrdinal($0) }.filter { !$0.isEmpty }
        }
        if let lines = any as? [[String: Any]] {
            return lines.compactMap { ($0["content"] as? String) ?? ($0["text"] as? String) }
                .map { stripLeadingOrdinal($0) }
                .filter { !$0.isEmpty }
        }
        if let s = any as? String {
            let trimmed = stripLeadingOrdinal(s)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return []
    }

    /// 前端卡片已渲染序号徽章；剥离模型偶发输出的「第1条：」「1.」「①」「- 」等行首序号/符号，避免重复。
    nonisolated static func stripLeadingOrdinal(_ s: String) -> String {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^第\s*[0-9一二三四五六七八九十]+\s*条[：:、．.]?\s*"#,
            #"^[0-9]+\s*[\.、．)）:：]\s*"#,
            #"^[①②③④⑤⑥⑦⑧⑨⑩❶❷❸❹❺❻❼❽❾❿]\s*"#,
            #"^[-•·*]\s+"#
        ]
        for p in patterns {
            if let r = str.range(of: p, options: .regularExpression) {
                str.removeSubrange(r)
            }
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func parseDimension(_ raw: String) -> SuggestionDimension? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "diet", "nutrition", "饮食", "饮食营养":
            return .diet
        case "exercise", "activity", "运动", "锻炼":
            return .exercise
        case "mood", "emotion", "mental", "情绪", "心理":
            return .mood
        case "sleep", "rest", "睡眠":
            return .sleep
        default:
            return nil
        }
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
            maxTokens: 800,
            responseFormat: nil
        )

        let urlRequest = try buildURLRequest(for: request)
        let (asyncBytes, httpResponse) = try await session.bytes(for: urlRequest)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (httpResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMError.httpError(statusCode: code)
        }

        var fullContent = ""
        var fullReasoning = ""
        var emittedLength = 0

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

        let cleaned = Self.cleanContent(fullContent)
        let inputTokens = Self.estimateTokenCount(messages: request.messages)
        let outputTokens = Self.estimateTokenCount(from: cleaned)
        return LLMChatStreamResult(
            content: cleaned,
            usage: LLMTokenUsage(inputTokens: inputTokens, outputTokens: outputTokens)
        )
    }

    // MARK: - Suggested Questions Generation

    private static let questionsMaxTokens = 300

    func generateSuggestedQuestions(for context: CycleContext) async throws -> [String] {
        let request = LLMRequest(
            model: Self.suggestionModelName,
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
        recentDialogue: String = ""
    ) async throws -> [String] {
        let request = LLMRequest(
            model: Self.suggestionModelName,
            messages: [
                LLMMessage(role: "system", content: Self.buildChatFollowUpQuestionsSystemPrompt()),
                LLMMessage(
                    role: "user",
                    content: Self.buildChatFollowUpUserPrompt(
                        context: context,
                        userQuestion: userQuestion,
                        assistantReply: assistantReply,
                        recentDialogue: recentDialogue
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

    // MARK: - Prompt Builders (nonisolated, always in Chinese)

    nonisolated static func buildSuggestionSystemPrompt() -> String {
        """
        你是女性月经周期相关的生活方式顾问，输出为参考建议，非医疗诊断或治疗。

        只输出纯 JSON（不要 markdown、说明文字），结构如下：
        {
          "suggestions": [
            {
              "dimension": "diet",
              "title": "8-15 字，具体针对当前阶段",
              "details": [
                "结合用户数据（如 HRV/日照/锻炼/步数等）的简短个性化说明，20-38 字",
                "具体可执行建议（含份量/时间或做法），20-38 字",
                "替代方案或加分习惯，20-38 字",
                "可适当避免或减少的习惯，20-38 字",
                "（可选）一句轻松提醒或小结，15-30 字；若与前四条重复可省略，此时数组至少保留 4 条"
              ]
            },
            … 另三条 dimension 分别为 exercise、mood、sleep，格式相同。
          ]
        }

        约束：dimension 仅 diet/exercise/mood/sleep；每个 dimension 的 details 数组须含 4-5 条互不重复、具体可操作的中文短句（优先 5 条，若写不出第 5 条则必须不少于 4 条）；禁用「治疗」「诊断」「医嘱」等医疗措辞；不夸大指标的医学意义。
        每条 details 直接写正文，不要以「第1条」「1.」「①」「·」等编号或符号开头（前端已渲染序号徽章）。
        若上下文中出现「上午」「活动数据仍在累积」或类似说明：今日步数/消耗为截至目前累计，不得据此批评用户活动太少、施压或制造焦虑；运动相关用鼓励、非评判语气，避免「太少」「不够」「要加强」等措辞。
        若上下文中包含「当前症状（最近48小时）」：请根据当前症状给出针对性建议，例如痉挛时建议温热敷/补镁、头痛时建议补水/避咖啡因、疲劳时调整运动强度、情绪波动时建议正念等。若只出现「本周期曾记录症状」或「历史高频症状」，只能作为历史参考，不要说成用户现在有这些症状。
        """
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
                lines.append("本周期曾记录症状（非当前症状，回答时不要说成现在有）：\(desc)")
            }
        }

        return lines
    }

    nonisolated static func buildSuggestionUserPrompt(context: CycleContext, profile: UserProfile? = nil) -> String {
        let lines = buildContextLines(context: context)
        let profileSummary = buildProfileSummary(profile: profile)
        return """
        请根据以下健康数据，为该用户生成四个维度（diet/exercise/mood/sleep）的个性化生活建议：

        \(lines.joined(separator: "\n"))
        \(profileSummary)

        请只输出 JSON，不要包含任何其他文字。
        """
    }

    /// 对话助手的 System Prompt：注入周期上下文 + 用户档案，设定温暖体贴语气
    nonisolated static func buildChatSystemPrompt(context: CycleContext, profile: UserProfile? = nil) -> String {
        let contextSummary = buildContextLines(context: context).joined(separator: "\n")
        let profileSummary = buildProfileSummary(profile: profile)
        let missingHint = buildMissingFieldsHint(profile: profile)
        return """
        你是月经周期生活方式顾问"周期助理"，语气温暖体贴，像关心朋友的闺蜜，偶尔使用 emoji 增加亲切感。

        规则：
        - 提供可操作的生活方式建议，含具体做法/份量/时间
        - 禁用「治疗」「诊断」「医嘱」等医疗措辞，不做医学因果断定
        - 若摘要中注明上午或活动数据仍在累积：不得因今日步数/消耗暂时偏低而批评用户；避免「活动太少」「不够」等施压表述
        - 若用户状态包含「当前症状（最近48小时）」：回答时充分考虑用户当前的经期症状和出血量，针对性地提供缓解建议，语气要更加温柔体贴
        - 若只出现「本周期曾记录症状」或「历史高频症状」：只能作为历史参考，不要说成用户现在有这些症状
        - 若提供了「用户个人画像」：回答应结合用户的身体数据、运动偏好、历史周期规律等个人化信息
        - 遇到诊断/疾病相关问题：先一句话直接说明需要医生判断，再简短提供生活层面可参考的内容
        - 输出纯文本，可用加粗和换行，不输出 JSON 或 markdown 代码块

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
    nonisolated static func buildChatFollowUpQuestionsSystemPrompt() -> String {
        """
        你是月经周期生活方式顾问的「追问推荐」模块，输出仅供用户点击参考，非医疗诊断。

        必须先完整阅读【助手上一答】全文与【近期对话摘录】后，再生成恰好 3 个用户很可能接着问的中文问题。
        要求：
        - 与上文话题自然衔接，可延伸细节、原理、执行步骤、替代方案、注意事项，或与周期/睡眠/情绪/饮食的关联
        - 3 个问题尽量覆盖不同角度，避免句式雷同或与用户原问题高度重复
        - 口语化、简短（单条原则上不超过 28 字）
        - 不出现「治疗」「诊断」「医嘱」等医疗措辞；不暗示替代就医
        - 不得编造用户当前状态摘要中没有出现的具体指标、周期信息或症状

        只输出 JSON，格式：{"questions":["问题1","问题2","问题3"]}
        """
    }

    nonisolated static func buildChatFollowUpUserPrompt(
        context: CycleContext,
        userQuestion: String,
        assistantReply: String,
        recentDialogue: String
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

        请只输出 JSON，不要其他说明。
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
        for phase in CyclePhase.allCases {
            let top = stats.topSymptoms(for: phase, limit: 3)
            if !top.isEmpty {
                let desc = top.map { item in
                    let name = SymptomEntry.SymptomType(rawValue: item.symptom)?.displayName ?? item.symptom
                    return "\(name)(\(item.count)次)"
                }.joined(separator: "、")
                lines.append("历史\(phase.displayName)高频症状（非当前状态）：\(desc)")
            }
        }

        // 运动统计
        let workouts = profile.workoutStats
        if let weeklyCount = workouts.weeklyWorkoutCount {
            if weeklyCount > 0 {
                let activities = (workouts.weeklyActivities ?? [])
                    .map { activity -> String in
                        if let duration = activity.totalDurationMinutes, duration > 0 {
                            return "\(activity.name) \(activity.count)次/约\(Int(duration))分钟"
                        }
                        return "\(activity.name) \(activity.count)次"
                    }
                    .joined(separator: "、")
                let total = workouts.weeklyTotalDurationMinutes.map { "，总时长约 \(Int($0)) 分钟" } ?? ""
                let desc = activities.isEmpty ? "\(weeklyCount) 次" : activities
                lines.append("过去7天运动：\(desc)\(total)")
            } else {
                lines.append("过去7天运动：暂无 HealthKit 运动记录")
            }
        }
        if !workouts.topActivities.isEmpty {
            let activities = workouts.topActivities.map { "\($0.name) \($0.count)次" }.joined(separator: "、")
            lines.append("近30天运动基线：\(activities)，每周约 \(String(format: "%.1f", workouts.weeklyFrequency)) 次，平均每次 \(String(format: "%.0f", workouts.avgDurationMinutes)) 分钟")
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
            model: Self.suggestionModelName,
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
