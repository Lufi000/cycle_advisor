import Combine
import SwiftUI
import UIKit

/// iOS 17 降级路径：读取聊天列表滚动偏移量（minY），用于感知「向上滚动」。
private struct ChatScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// iOS 18+ 的官方滚动几何回调；iOS 17 走 GeometryReader + PreferenceKey 降级路径。
private extension View {
    @ViewBuilder
    func onScrollContentOffsetChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                action(newValue)
            }
        } else {
            self
        }
    }
}

struct AssistantView: View {
    @Bindable var viewModel: AssistantViewModel
    @Binding var selectedTab: Int
    @AppStorage("displayName") private var displayName = ""
    /// 顶部健康 Header 折叠偏好，持久化保存；折叠状态由滚动手势与手动按钮共同控制。
    @AppStorage("assistant.header.isCollapsed") private var isHeaderCollapsed = false
    private let billing = BillingManager.shared
    @State private var pendingForceScrollToBottom = false
    @State private var timeTick = Date()
    @State private var dismissedLowQuotaWarning = false
    @State private var showingChatHistory = false
    @State private var lastScrollOffset: CGFloat?
    @State private var isProgrammaticScrolling = false
    /// 累计向上滚动的位移，避免慢速拖动时单次位移过小导致无法触发折叠。
    @State private var upwardScrollAccumulator: CGFloat = 0

    /// 剩余免费对话 ≤ 此阈值时给出"快用完"提示。
    private static let lowQuotaWarningThreshold = 2

    /// 新消息发出后延迟显示时间，避免气泡区过于拥挤。
    private static let messageCaptionFadeInDelay: TimeInterval = 180

    private static let chatScrollCoordinateSpace = "assistantChatScroll"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部固定健康 Header
                PhaseHeaderView(
                    context: viewModel.context,
                    displayName: sanitizedDisplayName,
                    isCollapsed: $isHeaderCollapsed
                )
                lowQuotaWarningBar

