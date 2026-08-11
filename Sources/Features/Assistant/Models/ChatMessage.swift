import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool
    var thinkingText: String?
    /// 本条助手回复生成后，基于对话语境推荐的后续问题（通常 3 条）
    var followUpQuestions: [String]?
    let timestamp: Date
    /// 用于按天分组，值为当天 00:00:00
    let sessionDate: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        isStreaming: Bool = false,
        thinkingText: String? = nil,
        followUpQuestions: [String]? = nil,
        timestamp: Date = .now,
        sessionDate: Date = Calendar.current.startOfDay(for: .now)
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.thinkingText = thinkingText
        self.followUpQuestions = followUpQuestions
        self.timestamp = timestamp
        self.sessionDate = sessionDate
    }
}
