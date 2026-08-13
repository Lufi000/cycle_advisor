import Foundation
import StoreKit

/// 用户档案管理器：持久化、HealthKit 积累、AI 对话提取
@Observable
final class UserProfileManager {

    static let shared = UserProfileManager()

    private(set) var profile: UserProfile = .empty

    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_profile.json")
    }()

    private let appGroupID = "group.com.cycleadvisor.shared"
    private let widgetProfileKey = "widget.profile"

    private init() {
        load()
    }

    // MARK: - Persistence

    func save() {
        profile.lastUpdated = Date()
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
        persistWidgetSnapshot()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return }
        profile = saved
    }

    func resetField(_ keyPath: WritableKeyPath<UserProfile, String?>) {
        profile[keyPath: keyPath] = nil
        save()
    }

    func resetLifestyleDietaryPreferences() {
        profile.lifestyle.dietaryPreferences = []
        save()
    }

    func resetKnownConditions() {
        profile.knownConditions = []
        save()
    }

    func resetKnownSensitivities() {
        profile.lifestyle.knownSensitivities = []
        save()
    }

    func resetAll() {
        profile = .empty
        try? FileManager.default.removeItem(at: fileURL)
        persistWidgetSnapshot()
    }

    // MARK: - HealthKit Accumulation

    /// 从 HealthKit 数据积累档案信息。由 HomeViewModel 在 HealthKit 更新后调用。
    func accumulate(
        context: CycleContext,
        bodyInfo: BodyInfo,
        workoutStats: WorkoutStats,
        cycleLengths: [Int],
        periodDurations: [Int]
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 更新身体信息（每次都覆盖，取最新值）
        profile.bodyInfo = bodyInfo

        // 更新运动统计（每次都覆盖，取最新快照）
        profile.workoutStats = workoutStats

        // 时间窗口快照每次刷新；只有历史频次/模式每天最多累计一次。
        profile.accumulatedStats.currentCycleFlowLevel = context.menstrualSymptoms.flowLevel

        let activeSymptoms = context.menstrualSymptoms.activeSymptoms
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()) ?? today
        profile.accumulatedStats.currentCycleSymptoms = activeSymptoms
        profile.accumulatedStats.recentSymptoms48h = activeSymptoms.filter { $0.date >= twoDaysAgo }

        // 周期统计：每天最多积累一次
        if let lastDate = profile.accumulatedStats.lastAccumulationDate,
           calendar.isDate(lastDate, inSameDayAs: today) {
            save()
            return
        }

        // 更新历史周期长度
        if !cycleLengths.isEmpty {
            profile.accumulatedStats.cycleLengths = cycleLengths
            profile.accumulatedStats.cyclesRecorded = cycleLengths.count
        }

        // 更新历史经期天数
        if !periodDurations.isEmpty {
            profile.accumulatedStats.periodDurations = periodDurations
        }

        // 积累当前出血量模式（仅在经期阶段）
        if context.phase == .menstrual, let flow = context.menstrualSymptoms.flowLevel {
            let dayKey = String(context.dayInPhase)
            profile.accumulatedStats.flowPatternByDay[dayKey] = flow.rawValue
        }

        // 积累当前症状频次
        if !activeSymptoms.isEmpty {
            let phaseKey = context.phase.rawValue
            var freqs = profile.accumulatedStats.symptomFrequencies[phaseKey] ?? [:]
            for symptom in activeSymptoms {
                let symptomKey = symptom.type.rawValue
                freqs[symptomKey, default: 0] += 1
            }
            profile.accumulatedStats.symptomFrequencies[phaseKey] = freqs
        }

        profile.accumulatedStats.lastAccumulationDate = today
        save()
    }

    // MARK: - AI Conversation Extraction

    /// 从 AI 对话中提取用户档案信息
    func extractFromChat(userMessage: String, assistantReply: String) async {
        guard profile.hasEmptyLifestyleFields else { return }

        do {
            let extracted = try await LLMService.shared.extractProfileFields(
                userMessage: userMessage,
                assistantReply: assistantReply
            )
            mergeExtracted(extracted)
        } catch {
            print("[UserProfileManager] extraction failed: \(error)")
        }
    }

    /// 合并提取结果到档案（只填充空字段，不覆盖已有数据）
    private func mergeExtracted(_ fields: ExtractedProfileFields) {
        var changed = false

        if let sleep = fields.sleepPattern, profile.lifestyle.sleepPattern == nil {
            profile.lifestyle.sleepPattern = sleep
            profile.lifestyle.sleepPatternObservedAt = Date()
            changed = true
        }
        if !fields.dietaryPreferences.isEmpty, profile.lifestyle.dietaryPreferences.isEmpty {
            profile.lifestyle.dietaryPreferences = fields.dietaryPreferences
            changed = true
        }
        if !fields.knownConditions.isEmpty, profile.knownConditions.isEmpty {
            profile.knownConditions = fields.knownConditions
            changed = true
        }
        if !fields.knownSensitivities.isEmpty, profile.lifestyle.knownSensitivities.isEmpty {
            profile.lifestyle.knownSensitivities = fields.knownSensitivities
            changed = true
        }

        if changed {
            profile.lifestyle.lastExtractedAt = Date()
            save()
        }
    }

    // MARK: - Widget

    private func persistWidgetSnapshot() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: widgetProfileKey)
    }
}

