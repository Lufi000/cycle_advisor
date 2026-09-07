import Foundation
import Observation

@Observable
@MainActor
final class AssistantViewModel {

    struct ChatSession: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var messages: [ChatMessage]
        let createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            messages: [ChatMessage],
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.messages = messages
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    var messages: [ChatMessage] = []
    var chatSessions: [ChatSession] = []
    var inputText: String = ""
    var isStreaming: Bool = false

    /// 由 HomeViewModel 注入，chat 时作为上下文快照
    var context: CycleContext = MockData.lutealContext
    /// 由 HomeViewModel 注入，首屏展示
    var suggestedQuestions: [String] = []
    var billingNotice: String = ""

    /// 追问芯片写入后递增，供列表滚动贴近最新芯片
    private(set) var followUpChipsRevision: Int = 0

    /// 每次 API 请求最多携带的历史消息条数，避免对话越长速度越慢
    private static let maxHistoryMessages = 20
    /// 每个历史会话最多保留的消息条数
    private static let maxPersistedMessages = 100
    /// 最多保留的历史会话数
    private static let maxStoredSessions = 50
    /// 追问建议与档案抽取的额外 token 预算，防止只结算主回答导致低估成本
    private static let postProcessTokenBudget = 260

    // MARK: - Session

    private let legacyHistoryURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_history.json")
    }()

    private let sessionsURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_sessions.json")
    }()

    private var activeSessionID: UUID?

    init() {
        loadChatSessions()
        openTodaySessionIfAvailable()
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let preferredLanguage = LLMService.preferredResponseLanguage()
        let responseLanguage = LLMService.responseLanguage(for: trimmed, fallback: preferredLanguage)
        let systemPrompt = LLMService.buildChatSystemPrompt(
            context: context,
            profile: UserProfileManager.shared.profile,
            responseLanguage: responseLanguage
        )
        let previewHistory = Array(messages.suffix(Self.maxHistoryMessages))
            .compactMap { msg -> LLMMessage? in
                guard !msg.content.isEmpty else { return nil }
                return LLMMessage(role: msg.role.rawValue, content: msg.content)
            } + [LLMMessage(role: "user", content: trimmed)]

        guard let reservationID = await reserveChatCredits(history: previewHistory, systemPrompt: systemPrompt) else {
            return
        }
        billingNotice = ""

        // 1. 添加用户消息
        messages.append(ChatMessage(role: .user, content: trimmed, sessionDate: today))

        // 备孕模式：异步抽取用户消息中的早孕症状（fire-and-forget，静默失败，不阻塞对话）
        if UserProfileManager.shared.profile.isTryingToConceive {
            let capturedMessage = trimmed
            Task {
                await SymptomExtractor.shared.extractAndStore(message: capturedMessage)
            }
        }

        // 2. 构建 API 历史（包含刚刚加入的用户消息，不含即将添加的占位符）
        // 截取最近 maxHistoryMessages 条，避免对话越长、每次请求越慢
        let apiHistory: [LLMMessage] = messages
            .suffix(Self.maxHistoryMessages)
            .compactMap { msg in
                guard !msg.content.isEmpty else { return nil }
                return LLMMessage(role: msg.role.rawValue, content: msg.content)
            }

        // 3. 添加助手占位符
        let assistantId = UUID()
        messages.append(ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isStreaming: true,
            sessionDate: today
        ))

        isStreaming = true

        // 4. 流式调用
        var streamSucceeded = false
        var usage: LLMTokenUsage?
        do {
            let result = try await LLMService.shared.streamChat(
                history: apiHistory,
                systemPrompt: systemPrompt,
                onToken: { [weak self] token in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let idx = self.messages.firstIndex(where: { $0.id == assistantId })
                        else { return }
                        self.messages[idx].content += token
                    }
                },
                onThinking: { [weak self] thinking in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let idx = self.messages.firstIndex(where: { $0.id == assistantId })
                        else { return }
                        self.messages[idx].thinkingText = thinking
                    }
                }
            )
            streamSucceeded = true
            usage = result.usage
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = Self.assistantErrorMessage(for: error)
            }
        }

        // 5. 结束流式状态
        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].isStreaming = false
        }
        isStreaming = false
        saveCurrentSession()

        // 6. 在助手回复完成后再生成追问，保证承接当前完整语境
        var postProcessTokenBudget = 0
        if streamSucceeded {
            if let i = messages.firstIndex(where: { $0.id == assistantId }) {
                let reply = messages[i].content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    let followUps = await fetchContextualFollowUpQuestions(
                        userQuestion: trimmed,
                        assistantReply: messages[i].content,
                        responseLanguage: responseLanguage
                    )
                    if !followUps.isEmpty {
                        var updated = messages[i]
                        updated.followUpQuestions = followUps
                        messages[i] = updated
                        followUpChipsRevision += 1
                        saveCurrentSession()
                        postProcessTokenBudget += Self.postProcessTokenBudget
                    }
                }
            }

            // 7. 后台提取用户档案信息（fire-and-forget，不阻塞对话）
            // 仅当档案还有空字段 + 用户消息可能包含生活信息时才触发，避免浪费 token
            if UserProfileManager.shared.profile.hasEmptyLifestyleFields,
               Self.mayContainLifestyleInfo(trimmed),
               let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                let fullReply = messages[idx].content
                let capturedMessage = trimmed
                Task {
                    await UserProfileManager.shared.extractFromChat(
                        userMessage: capturedMessage,
                        assistantReply: fullReply
                    )
                }
                postProcessTokenBudget += Self.postProcessTokenBudget
            }
        }

        settleChatCredits(
            reservationID: reservationID,
            succeeded: streamSucceeded,
            usage: usage,
            extraTokenBudget: postProcessTokenBudget
        )
    }

    /// 在助手回复完成后拉取追问，结合近期多轮语境，避免出现与当前回答脱节的建议。
    private func fetchContextualFollowUpQuestions(
        userQuestion: String,
        assistantReply: String,
        responseLanguage: LLMService.ResponseLanguage
    ) async -> [String] {
        let excerpt = buildRecentDialogueExcerpt()
        do {
            let raw = try await LLMService.shared.generateChatFollowUpQuestions(
                context: context,
                userQuestion: userQuestion,
                assistantReply: assistantReply,
                recentDialogue: excerpt,
                responseLanguage: responseLanguage
            )
            return Self.normalizeToThreeQuestions(raw, responseLanguage: responseLanguage)
        } catch {
            return Self.normalizeToThreeQuestions([], responseLanguage: responseLanguage)
        }
    }

    /// 截取近期对话片段供追问模块理解上下文，并限制长度避免额外 token 浪费。
    private func buildRecentDialogueExcerpt() -> String {
        let slice = Array(messages.suffix(12))
        var lines: [String] = []
        for msg in slice {
            let role = msg.role == .user ? "用户" : "助手"
            var text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count > 1600 {
                text = String(text.prefix(1600)) + "…"
            }
            guard !text.isEmpty else { continue }
            lines.append("\(role)：\(text)")
        }
        var joined = lines.joined(separator: "\n\n")
        if joined.count > 5000 {
            joined = String(joined.suffix(5000))
            joined = "…（更早对话已省略）\n\n" + joined
        }
        return joined
    }

    /// 去重并补齐到 3 条，避免接口异常或返回不足时芯片区域为空。
    private static func normalizeToThreeQuestions(
        _ raw: [String],
        responseLanguage: LLMService.ResponseLanguage = .simplifiedChinese
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for q in raw {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
            if out.count == 3 { break }
        }
        let fallback = responseLanguage.followUpFallbackQuestions
        var i = 0
        while out.count < 3, i < fallback.count {
            let f = fallback[i]
            i += 1
            guard !seen.contains(f) else { continue }
            out.append(f)
            seen.insert(f)
        }
        return Array(out.prefix(3))
    }

    // MARK: - Lifestyle Keyword Detection

    /// 轻量关键词检测：仅当用户消息可能包含生活方式信息时返回 true，避免每次聊天都额外调 API
    nonisolated private static let lifestyleKeywords: [String] = [
        "睡", "觉", "失眠", "熬夜", "早起", "入睡",
        "吃", "饮食", "素食", "忌口", "过敏", "乳糖", "麸质", "不吃",
        "咖啡", "茶", "酒",
        "痛经", "多囊", "内膜", "子宫", "卵巢", "贫血", "甲状腺",
        "敏感", "不耐受",
    ]

    nonisolated private static func mayContainLifestyleInfo(_ text: String) -> Bool {
        lifestyleKeywords.contains { text.contains($0) }
    }

    // MARK: - Clear

    func clearHistory() {
        messages = []
        chatSessions = []
        activeSessionID = nil
        inputText = ""
        billingNotice = ""
        isStreaming = false
        try? FileManager.default.removeItem(at: sessionsURL)
        try? FileManager.default.removeItem(at: legacyHistoryURL)
    }

    func discardCurrentConversation(archiveCurrent: Bool = true) {
        if archiveCurrent {
            saveCurrentSession()
        }
        messages = []
        inputText = ""
        billingNotice = ""
        isStreaming = false
        activeSessionID = nil
        try? FileManager.default.removeItem(at: legacyHistoryURL)
    }

    func prepareCurrentDayConversation() {
        guard !isStreaming else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let currentDate = messages.first?.sessionDate,
           Calendar.current.isDate(currentDate, inSameDayAs: today) {
            return
        }
        saveCurrentSession()
        openTodaySessionIfAvailable()
    }

    private func openTodaySessionIfAvailable() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let session = chatSessions.first(where: { session in
            guard let date = session.messages.first?.sessionDate else { return false }
            return Calendar.current.isDate(date, inSameDayAs: today)
        }) else {
            messages = []
            inputText = ""
            billingNotice = ""
            activeSessionID = nil
            return
        }
        messages = session.messages.map {
            var message = $0
            message.isStreaming = false
            return message
        }
        inputText = ""
        billingNotice = ""
        activeSessionID = session.id
    }

    func openSession(_ id: UUID) {
        guard !isStreaming,
              let session = chatSessions.first(where: { $0.id == id })
        else { return }
        messages = session.messages.map {
            var message = $0
            message.isStreaming = false
            return message
        }
        inputText = ""
        billingNotice = ""
        activeSessionID = id
    }

    func deleteMessage(_ id: UUID) {
        guard !isStreaming, let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages.remove(at: idx)
        saveCurrentSession()
    }

    func deleteSession(_ id: UUID) {
        guard !isStreaming else { return }
        chatSessions.removeAll { $0.id == id }
        if activeSessionID == id {
            messages = []
            inputText = ""
            billingNotice = ""
            activeSessionID = nil
        }
        saveChatSessions()
    }

    /// 刷新最后一条用户提问：用于回复异常时重试，不新增重复用户消息。
    func refreshUserMessage(_ id: UUID) async {
        guard !isStreaming else { return }
        guard let userIndex = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else { return }
        guard userIndex == messages.indices.last(where: { messages[$0].role == .user }) else { return }

        let userQuestion = messages[userIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuestion.isEmpty else { return }

        if messages.indices.contains(userIndex + 1), messages[userIndex + 1].role == .assistant {
            messages.remove(at: userIndex + 1)
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let assistantId = UUID()
        messages.append(ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isStreaming: true,
            sessionDate: today
        ))

        let apiHistory: [LLMMessage] = messages
            .prefix(userIndex + 1)
            .suffix(Self.maxHistoryMessages)
            .compactMap { msg in
                guard !msg.content.isEmpty else { return nil }
                return LLMMessage(role: msg.role.rawValue, content: msg.content)
            }

        let preferredLanguage = LLMService.preferredResponseLanguage()
        let responseLanguage = LLMService.responseLanguage(for: userQuestion, fallback: preferredLanguage)
        let systemPrompt = LLMService.buildChatSystemPrompt(
            context: context,
            profile: UserProfileManager.shared.profile,
            responseLanguage: responseLanguage
        )
        guard let reservationID = await reserveChatCredits(history: apiHistory, systemPrompt: systemPrompt) else {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].isStreaming = false
                messages[idx].content = billingNotice
            }
            return
        }

        isStreaming = true
        var streamSucceeded = false
        var usage: LLMTokenUsage?
        do {
            let result = try await LLMService.shared.streamChat(
                history: apiHistory,
                systemPrompt: systemPrompt,
                onToken: { [weak self] token in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let idx = self.messages.firstIndex(where: { $0.id == assistantId })
                        else { return }
                        self.messages[idx].content += token
                    }
                },
                onThinking: { [weak self] thinking in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let idx = self.messages.firstIndex(where: { $0.id == assistantId })
                        else { return }
                        self.messages[idx].thinkingText = thinking
                    }
                }
            )
            streamSucceeded = true
            usage = result.usage
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = Self.assistantErrorMessage(for: error)
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].isStreaming = false
        }
        isStreaming = false
        saveCurrentSession()

        var postProcessTokenBudget = 0
        if streamSucceeded,
           let i = messages.firstIndex(where: { $0.id == assistantId }) {
            let reply = messages[i].content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reply.isEmpty {
                let followUps = await fetchContextualFollowUpQuestions(
                    userQuestion: userQuestion,
                    assistantReply: messages[i].content,
                    responseLanguage: responseLanguage
                )
                if !followUps.isEmpty {
                    var updated = messages[i]
                    updated.followUpQuestions = followUps
                    messages[i] = updated
                    followUpChipsRevision += 1
                    saveCurrentSession()
                    postProcessTokenBudget += Self.postProcessTokenBudget
                }
            }
        }

        settleChatCredits(
            reservationID: reservationID,
            succeeded: streamSucceeded,
            usage: usage,
            extraTokenBudget: postProcessTokenBudget
        )
    }

    // MARK: - Session Persistence

    private func saveCurrentSession() {
        let storedMessages = Array(messages.filter { !$0.isStreaming }.suffix(Self.maxPersistedMessages))
        guard !storedMessages.isEmpty else {
            if let activeSessionID {
                chatSessions.removeAll { $0.id == activeSessionID }
                self.activeSessionID = nil
                saveChatSessions()
            }
            return
        }

        let now = Date()
        let title = Self.sessionTitle(from: storedMessages)
        if let activeSessionID,
           let index = chatSessions.firstIndex(where: { $0.id == activeSessionID }) {
            chatSessions[index].title = title
            chatSessions[index].messages = storedMessages
            chatSessions[index].updatedAt = now
        } else {
            let session = ChatSession(title: title, messages: storedMessages, createdAt: now, updatedAt: now)
            activeSessionID = session.id
            chatSessions.insert(session, at: 0)
        }

        chatSessions.sort { $0.updatedAt > $1.updatedAt }
        chatSessions = Array(chatSessions.prefix(Self.maxStoredSessions))
        saveChatSessions()
    }

    private func saveChatSessions() {
        guard let data = try? JSONEncoder().encode(chatSessions) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }

    private func loadChatSessions() {
        guard let data = try? Data(contentsOf: sessionsURL),
              let saved = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }
        chatSessions = saved.map { session in
            var copy = session
            copy.messages = session.messages.map {
                var message = $0
                message.isStreaming = false
                return message
            }
            return copy
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func sessionTitle(from messages: [ChatMessage]) -> String {
        let source = messages.first(where: { $0.role == .user }) ?? messages.first
        let title = source?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        guard !title.isEmpty else { return String(localized: "assistant.history.untitled") }
        if title.count <= 28 { return title }
        return String(title.prefix(28)) + "..."
    }

    private static func assistantErrorMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(localized: "assistant.error_fallback") : message
    }

    // MARK: - Billing

    private func reserveChatCredits(history: [LLMMessage], systemPrompt: String) async -> String? {
        let inputTokens = LLMService.estimateTokenCount(from: systemPrompt) + LLMService.estimateTokenCount(messages: history)
        let estimatedTotalTokens = inputTokens + 800 + Self.postProcessTokenBudget
        let estimatedCredits = BillingManager.shared.estimatedCredits(forTokens: estimatedTotalTokens)
        let billing = BillingManager.shared

        if !billing.isSubscriptionActive && billing.freeChatRemaining == 0 {
            await billing.refreshSubscriptionStatus()
        }

        do {
            return try billing.reserveAssistantChat(estimatedCredits: estimatedCredits)
        } catch {
            billingNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func settleChatCredits(
        reservationID: String?,
        succeeded: Bool,
        usage: LLMTokenUsage?,
        extraTokenBudget: Int
    ) {
        guard let reservationID else { return }
        let tokenTotal = (usage?.totalTokens ?? 0) + extraTokenBudget
        let actualCredits = BillingManager.shared.estimatedCredits(forTokens: max(1, tokenTotal))
        BillingManager.shared.settleAssistantChat(
            reservationID: reservationID,
            actualCredits: actualCredits,
            succeeded: succeeded
        )
    }
}
