import Foundation

// MARK: - 提示等级

enum PregnancyInsight: Equatable {
    /// 数据不足，不出任何提示
    case insufficient
    /// 已定位排卵，高温相 < 12 天（展示黄体期第 X 天）
    case tracking(lutealDay: Int)
    /// 温和提示：现在可以用验孕棒检测了
    case possible(reasons: [InsightReason])
    /// 较强提示：建议尽快验孕确认（必须有温度主信号）
    case likely(reasons: [InsightReason])
}

/// 提示触发原因（用于 UI 解释展示）
enum InsightReason: Equatable {
    case sustainedHighTemperature(days: Int)
    case periodLate(days: Int)
    case elevatedRestingHeartRate(deltaBPM: Int)
    case suppressedHRV(percent: Int)
    case earlySymptoms(count: Int)
}

// MARK: - 判定引擎（本地纯逻辑）

/// 信号分层：温度主信号独立触发；RHR/HRV/症状为佐证只升档；经期推迟为基础信号。
struct PregnancyInsightEngine {

    struct Input {
        /// 已合并的体温序列（手表优先）
        var temperatures: [BasalTemperatureEntry]
        var vitals: [DailyVitals]
        var symptoms: [SymptomRecord]
        var lastPeriodStart: Date?
        /// 预期经期日（由 CyclePhaseEngine.nextPeriodDate 得出）
        var expectedPeriodStart: Date?
        var referenceDate: Date
        var testFeedback: PregnancyTestFeedback?
        var dismissedUntil: Date?
    }

    /// 佐证信号集合（全部相对个人卵泡期基线，不设绝对阈值）
    struct CorroboratingSignals: Equatable {
        var rhrDeltaBPM: Int?
        var hrvDropPercent: Int?
        var earlySymptomCount: Int

        var count: Int {
            (rhrDeltaBPM != nil ? 1 : 0)
                + (hrvDropPercent != nil ? 1 : 0)
                + (earlySymptomCount >= 2 ? 1 : 0)
        }
    }

    private let locator = OvulationLocator()

    init() {}

    func evaluate(_ input: Input) -> PregnancyInsight {
        // 阳性反馈：停止一切提示
        if let feedback = input.testFeedback, case .positive = feedback {
            return .insufficient
        }

        let calendar = Calendar.current
        let refDay = calendar.startOfDay(for: input.referenceDate)
        let located = locator.locate(temperatures: input.temperatures, referenceDate: refDay)

        // 排卵若发生在本次经期之前，属于上一周期，不用来判定
        let usable: OvulationLocator.Result? = located.flatMap { result in
            if let period = input.lastPeriodStart,
               calendar.startOfDay(for: period) > result.ovulationDay {
                return nil
            }
            return result
        }

        let lateDays = periodLateDays(
            expected: input.expectedPeriodStart,
            lastPeriodStart: input.lastPeriodStart,
            referenceDay: refDay
        )
        let symptomWindowStart = usable?.ovulationDay
            ?? input.lastPeriodStart.map { calendar.startOfDay(for: $0) }
        let signals = corroboratingSignals(
            vitals: input.vitals,
            symptoms: input.symptoms,
            lastPeriodStart: input.lastPeriodStart,
            symptomWindowStart: symptomWindowStart,
            referenceDay: refDay
        )

        var insight: PregnancyInsight
        if let result = usable, result.isStillElevated {
            let lutealDay = calendar.dateComponents([.day], from: result.ovulationDay, to: refDay).day ?? 0
            var reasons: [InsightReason] = [.sustainedHighTemperature(days: result.highTemperatureDays)]
            if lateDays > 0 { reasons.append(.periodLate(days: lateDays)) }
            reasons.append(contentsOf: signalReasons(signals))

            if result.highTemperatureDays >= 16
                || (result.highTemperatureDays >= 14 && signals.count >= 2) {
                // 使用降权（干扰标记）数据时置信降一级
                insight = result.usedDisturbedEntries
                    ? .possible(reasons: reasons)
                    : .likely(reasons: reasons)
            } else if result.highTemperatureDays >= 12
                || (lateDays >= 1 && lateDays <= 3 && signals.count >= 1) {
                insight = .possible(reasons: reasons)
            } else {
                insight = .tracking(lutealDay: lutealDay)
            }
        } else if usable == nil, located == nil {
            // 降级路径：完全无温度数据，无法定位排卵
            if lateDays >= 3 && signals.count >= 2 {
                var reasons: [InsightReason] = [.periodLate(days: lateDays)]
                reasons.append(contentsOf: signalReasons(signals))
                insight = .possible(reasons: reasons)
            } else {
                insight = .insufficient
            }
        } else {
            // 高温相已回落（月经将至/新周期已开始）
            insight = .insufficient
        }

        return applyFeedbackGating(insight, input: input, usable: usable, refDay: refDay)
    }

    // MARK: - 基础信号