// MARK: - Extracted Profile Fields (from AI)

struct ExtractedProfileFields: Codable {
    var sleepPattern: String?
    var dietaryPreferences: [String]
    var knownConditions: [String]
    var knownSensitivities: [String]

    enum CodingKeys: String, CodingKey {
        case sleepPattern = "sleep_pattern"
        case dietaryPreferences = "dietary_preferences"
        case knownConditions = "known_conditions"
        case knownSensitivities = "known_sensitivities"
    }
}

// MARK: - Subscription Billing Manager

@MainActor
@Observable
final class BillingManager {

    static let shared = BillingManager()

    static let monthlySubscriptionProductID = "com.cycleadvisor.premium.monthly"
    static let monthlySubscriptionFallbackTitle = "¥38/month"
    static let monthlySubscriptionPriceCNYFen = 3_800
    static let tokensPerCredit = 10_000

    struct PendingChargeReservation {
        let id: String
        let estimatedCredits: Int
        let usedFreeChat: Bool
        let usedSubscription: Bool
        let freeChatDayKey: String?
        let source: CreditLedgerSource
        let createdAt: Date
    }

    struct BillingSevenDaySnapshot {
        var assistantChatCount: Int
        var suggestionRefreshCount: Int
        var creditsConsumed: Int
        var rechargeOrderCount: Int
        var paidAmountCNYFen: Int
        var refundCredits: Int
    }

    enum PricingAdjustmentSuggestion: Equatable {
        case keep
        case decreaseCreditsBy10To15
        case increaseEntryCreditsBy10
        case improveMidTierValue
    }

    enum BillingError: LocalizedError {
        case insufficientCredits
        case rateLimited
        case dailyLimitReached
        case purchaseUnavailable
        case purchaseNotVerified
        case subscriptionRequired

        var errorDescription: String? {
            switch self {
            case .insufficientCredits:
                return String(localized: "billing.error.insufficient_credits")
            case .rateLimited:
                return String(localized: "billing.error.rate_limited")
            case .dailyLimitReached:
                return String(localized: "billing.error.daily_limit")
            case .purchaseUnavailable:
                return String(localized: "billing.error.purchase_unavailable")
            case .purchaseNotVerified:
                return String(localized: "billing.error.purchase_not_verified")
            case .subscriptionRequired:
                return String(localized: "billing.error.subscription_required")
            }
        }
    }

    enum PurchaseOutcome {
        case success
        case userCancelled
        case pending
        case alreadyInProgress

        var message: String? {
            switch self {
            case .success:
                return nil
            case .userCancelled:
                return String(localized: "billing.action.purchase_cancelled")
            case .pending:
                return String(localized: "billing.action.purchase_pending")
            case .alreadyInProgress:
                return String(localized: "billing.action.purchase_in_progress")
            }
        }
    }

