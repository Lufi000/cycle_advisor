import Foundation

/// 排卵定位：3-over-6 规则。
/// 某日起连续 3 天温度 ≥ 前 6 个有效日均值 + 0.2°C → 判定升温，升温前最后一低温日为排卵日。
/// 腕温绝对值比口温高约 1°C，但规则看的是相对位移，阈值通用。
struct OvulationLocator {

    struct Result: Equatable {
        /// 排卵日 = 升温前最后一个有读数的低温日
        var ovulationDay: Date
        /// 截至参考日的高温相天数（缺测日照常计数，遇降温停止）
        var highTemperatureDays: Int
        /// 高温是否持续中（最新读数仍在高温线以上）
        var isStillElevated: Bool
        /// 定位是否使用了带干扰标记的补位条目（判定置信降一级）
        var usedDisturbedEntries: Bool
    }

    /// - Parameters:
    ///   - temperatures: 已合并的体温序列（任意顺序，同日只应有一条）
    ///   - referenceDate: 判定基准日（通常今天）
    /// - Returns: 定位结果；有效日 < 10 或未检测到双相时返回 nil
    func locate(temperatures: [BasalTemperatureEntry], referenceDate: Date) -> Result? {
        let calendar = Calendar.current
        let refDay = calendar.startOfDay(for: referenceDate)
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: refDay) else { return nil }

        // 有效性：手表条目全部有效；手动条目仅无干扰标记的有效。
        let valid = temperatures.filter { $0.source == .wristTemperature || $0.disturbances.isEmpty }
        // 降权补位：有干扰标记的手动条目仅在该日无有效读数时参与
        var usedDisturbed = false
        var series = valid
        for entry in temperatures where entry.source == .manual && !entry.disturbances.isEmpty {
            if !valid.contains(where: { calendar.isDate($0.date, inSameDayAs: entry.date) }) {
                series.append(entry)
                usedDisturbed = true
            }
        }

        var byDay: [Date: Double] = [:]
        for entry in series {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= cutoff, day <= refDay else { continue }
            byDay[day] = entry.celsius
        }
        guard byDay.count >= 10 else { return nil }

        // 候选升温起点 d：d, d+1, d+2 三天均有读数且都 ≥ [d-6, d-1] 读数均值 + 0.2；
        // [d-6, d+2] 共 9 天窗口内缺测 > 2 天则跳过。取最早一次升温。
        guard let firstDay = byDay.keys.min() else { return nil }
        var shiftStart: Date?
        var shiftThreshold = 0.0
        var day = firstDay

        while day <= refDay, shiftStart == nil {
            if let d1 = calendar.date(byAdding: .day, value: 1, to: day),
               let d2 = calendar.date(byAdding: .day, value: 2, to: day),
               let t0 = byDay[day], let t1 = byDay[d1], let t2 = byDay[d2] {
                var baseline: [Double] = []
                var presentCount = 3 // d, d+1, d+2 已确认有读数
                for offset in -6...(-1) {
                    if let dd = calendar.date(byAdding: .day, value: offset, to: day),
                       let value = byDay[dd] {
                        baseline.append(value)
                        presentCount += 1
                    }
                }
                if 9 - presentCount <= 2, !baseline.isEmpty {
                    let threshold = baseline.reduce(0, +) / Double(baseline.count) + 0.2
                    if t0 >= threshold, t1 >= threshold, t2 >= threshold {
                        shiftStart = day
                        shiftThreshold = threshold
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        guard let shift = shiftStart else { return nil }

        // 排卵日 = 升温前最后一个有读数的低温日
        let ovulationDay = byDay.keys.filter { $0 < shift }.max()
            ?? calendar.date(byAdding: .day, value: -1, to: shift)!

        // 高温相计数：从升温起点走到参考日，遇低于阈值的读数停止
        var highDays = 0
        var stillElevated = true
        var cursor = shift
        while cursor <= refDay {
            if let value = byDay[cursor] {
                if value >= shiftThreshold {
                    highDays += 1
                } else {
                    stillElevated = false
                    break
                }
            } else {
                highDays += 1 // 缺测日不中断高温相
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return Result(
            ovulationDay: ovulationDay,
            highTemperatureDays: highDays,
            isStillElevated: stillElevated,
            usedDisturbedEntries: usedDisturbed
        )
    }
}