    /// 月经推迟天数（经期已至则为 0）
    private func periodLateDays(expected: Date?, lastPeriodStart: Date?, referenceDay: Date) -> Int {
        guard let expected else { return 0 }
        let calendar = Calendar.current
        let expectedDay = calendar.startOfDay(for: expected)
        if let last = lastPeriodStart, calendar.startOfDay(for: last) >= expectedDay { return 0 }
        return max(0, calendar.dateComponents([.day], from: expectedDay, to: referenceDay).day ?? 0)
    }

    // MARK: - 佐证信号

    private func corroboratingSignals(
        vitals: [DailyVitals],
        symptoms: [SymptomRecord],
        lastPeriodStart: Date?,
        symptomWindowStart: Date?,
        referenceDay: Date
    ) -> CorroboratingSignals {
        let calendar = Calendar.current

        // 卵泡期基线：本周期前 7 天滚动均值
        var rhrBaseline: Double?
        var hrvBaseline: Double?
        if let start = lastPeriodStart.map({ calendar.startOfDay(for: $0) }),
           let end = calendar.date(byAdding: .day, value: 7, to: start) {
            let window = vitals.filter { $0.date >= start && $0.date < end }
            let rhrs = window.compactMap(\.restingHeartRate)
            let hrvs = window.compactMap(\.hrvSDNN)
            if !rhrs.isEmpty { rhrBaseline = rhrs.reduce(0, +) / Double(rhrs.count) }
            if !hrvs.isEmpty { hrvBaseline = hrvs.reduce(0, +) / Double(hrvs.count) }
        }

        // RHR 升高：最近 5 个有读数的日均 ≥ 基线 + 2（未孕周期 RHR 经前回落，怀孕则持续爬升）
        var rhrDelta: Int?
        if let baseline = rhrBaseline {
            let recent = vitals
                .filter { $0.date <= referenceDay }
                .compactMap { $0.restingHeartRate }
                .suffix(5)
            if recent.count >= 5, recent.allSatisfy({ $0 >= baseline + 2 }) {
                rhrDelta = Int((recent.reduce(0, +) / 5.0 - baseline).rounded())
            }
        }

        // HRV 抑制：最近 5 个有读数的日均 ≤ 基线 × 0.9
        var hrvDrop: Int?
        if let baseline = hrvBaseline, baseline > 0 {
            let recent = vitals
                .filter { $0.date <= referenceDay }
                .compactMap { $0.hrvSDNN }
                .suffix(5)
            if recent.count >= 5, recent.allSatisfy({ $0 <= baseline * 0.9 }) {
                let average = recent.reduce(0, +) / 5.0
                hrvDrop = Int(((baseline - average) / baseline * 100).rounded())
            }
        }

        // 早孕症状：窗口内去重计数（恶心/呕吐/疲倦/乳房胀痛/点滴出血）
        var symptomCount = 0
        if let windowStart = symptomWindowStart {
            symptomCount = Set(
                symptoms
                    .filter { $0.date >= windowStart
                        && PregnancySymptomType.earlyPregnancySignals.contains($0.type) }
                    .map(\.type)
            ).count
        }

        return CorroboratingSignals(
            rhrDeltaBPM: rhrDelta,
            hrvDropPercent: hrvDrop,
            earlySymptomCount: symptomCount
        )
    }

    private func signalReasons(_ signals: CorroboratingSignals) -> [InsightReason] {
        var reasons: [InsightReason] = []
        if let delta = signals.rhrDeltaBPM { reasons.append(.elevatedRestingHeartRate(deltaBPM: delta)) }
        if let percent = signals.hrvDropPercent { reasons.append(.suppressedHRV(percent: percent)) }
        if signals.earlySymptomCount >= 2 { reasons.append(.earlySymptoms(count: signals.earlySymptomCount)) }
        return reasons
    }

    // MARK: - 反馈门控

    /// 阴性（本周期内）与忽略（7 天内）把 possible/likely 降回 tracking/insufficient
    private func applyFeedbackGating(
        _ insight: PregnancyInsight,
        input: Input,
        usable: OvulationLocator.Result?,
        refDay: Date
    ) -> PregnancyInsight {
        let calendar = Calendar.current
        var suppressed = false

        if let feedback = input.testFeedback, case .negative(_, let cycleStart) = feedback {
            let currentCycle = input.lastPeriodStart.map { calendar.startOfDay(for: $0) }
            let feedbackCycle = cycleStart.map { calendar.startOfDay(for: $0) }
            // 无新经期数据，或经期日未超过反馈时的周期起点 → 仍在同一周期
            if let current = currentCycle {
                suppressed = current <= (feedbackCycle ?? .distantPast)
            } else {
                suppressed = feedbackCycle == nil
            }
        }
        if let until = input.dismissedUntil, refDay < calendar.startOfDay(for: until) {
            suppressed = true
        }

        guard suppressed else { return insight }
        switch insight {
        case .possible, .likely:
            if let usable {
                let lutealDay = calendar.dateComponents([.day], from: usable.ovulationDay, to: refDay).day ?? 0
                return .tracking(lutealDay: lutealDay)
            }
            return .insufficient
        default:
            return insight
        }
    }
}