    private(set) var state: BillingAccountState = .initial
    private(set) var storeProducts: [String: Product] = [:]
    private(set) var isLoadingStoreProducts = false
    /// 已发起一次购买，且尚未走完 success/userCancelled/pending 分支。用于按钮防抖。
    private(set) var isPurchasing: Bool = false
    /// 最近一次 `loadStoreProducts()` 是否失败（包含拿到的产品列表为空的情形）。
    /// 仅用于 UI 决策：显示「重试」/「Loading…」/价格三种状态之一。
    private(set) var lastProductLoadFailed: Bool = false
    private var transactionUpdatesTask: Task<Void, Never>?
    private var pendingReservations: [String: PendingChargeReservation] = [:]

    private let minAssistantRequestInterval: TimeInterval = 1.2
    private let maxAssistantChatsPerDay = 120
    private let keepUsageHistoryDays = 14
    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("billing_state.json")
    }()

    private init() {
        load()
        cleanupExpiredUsageWindow()
        Task {
            await loadStoreProducts()
            await refreshSubscriptionStatus()
        }
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionUpdate: update)
            }
        }
    }

    var freeChatRemaining: Int {
        freeChatRemaining(on: Date())
    }
    var creditsBalance: Int { state.creditsBalance }
    var assistantChatsRemainingToday: Int {
        let todayKey = dayKeyString(for: Date())
        let todayCount = state.dailyMetrics[todayKey]?.assistantChatCount ?? 0
        return max(0, maxAssistantChatsPerDay - todayCount)
    }
    var isSubscriptionActive: Bool {
        guard let expiration = state.subscriptionExpirationDate else { return false }
        return expiration > Date()
    }
    var subscriptionExpirationDate: Date? { state.subscriptionExpirationDate }
    var subscriptionStatusText: String {
        if let expiration = state.subscriptionExpirationDate, expiration > Date() {
            return String(format: String(localized: "billing.subscription.active_until"), expiration.formatted(date: .abbreviated, time: .omitted))
        }
        return String(localized: "billing.subscription.inactive")
    }
    var lowBalanceThresholdCredits: Int { state.lowBalanceThresholdCredits }
    var shouldWarnLowBalance: Bool {
        freeChatRemaining == 0 && !isSubscriptionActive
    }

    func estimatedCredits(forTokens tokens: Int) -> Int {
        max(1, Int(ceil(Double(max(0, tokens)) / Double(Self.tokensPerCredit))))
    }

    private func freeChatRemaining(on date: Date) -> Int {
        let dayKey = dayKeyString(for: date)
        let used = state.freeChatUsageByDay?[dayKey] ?? 0
        return max(0, state.freeChatQuotaTotal - used)
    }

    func suggestionRefreshRemainingToday(on date: Date = Date()) -> Int {
        let dayKey = dayKeyString(for: date)
        let used = Set(state.suggestionQuotaUsageByDay[dayKey] ?? [])
        return max(0, state.dailySuggestionQuota - used.count)
    }

    /// 早/中/晚各 1 次刷新配额，不累计到次日。
    func consumeSuggestionRefreshIfAvailable(on date: Date = Date()) -> Bool {
        cleanupExpiredUsageWindow(referenceDate: date)
        let dayKey = dayKeyString(for: date)
        let slot = SuggestionRefreshSlot.slot(for: date).rawValue
        var used = Set(state.suggestionQuotaUsageByDay[dayKey] ?? [])
        guard used.count < state.dailySuggestionQuota, !used.contains(slot) else {
            return false
        }
        used.insert(slot)
        state.suggestionQuotaUsageByDay[dayKey] = Array(used).sorted()
        bumpDailyMetric(on: date) { metric in
            metric.suggestionRefreshCount += 1
        }
        save()
        return true
    }

    func reserveAssistantChat(estimatedCredits: Int) throws -> String {
        let now = Date()
        try guardAssistantRiskRules(at: now)
        let reservationID = UUID().uuidString

        if isSubscriptionActive {
            state.lastAssistantRequestAt = now
            pendingReservations[reservationID] = PendingChargeReservation(
                id: reservationID,
                estimatedCredits: 0,
                usedFreeChat: false,
                usedSubscription: true,
                freeChatDayKey: nil,
                source: .assistantChat,
                createdAt: now
            )
            save()
            return reservationID
        }

        if freeChatRemaining(on: now) > 0 {
            let dayKey = dayKeyString(for: now)
            var usageByDay = state.freeChatUsageByDay ?? [:]
            usageByDay[dayKey, default: 0] += 1
            state.freeChatUsageByDay = usageByDay
            state.lastAssistantRequestAt = now
            pendingReservations[reservationID] = PendingChargeReservation(
                id: reservationID,
                estimatedCredits: 0,
                usedFreeChat: true,
                usedSubscription: false,
                freeChatDayKey: dayKey,
                source: .assistantChat,
                createdAt: now
            )
            save()
            return reservationID
        }

        throw BillingError.subscriptionRequired
    }

    func settleAssistantChat(reservationID: String, actualCredits: Int, succeeded: Bool) {
        guard let reservation = pendingReservations.removeValue(forKey: reservationID) else { return }
        let now = Date()

        if reservation.usedFreeChat || reservation.usedSubscription {
            if succeeded {
                bumpDailyMetric(on: now) { metric in
                    metric.assistantChatCount += 1
                    if reservation.usedSubscription {
                        metric.creditsConsumed += max(1, actualCredits)
                    }
                }
            } else {
                if reservation.usedFreeChat, let dayKey = reservation.freeChatDayKey {
                    var usageByDay = state.freeChatUsageByDay ?? [:]
                    usageByDay[dayKey] = max(0, (usageByDay[dayKey] ?? 0) - 1)
                    state.freeChatUsageByDay = usageByDay
                }
            }
            save()
            return
        }

        let held = reservation.estimatedCredits
        guard held > 0 else {
            save()
            return
        }

        if !succeeded {
            state.creditsBalance += held
            appendLedger(
                type: .refund,
                source: .assistantChat,
                delta: held,
                note: String(localized: "billing.ledger.rollback"),
                referenceID: reservationID
            )
            bumpDailyMetric(on: now) { metric in
                metric.refundCredits += held
            }
            save()
            return
        }

        let settledCredits = max(1, actualCredits)
        if settledCredits < held {
            let refund = held - settledCredits
            state.creditsBalance += refund
            appendLedger(
                type: .refund,
                source: .assistantChat,
                delta: refund,
                note: String(localized: "billing.ledger.refund"),
                referenceID: reservationID
            )
            bumpDailyMetric(on: now) { metric in
                metric.refundCredits += refund
            }
        } else if settledCredits > held {
            let extraNeeded = settledCredits - held
            let extraCharged = min(extraNeeded, state.creditsBalance)
            if extraCharged > 0 {
                state.creditsBalance -= extraCharged
                appendLedger(
                    type: .consume,
                    source: .assistantChat,
                    delta: -extraCharged,
                    note: String(localized: "billing.ledger.consume_extra"),
                    referenceID: reservationID
                )
            }
        }

        appendLedger(
            type: .consume,
            source: .assistantChat,
            delta: 0,
            note: String(format: String(localized: "billing.ledger.settle"), settledCredits),
            referenceID: reservationID
        )
        bumpDailyMetric(on: now) { metric in
            metric.assistantChatCount += 1
            metric.creditsConsumed += settledCredits
        }
        save()
    }

    func loadStoreProducts() async {
        if isLoadingStoreProducts {
            while isLoadingStoreProducts && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return
        }
        isLoadingStoreProducts = true
        defer { isLoadingStoreProducts = false }

        do {
            let ids = [Self.monthlySubscriptionProductID]
            let products = try await Product.products(for: ids)
            storeProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            // 即使请求成功，目标产品也可能未在 App Store Connect 配置 / 未通过审核 →
            // 此时 storeProducts 是空的，UI 仍应进入「失败/重试」状态。
            lastProductLoadFailed = storeProducts[Self.monthlySubscriptionProductID] == nil
        } catch {
            storeProducts = [:]
            lastProductLoadFailed = true
        }
    }

    /// 价格文案：仅当 StoreKit 真的回灌到产品时返回 `displayPrice`，否则返回 fallback。
    /// UI 应优先用 `hasLoadedSubscriptionProduct` 判断是否进入「Loading / 重试」态，
    /// 而不要直接把这个 fallback 当作真实价格展示给用户。
    var monthlySubscriptionDisplayPrice: String {
        storeProducts[Self.monthlySubscriptionProductID]?.displayPrice ?? Self.monthlySubscriptionFallbackTitle
    }

    /// StoreKit 是否已经成功取回订阅产品（即可以直接发起购买）。
    var hasLoadedSubscriptionProduct: Bool {
        storeProducts[Self.monthlySubscriptionProductID] != nil
    }

    @discardableResult
    func purchaseMonthlySubscription() async throws -> PurchaseOutcome {
        // 防止双击/快速连点触发并发购买——StoreKit 自身虽然会兜底，
        // 但提前在业务层拒掉，UI 的禁用态/loading 态会更稳定。
        guard !isPurchasing else { return .alreadyInProgress }
        isPurchasing = true
        defer { isPurchasing = false }

        if storeProducts[Self.monthlySubscriptionProductID] == nil {
            await loadStoreProducts()
        }
        guard let product = storeProducts[Self.monthlySubscriptionProductID] else {
            throw BillingError.purchaseUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            updateSubscriptionState(from: transaction)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    /// 调用 `AppStore.sync()` 让系统从 App Store 拉取该 Apple ID 下的最新交易，
    /// 然后刷新本地订阅状态。返回值表示「刷新后是否处于已订阅状态」。
    ///
    /// Apple Guideline 3.1.1 要求所有售卖订阅的 App 必须提供 Restore Purchases 入口。
    @discardableResult
    func restorePurchases() async throws -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            throw BillingError.purchaseUnavailable
        }
        await refreshSubscriptionStatus()
        return isSubscriptionActive
    }

    /// 用户在 Apple ID 账户中管理 / 取消订阅的回退 URL。
    /// SwiftUI 优先使用 `.manageSubscriptionsSheet(isPresented:)` 弹出系统表单；
    /// 当系统表单不可用（如 sandbox 环境异常）时，可由 UI 用这个 URL 打开 App Store。
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    func refreshSubscriptionStatus() async {
        var latestExpiration: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement),
                  transaction.productID == Self.monthlySubscriptionProductID,
                  transaction.revocationDate == nil
            else { continue }
            if let expiration = transaction.expirationDate, expiration > Date() {
                latestExpiration = max(latestExpiration ?? expiration, expiration)
            }
        }
        state.subscriptionProductID = latestExpiration == nil ? nil : Self.monthlySubscriptionProductID
        state.subscriptionExpirationDate = latestExpiration
        save()
    }

    private func handle(transactionUpdate update: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(update),
              transaction.productID == Self.monthlySubscriptionProductID
        else { return }
        updateSubscriptionState(from: transaction)
        await transaction.finish()
    }

    private func updateSubscriptionState(from transaction: Transaction) {
        guard transaction.revocationDate == nil else {
            state.subscriptionProductID = nil
            state.subscriptionExpirationDate = nil
            save()
            return
        }
        state.subscriptionProductID = transaction.productID
        state.subscriptionExpirationDate = transaction.expirationDate
        appendLedger(
            type: .recharge,
            source: .system,
            delta: 0,
            note: String(localized: "billing.ledger.subscription"),
            referenceID: String(transaction.id)
        )
        bumpDailyMetric(on: Date()) { metric in
            metric.rechargeOrderCount += 1
            metric.paidAmountCNYFen += Self.monthlySubscriptionPriceCNYFen
        }
        save()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw BillingError.purchaseNotVerified
        case .verified(let safe):
            return safe
        }
    }

    func recentLedger(limit: Int = 20) -> [CreditLedgerEntry] {
        Array(state.ledger.suffix(limit).reversed())
    }

    func sevenDaySnapshot(referenceDate: Date = Date()) -> BillingSevenDaySnapshot {
        let calendar = Calendar.current
        var snapshot = BillingSevenDaySnapshot(
            assistantChatCount: 0,
            suggestionRefreshCount: 0,
            creditsConsumed: 0,
            rechargeOrderCount: 0,
            paidAmountCNYFen: 0,
            refundCredits: 0
        )
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else { continue }
            let key = dayKeyString(for: day)
            guard let metric = state.dailyMetrics[key] else { continue }
            snapshot.assistantChatCount += metric.assistantChatCount
            snapshot.suggestionRefreshCount += metric.suggestionRefreshCount
            snapshot.creditsConsumed += metric.creditsConsumed
            snapshot.rechargeOrderCount += metric.rechargeOrderCount
            snapshot.paidAmountCNYFen += metric.paidAmountCNYFen
            snapshot.refundCredits += metric.refundCredits
        }
        return snapshot
    }

    /// 周度调价建议（V1）：按计划中的阈值给出可执行动作建议。
    func weeklyPricingSuggestion(
        estimatedCostPerCreditCNYFen: Double,
        overagePackPurchaseRate: Double,
        conversionIsLow: Bool
    ) -> PricingAdjustmentSuggestion {
        let snapshot = sevenDaySnapshot()
        let revenue = Double(snapshot.paidAmountCNYFen)
        guard revenue > 0 else { return .keep }

        let estimatedCost = Double(snapshot.creditsConsumed) * max(0, estimatedCostPerCreditCNYFen)
        let grossMargin = (revenue - estimatedCost) / revenue

        if grossMargin < 0.60 {
            return .decreaseCreditsBy10To15
        }
        if grossMargin > 0.80 && conversionIsLow {
            return .increaseEntryCreditsBy10
        }
        if overagePackPurchaseRate > 0.35 {
            return .improveMidTierValue
        }
        return .keep
    }

    private func guardAssistantRiskRules(at date: Date) throws {
        if let last = state.lastAssistantRequestAt,
           date.timeIntervalSince(last) < minAssistantRequestInterval {
            throw BillingError.rateLimited
        }

        let todayKey = dayKeyString(for: date)
        let todayCount = state.dailyMetrics[todayKey]?.assistantChatCount ?? 0
        if todayCount >= maxAssistantChatsPerDay {
            throw BillingError.dailyLimitReached
        }
    }

    private func bumpDailyMetric(on date: Date, _ transform: (inout BillingDailyMetric) -> Void) {
        let key = dayKeyString(for: date)
        var metric = state.dailyMetrics[key] ?? .empty(dateKey: key)
        transform(&metric)
        state.dailyMetrics[key] = metric
    }

    private func appendLedger(
        type: CreditLedgerEntryType,
        source: CreditLedgerSource,
        delta: Int,
        note: String,
        referenceID: String?
    ) {
        let entry = CreditLedgerEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            type: type,
            source: source,
            delta: delta,
            balanceAfter: state.creditsBalance,
            note: note,
            referenceID: referenceID
        )
        state.ledger.append(entry)
        if state.ledger.count > 300 {
            state.ledger = Array(state.ledger.suffix(300))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(BillingAccountState.self, from: data)
        else { return }
        state = saved
    }

    private func cleanupExpiredUsageWindow(referenceDate: Date = Date()) {
        let calendar = Calendar.current
        let validDayKeys = Set((0..<keepUsageHistoryDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: referenceDate).map(dayKeyString(for:))
        })
        state.suggestionQuotaUsageByDay = state.suggestionQuotaUsageByDay.filter { validDayKeys.contains($0.key) }
        state.freeChatUsageByDay = (state.freeChatUsageByDay ?? [:]).filter { validDayKeys.contains($0.key) }
        state.dailyMetrics = state.dailyMetrics.filter { validDayKeys.contains($0.key) }
        save()
    }

    private func dayKeyString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum SuggestionRefreshSlot: String {
    case morning
    case noon
    case evening

    static func slot(for date: Date) -> SuggestionRefreshSlot {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 { return .morning }
        if hour < 18 { return .noon }
        return .evening
    }
}