                // 首屏不滚动；有对话后才进入聊天滚动列表
                if viewModel.messages.isEmpty {
                    emptyStateView
                        .onAppear {
                            timeTick = Date()
                        }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            // iOS 17 降级：经典零高度 GeometryReader 直读偏移。
                            // 不要放回 background：在部分系统版本上滚动时 preference 不会刷新。
                            if #unavailable(iOS 18.0) {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ChatScrollOffsetKey.self,
                                        value: geo.frame(in: .named(Self.chatScrollCoordinateSpace)).minY
                                    )
                                }
                                .frame(height: 0)
                            }
                            LazyVStack(spacing: 24) {
                                dateSeparators
                                Color.clear
                                    .frame(height: 1)
                                    .id("chat-bottom-anchor")
                            }
                            .padding(.horizontal, 0)
                            .padding(.top, 24)
                            .padding(.bottom, 8)
                        }
                        // 上滑时收起键盘
                        .scrollDismissesKeyboard(.interactively)
                        .coordinateSpace(name: Self.chatScrollCoordinateSpace)
                        .onPreferenceChange(ChatScrollOffsetKey.self) { offset in
                            handleScrollOffset(offset)
                        }
                        .onScrollContentOffsetChange { offset in
                            handleScrollGeometry(offset)
                        }
                        .onAppear {
                            timeTick = Date()
                            DispatchQueue.main.async {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        }
                        .onChange(of: viewModel.messages.count) {
                            autoScrollIfNeeded(proxy: proxy)
                        }
                    }
                }

                // 底部输入栏
                if !viewModel.billingNotice.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                        Text(viewModel.billingNotice)
                            .lineLimit(2)
                    }
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.phaseMenstrual)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ChatInputBarView(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming
                ) {
                    sendCurrentInput()
                }
            }
            .background(
                Theme.background
                    .grainTexture(intensity: .subtle, seed: 99)
                    .ignoresSafeArea()
            )
            // 点击空白收起键盘
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            // 左侧边缘透明条：专门接右划手势，不被 ScrollView 拦截
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .global)
                            .onEnded { value in
                                let rightward = value.translation.width > 60
                                let notVertical = abs(value.translation.height) < 80
                                if rightward && notVertical {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedTab = 0
                                    }
                                }
                            }
                    )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task {
                await billing.refreshSubscriptionStatus()
                if billing.isSubscriptionActive {
        viewModel.billingNotice = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = 0
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityLabel(String(localized: "common.back"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingChatHistory = true
                        } label: {
                            Label(String(localized: "assistant.history.title"), systemImage: "clock.arrow.circlepath")
                        }

                        Button {
                            viewModel.discardCurrentConversation()
                        } label: {
                            Label(String(localized: "assistant.new_chat"), systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive) {
                            viewModel.clearHistory()
                        } label: {
                            Label(String(localized: "assistant.clear_history"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .sheet(isPresented: $showingChatHistory) {
                chatHistorySheet
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                timeTick = Date()
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { timeTick = $0 }
        }
    }

    // MARK: - Empty State（推荐问题首屏）

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            greetingBubble
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var greetingBubble: some View {
        Text(greetingBubbleText)
            .font(Theme.itim(size: 24))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 34)
    }

    private var greetingBubbleText: String {
        let name = sanitizedDisplayName
        if name.isEmpty {
            return String(localized: "assistant.greeting.bubble.no_name")
        }
        return String(format: String(localized: "assistant.greeting.bubble %@"), name)
    }

    // MARK: - History

    @ViewBuilder
    private var chatHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.chatSessions) { session in
                    Button {
                        viewModel.openSession(session.id)
                        showingChatHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(Theme.itim(size: 18))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(historySubtitle(for: session))
                                .font(Theme.itim(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteSession(session.id)
                        } label: {
                            Label(String(localized: "assistant.message.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "assistant.history.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        showingChatHistory = false
                    }
                }
            }
        }
    }

    private func historySubtitle(for session: AssistantViewModel.ChatSession) -> String {
        "\(formatHistoryDate(session.updatedAt)) · \(session.messages.count) \(String(localized: "assistant.history.messages_count_suffix"))"
    }

    private func formatHistoryDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .autoupdatingCurrent
        fmt.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    // MARK: - Message List with Date Separators

    @ViewBuilder
    private var dateSeparators: some View {
        let grouped = groupedMessages()
        let lastUserId = viewModel.messages.last(where: { $0.role == .user })?.id
        let now = timeTick
        ForEach(grouped, id: \.date) { group in
            ForEach(group.messages) { msg in
                ChatBubbleView(
                    message: msg,
                    captionBelow: messageCaptionBelow(msg, now: now),
                    onFollowUpTap: { question in
                        pendingForceScrollToBottom = true
                        Task { await viewModel.sendMessage(question) }
                    },
                    onCopyTap: { message in
                        UIPasteboard.general.string = message.content
                    },
                    onDeleteTap: { message in
                        viewModel.deleteMessage(message.id)
                    },
                    onRefreshTap: { message in
                        pendingForceScrollToBottom = true
                        Task { await viewModel.refreshUserMessage(message.id) }
                    },
                    showsRefreshAction: msg.role == .user &&
                        !msg.isStreaming &&
                        msg.id == lastUserId
                )
                .id(msg.id)
            }
        }
    }

    // MARK: - Helpers

    private func sendCurrentInput() {
        let text = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
                    viewModel.billingNotice = ""
        pendingForceScrollToBottom = true
        viewModel.inputText = ""
        Task { await viewModel.sendMessage(text) }
    }

    private func autoScrollIfNeeded(proxy: ScrollViewProxy) {
        guard pendingForceScrollToBottom else { return }
        scrollToBottom(proxy: proxy)
        pendingForceScrollToBottom = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        isProgrammaticScrolling = true
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isProgrammaticScrolling = false
        }
    }

    /// 用户向对话上方（历史消息方向）滚动时，自动收起顶部健康 Header。
    /// 两条路径把「向上滚动的距离」归一化后交给 handleScrollUpMagnitude：
    /// - iOS 17：GeometryReader 的 minY 增大（内容向下移动，delta > 0）；
    /// - iOS 18+：contentOffset.y 减小（delta < 0）。
    private func handleScrollOffset(_ offset: CGFloat) {
        defer { lastScrollOffset = offset }
        guard let lastScrollOffset else { return }
        handleScrollUpMagnitude(offset - lastScrollOffset)
    }

    private func handleScrollGeometry(_ contentOffsetY: CGFloat) {
        defer { lastScrollOffset = contentOffsetY }
        guard let lastScrollOffset else { return }
        handleScrollUpMagnitude(lastScrollOffset - contentOffsetY)
    }

    /// 累计「向上滚动」的位移，超过阈值后收起 Header；向下滚动时清零。
    private func handleScrollUpMagnitude(_ magnitude: CGFloat) {
        guard !isProgrammaticScrolling, !isHeaderCollapsed else { return }
        guard magnitude > 0 else {
            upwardScrollAccumulator = 0
            return
        }
        upwardScrollAccumulator += magnitude
        guard upwardScrollAccumulator > 12 else { return }
        upwardScrollAccumulator = 0
        withAnimation(.easeInOut(duration: 0.22)) {
            isHeaderCollapsed = true
        }
    }

    private struct MessageGroup {
        let date: Date
        let messages: [ChatMessage]
    }

    private func groupedMessages() -> [MessageGroup] {
        var result: [MessageGroup] = []
        var currentDate: Date?
        var currentMessages: [ChatMessage] = []

        for msg in viewModel.messages {
            if msg.sessionDate != currentDate {
                if !currentMessages.isEmpty {
                    result.append(MessageGroup(date: currentDate!, messages: currentMessages))
                }
                currentDate = msg.sessionDate
                currentMessages = [msg]
            } else {
                currentMessages.append(msg)
            }
        }
        if !currentMessages.isEmpty, let date = currentDate {
            result.append(MessageGroup(date: date, messages: currentMessages))
        }
        return result
    }

    @ViewBuilder
    private func dateSeparatorLabel(for date: Date) -> some View {
        let label = formatSectionDate(date)
        Text(label)
            .font(Theme.itim(size: 14))
            .foregroundStyle(Color.black.opacity(0.22))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    private func formatSectionDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "assistant.date.today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "assistant.date.yesterday") }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    private func messageCaptionBelow(_ message: ChatMessage, now: Date) -> String? {
        if message.isStreaming { return nil }
        if now.timeIntervalSince(message.timestamp) < Self.messageCaptionFadeInDelay { return nil }

        let cal = Calendar.current
        let hm = formatHourMinute(message.timestamp)
        if cal.isDate(message.timestamp, inSameDayAs: now) {
            return hm
        }
        let dayPrefix = formatRelativeDayPrefixForCaption(message.timestamp, referenceNow: now, cal: cal)
        return "\(dayPrefix) \(hm)"
    }

    private func formatHourMinute(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .autoupdatingCurrent
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func formatRelativeDayPrefixForCaption(_ date: Date, referenceNow: Date, cal: Calendar) -> String {
        let startDate = cal.startOfDay(for: date)
        let startNow = cal.startOfDay(for: referenceNow)
        if startDate > startNow {
            return formatMonthDay(date)
        }
        let daysAgo = cal.dateComponents([.day], from: startDate, to: startNow).day ?? 0
        switch daysAgo {
        case 1:
            return String(localized: "assistant.date.yesterday")
        case 2:
            return String(localized: "assistant.date.day_before_yesterday")
        default:
            break
        }
        if daysAgo >= 3, daysAgo <= 7 {
            let fmt = DateFormatter()
            fmt.locale = .autoupdatingCurrent
            fmt.setLocalizedDateFormatFromTemplate("EEEE")
            return fmt.string(from: date)
        }
        let msgYear = cal.component(.year, from: date)
        let nowYear = cal.component(.year, from: referenceNow)
        if msgYear == nowYear {
            return formatMonthDay(date)
        }
        return formatYearMonthDay(date)
    }

    private func formatMonthDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("M-d")
        return fmt.string(from: date)
    }

    private func formatYearMonthDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("y-M-d")
        return fmt.string(from: date)
    }

    private func greetingText(for context: CycleContext) -> String {
        let displayName = sanitizedDisplayName
        let phaseName = context.phase.displayName
        let day = context.dayInPhase
        let emoji = context.phase.emoji
        if displayName.isEmpty {
            return String(
                format: String(localized: context.isPredicted
                    ? "assistant.greeting.predicted.no_name %@ %lld %@"
                    : "assistant.greeting.no_name %@ %lld %@"),
                phaseName, day, emoji
            )
        }
        return String(
            format: String(localized: context.isPredicted
                ? "assistant.greeting.predicted %@ %@ %lld %@"
                : "assistant.greeting %@ %@ %lld %@"),
            displayName, phaseName, day, emoji
        )
    }

    private var sanitizedDisplayName: String {
        DisplayName.sanitized(displayName)
    }

    /// 仅当免费对话剩余条数低于阈值时显示，且用户可手动关闭，避免信息常驻顶部。
    @ViewBuilder
    private var lowQuotaWarningBar: some View {
        let remaining = billing.freeChatRemaining
        if !billing.isSubscriptionActive,
           !dismissedLowQuotaWarning,
           remaining > 0,
           remaining <= Self.lowQuotaWarningThreshold {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                Text(String(format: String(localized: "billing.free_chat.warning_low"), remaining))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        dismissedLowQuotaWarning = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "billing.free_chat.warning_dismiss_a11y"))
            }
            .font(Theme.itim(size: 14))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.cardBackgroundSolid.opacity(0.95))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.2)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

}

#Preview {
    @Previewable @State var tab = 1
    let vm = AssistantViewModel()
    vm.suggestedQuestions = ["今天适合高强度训练吗？", "卵泡期应该怎么调整饮食？", "为什么最近睡眠变浅了？"]
    return AssistantView(viewModel: vm, selectedTab: $tab)
}
