import SwiftUI
import UIKit

struct ChatBubbleView: View {
    let message: ChatMessage
    var captionBelow: String?
    /// 点击助手消息下方的推荐追问时发送该问题
    var onFollowUpTap: ((String) -> Void)?
    var onCopyTap: ((ChatMessage) -> Void)?
    var onDeleteTap: ((ChatMessage) -> Void)?
    var onRefreshTap: ((ChatMessage) -> Void)?
    var showsRefreshAction: Bool

    init(
        message: ChatMessage,
        captionBelow: String? = nil,
        onFollowUpTap: ((String) -> Void)? = nil,
        onCopyTap: ((ChatMessage) -> Void)? = nil,
        onDeleteTap: ((ChatMessage) -> Void)? = nil,
        onRefreshTap: ((ChatMessage) -> Void)? = nil,
        showsRefreshAction: Bool = false
    ) {
        self.message = message
        self.captionBelow = captionBelow
        self.onFollowUpTap = onFollowUpTap
        self.onCopyTap = onCopyTap
        self.onDeleteTap = onDeleteTap
        self.onRefreshTap = onRefreshTap
        self.showsRefreshAction = showsRefreshAction
    }

    /// 推理块是否展开。流式思考时自动展开；完成后用户可手动折叠。
    @State private var thinkingExpanded = false

    private var isThinking: Bool {
        message.isStreaming && !(message.thinkingText ?? "").isEmpty && message.content.isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 0) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                // 推理块（Deep 模式，仅助手）
                if let thinking = message.thinkingText, !thinking.isEmpty, message.role == .assistant {
                    thinkingAccordion(text: thinking)
                }

                // 消息气泡：思考过程中不显示打点动画，用推理块表达进度
                if !isThinking {
                    bubbleContent
                }

                if message.role == .assistant,
                   !message.isStreaming,
                   let follow = message.followUpQuestions,
                   !follow.isEmpty {
                    followUpSuggestions(follow)
                }

                if let cap = captionBelow, !cap.isEmpty {
                    captionView(cap)
                }
            }

            if message.role == .assistant { Spacer(minLength: 24) }
        }
        .padding(.trailing, message.role == .user ? 18 : 0)
        // 推理文字一出现，立即展开
        .onChange(of: message.thinkingText) { _, newVal in
            if let t = newVal, !t.isEmpty, !thinkingExpanded {
                withAnimation(.easeOut(duration: 0.2)) { thinkingExpanded = true }
            }
        }
    }

    // MARK: - Bubble

    private func captionView(_ caption: String) -> some View {
        Text(caption)
            .font(Theme.itim(size: 14))
            .foregroundStyle(Color.black.opacity(0.28))
            .padding(.top, 2)
            .padding(.leading, message.role == .assistant ? 18 : 0)
            .multilineTextAlignment(message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let bubble = message.role == .assistant ? AnyView(assistantLine) : AnyView(userBubble)

        if !message.content.isEmpty {
            bubble.contextMenu {
                Button {
                    if let onCopyTap {
                        onCopyTap(message)
                    } else {
                        UIPasteboard.general.string = message.content
                    }
                } label: {
                    Label(String(localized: "assistant.message.copy"), systemImage: "doc.on.doc")
                }

                if showsRefreshAction {
                    Button {
                        onRefreshTap?(message)
                    } label: {
                        Label(String(localized: "assistant.message.refresh"), systemImage: "arrow.clockwise")
                    }
                }

                Button(role: .destructive) {
                    onDeleteTap?(message)
                } label: {
                    Label(String(localized: "assistant.message.delete"), systemImage: "trash")
                }
            }
        } else {
            bubble
        }
    }

    private var userBubble: some View {
        ViewThatFits(in: .horizontal) {
            userBubbleText
                .fixedSize(horizontal: true, vertical: false)
            userBubbleText
                .frame(width: 216, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
        }
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
            .background(Theme.cardBackgroundSolid.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    private var userBubbleText: some View {
        Text(message.content)
            .font(Theme.itim(size: 18))
            .foregroundStyle(Color.black.opacity(0.50))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
    }

    private var assistantLine: some View {
        Group {
            if message.isStreaming && message.content.isEmpty {
                TypingIndicatorView()
            } else {
                MarkdownTextView(content: message.content, isStreaming: message.isStreaming)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.leading, 18)
        .padding(.trailing, 30)
        .padding(.vertical, 8)
    }

    // MARK: - Follow-up question chips

    @ViewBuilder
    private func followUpSuggestions(_ questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "assistant.followup_label"))
                .font(Theme.itim(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)

            ForEach(questions, id: \.self) { q in
                SuggestedQuestionChip(question: q) {
                    onFollowUpTap?(q)
                }
            }
        }
        .padding(.top, 4)
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thinking Accordion

    @ViewBuilder
    private func thinkingAccordion(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header：思考中 vs 思考过程（完成）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                    if message.isStreaming && message.content.isEmpty {
                        Text(String(localized: "assistant.thinking.in_progress"))
                            .font(Theme.itim(size: 14))
                        ThinkingPulse()
                    } else {
                        Text(String(localized: "assistant.thinking.completed"))
                            .font(Theme.itim(size: 14))
                    }
                    Image(systemName: thinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Theme.accent.opacity(0.8))
            }
            .buttonStyle(.plain)

            // 内容：始终由 thinkingExpanded 控制，流式时默认展开但可手动折叠
            if thinkingExpanded {
                ScrollView {
                    Text(text)
                        .font(Theme.itim(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 160)
                .background(Theme.accentLight.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Theme.cardBackgroundSolid.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Thinking Pulse（三个渐变小点，表示"正在思考"）

private struct ThinkingPulse: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    VStack(spacing: 12) {
        ChatBubbleView(message: ChatMessage(role: .user, content: "今天适合运动吗？"))
        // 思考中（流式，有推理文字，内容为空）
        ChatBubbleView(message: ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true,
            thinkingText: "用户目前处于卵泡期第5天，HRV 58ms 趋势上升，说明身体恢复良好，适合中高强度训练…"
        ))
        // 思考完成，正在生成回复
        ChatBubbleView(message: ChatMessage(
            role: .assistant,
            content: "当然可以！卵泡期雌激素上升，是运动的好时机 💪",
            isStreaming: false,
            thinkingText: "用户目前处于卵泡期第5天，HRV 58ms 趋势上升，说明身体恢复良好。"
        ))
        // Markdown 渲染测试
        ChatBubbleView(message: ChatMessage(
            role: .assistant,
            content: """
            ## 卵泡期建议
            这个阶段雌激素上升，适合：
            - **高强度训练**（如 HIIT）
            - 力量训练 `PR` 尝试
            1. 优先保证睡眠
            2. 增加*蛋白质*摄入
            """,
            isStreaming: false
        ))
    }
    .padding()
    .background(Theme.background)
}
