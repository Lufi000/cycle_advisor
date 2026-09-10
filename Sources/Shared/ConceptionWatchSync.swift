import Foundation
import WatchConnectivity
#if os(watchOS)
import UserNotifications
#endif

/// 验孕提示状态 iPhone→Watch 单向同步（spec §4.1 的明确例外，仅 tier+原因+周期起点，不回传）。
/// iPhone 在 ConceptionInsightManager.refresh() 算出 insight 后 push 最新状态；
/// 手表收到后自行调度本地通知（去重 key 与 iPhone 侧同构，但各存各的 UserDefaults，互不影响）。
final class ConceptionWatchSync: NSObject {

    static let shared = ConceptionWatchSync()

    /// 手表本地通知 ID 与去重 UserDefaults key
    static let notificationID = "conception.pregnancy.prompt.watch"
    static let lastNotifiedKey = "conception.prompt.watch.lastNotified"

    private override init() {}

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Payload（property-list dict，WC 原生格式）

    static func dedupeKey(tier: String, cycleStart: Date?) -> String {
        "\(tier)@\(Int(cycleStart?.timeIntervalSince1970 ?? 0))"
    }

    /// 纯函数：同一 tier 同一周期只通知一次；possible→likely 升级或新周期会再次通知
    static func watchShouldNotify(tier: String, lastNotified: String?, cycleStart: Date?) -> Bool {
        guard tier == "possible" || tier == "likely" else { return false }
        return lastNotified != dedupeKey(tier: tier, cycleStart: cycleStart)
    }

    /// 原因格式化（双端共用，复用 conception.reason.* 翻译）
    static func reasonText(type: String, value: Int) -> String? {
        switch type {
        case "high_temp":
            return String(format: String(localized: "conception.reason.high_temp"), Int64(value))
        case "period_late":
            return String(format: String(localized: "conception.reason.period_late"), Int64(value))
        case "rhr":
            return String(format: String(localized: "conception.reason.rhr"), Int64(value))
        case "hrv":
            return String(format: String(localized: "conception.reason.hrv"), Int64(value))
        case "symptoms":
            return String(format: String(localized: "conception.reason.symptoms"), Int64(value))
        default:
            return nil
        }
    }
}

// MARK: - iOS：发送端

#if os(iOS)
extension ConceptionWatchSync {

    /// insight → payload：possible/likely 带 tier+原因（截断 3 条），其余状态一律 none
    static func payload(for insight: PregnancyInsight, cycleStart: Date?) -> [String: Any] {
        switch insight {
        case .possible(let reasons):
            return makePayload(tier: "possible", reasons: reasons, cycleStart: cycleStart)
        case .likely(let reasons):
            return makePayload(tier: "likely", reasons: reasons, cycleStart: cycleStart)
        default:
            return makePayload(tier: "none", reasons: [], cycleStart: cycleStart)
        }
    }

    private static func makePayload(tier: String, reasons: [InsightReason], cycleStart: Date?) -> [String: Any] {
        [
            "tier": tier,
            "reasons": reasons.prefix(3).map { [$0.typeKey, $0.value] as [Any] },
            "cycleStart": cycleStart?.timeIntervalSince1970 ?? 0.0
        ]
    }

    /// 每次 refresh 后调用；updateApplicationContext 只保留最新状态，失败回退 transferUserInfo
    func push(insight: PregnancyInsight, cycleStart: Date?) {
        guard let session else { return }
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        }
        do {
            try session.updateApplicationContext(Self.payload(for: insight, cycleStart: cycleStart))
        } catch {
            session.transferUserInfo(Self.payload(for: insight, cycleStart: cycleStart))
        }
    }
}

private extension InsightReason {
    var typeKey: String {
        switch self {
        case .sustainedHighTemperature: return "high_temp"
        case .periodLate: return "period_late"
        case .elevatedRestingHeartRate: return "rhr"
        case .suppressedHRV: return "hrv"
        case .earlySymptoms: return "symptoms"
        }
    }

    var value: Int {
        switch self {
        case .sustainedHighTemperature(let days): return days
        case .periodLate(let days): return days
        case .elevatedRestingHeartRate(let delta): return delta
        case .suppressedHRV(let percent): return percent
        case .earlySymptoms(let count): return count
        }
    }
}
#endif

// MARK: - watchOS：接收端

#if os(watchOS)
extension ConceptionWatchSync {

    func handle(payload: [String: Any]) {
        let tier = payload["tier"] as? String ?? "none"
        // WC property-list 往返后是 NSNumber，统一走 NSNumber 取值
        let rawStart = (payload["cycleStart"] as? NSNumber)?.doubleValue ?? 0
        let cycleStart = rawStart > 0 ? Date(timeIntervalSince1970: rawStart) : nil

        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()

        guard Self.watchShouldNotify(
            tier: tier,
            lastNotified: defaults.string(forKey: Self.lastNotifiedKey),
            cycleStart: cycleStart
        ) else {
            // 状态降级（阴性/忽略/关闭备孕）→ 撤销未送达通知，清去重 key 以便下次重新提示
            if tier == "none" {
                center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
                defaults.removeObject(forKey: Self.lastNotifiedKey)
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: tier == "likely"
            ? "notify.conception.likely"
            : "notify.conception.possible")
        let reasons = payload["reasons"] as? [[Any]] ?? []
        let body = reasons.compactMap { pair -> String? in
            guard let type = pair.first as? String, let value = pair.last as? Int else { return nil }
            return Self.reasonText(type: type, value: value)
        }.joined(separator: ", ")
        if !body.isEmpty { content.body = body }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.add(UNNotificationRequest(
            identifier: Self.notificationID, content: content, trigger: trigger
        ))

        defaults.set(Self.dedupeKey(tier: tier, cycleStart: cycleStart), forKey: Self.lastNotifiedKey)
    }
}
#endif

// MARK: - WCSessionDelegate

extension ConceptionWatchSync: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    #if os(watchOS)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(payload: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(payload: userInfo)
    }
    #endif
}
