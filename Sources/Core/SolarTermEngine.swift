import Foundation

/// 节气计算引擎 — 基于简化 VSOP87 天文算法，本地计算 24 节气日期
struct SolarTermEngine {

    // MARK: - Public API

    /// 计算某年全部 24 节气的日期
    func termsForYear(_ year: Int) -> [SolarTermInfo] {
        SolarTerm.calendarOrder.map { term in
            let date = findTermDate(term: term, year: year)
            return SolarTermInfo(term: term, date: date, year: year)
        }
    }

    /// 当前节气与下一个节气（自动处理跨年）
    func currentAndNext(on date: Date = .now) -> (current: SolarTermInfo, next: SolarTermInfo) {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        // 计算当年 + 下年，覆盖年末跨年场景
        let terms = termsForYear(year) + termsForYear(year + 1)
        let sorted = terms.sorted { $0.date < $1.date }

        var currentIdx = 0
        for (i, info) in sorted.enumerated() {
            if info.date <= date {
                currentIdx = i
            }
        }
        let nextIdx = min(currentIdx + 1, sorted.count - 1)
        return (sorted[currentIdx], sorted[nextIdx])
    }

    /// 距下一个节气的天数
    func daysUntilNext(from date: Date = .now) -> Int {
        let (_, next) = currentAndNext(on: date)
        return Calendar.current.dateComponents([.day], from: date, to: next.date).day ?? 0
    }

    // MARK: - Astronomical Calculation

    /// 查找太阳到达目标黄经的日期
    private func findTermDate(term: SolarTerm, year: Int) -> Date {
        let targetLon = term.longitude
        let approxJD = approximateJD(for: targetLon, year: year)
        return refineToDate(targetLongitude: targetLon, approximateJD: approxJD)
    }

    /// 计算给定儒略日的太阳视黄经（度）
    private func solarLongitude(jd: Double) -> Double {
        let T = (jd - 2451545.0) / 36525.0

        // 平黄经
        let L0 = normalized(280.46646 + 36000.76983 * T + 0.0003032 * T * T)

        // 平近点角（弧度）
        let MRad = (357.52911 + 35999.05029 * T - 0.0001537 * T * T) * .pi / 180.0

        // 中心差
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(MRad)
            + (0.019993 - 0.000101 * T) * sin(2 * MRad)
            + 0.000289 * sin(3 * MRad)

        // 真黄经
        let sunLon = L0 + C

        // 章动和光行差修正
        let omega = (125.04 - 1934.136 * T) * .pi / 180.0
        let apparent = sunLon - 0.00569 - 0.00478 * sin(omega)

        return normalized(apparent)
    }

    /// 二分法精确搜索太阳到达目标黄经的儒略日
    private func refineToDate(targetLongitude: Double, approximateJD: Double) -> Date {
        var lo = approximateJD - 25
        var hi = approximateJD + 25

        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            let lon = solarLongitude(jd: mid)
            let diff = angleDifference(from: lon, to: targetLongitude)
            if diff > 0 {
                lo = mid
            } else {
                hi = mid
            }
        }

        let jd = (lo + hi) / 2
        return dateFromJD(jd)
    }

    /// 有符号角度差（处理 360°/0° 跨越）
    private func angleDifference(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// 角度归一化到 [0, 360)
    private func normalized(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    // MARK: - Julian Day Helpers

    /// 估算目标黄经对应的大致儒略日
    private func approximateJD(for longitude: Double, year: Int) -> Double {
        // 春分（黄经 0°）大约在 3 月 20 日
        // 每 15° 大约间隔 ~15.22 天
        let marchEquinoxJD = jdFromGregorian(year: year, month: 3, day: 20)
        let offset = angleDifference(from: 0, to: longitude) // 从春分算起的度数偏移
        let daysOffset = offset / 360.0 * 365.25
        return marchEquinoxJD + daysOffset
    }

    /// 格里历日期 → 儒略日
    private func jdFromGregorian(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year)
        var m = Double(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let A = floor(y / 100)
        let B = 2 - A + floor(A / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + B - 1524.5
    }

    /// 儒略日 → Date（UTC）
    private func dateFromJD(_ jd: Double) -> Date {
        // 儒略日 → 格里历分量
        let z = floor(jd + 0.5)
        let f = jd + 0.5 - z

        let alpha = floor((z - 1867216.25) / 36524.25)
        let a = z + 1 + alpha - floor(alpha / 4)

        let b = a + 1524
        let c = floor((b - 122.1) / 365.25)
        let d = floor(365.25 * c)
        let e = floor((b - d) / 30.6001)

        let day = Int(b - d - floor(30.6001 * e))
        let month: Int
        if e < 14 {
            month = Int(e) - 1
        } else {
            month = Int(e) - 13
        }
        let year: Int
        if month > 2 {
            year = Int(c) - 4716
        } else {
            year = Int(c) - 4715
        }

        // f 是当天的小数部分（UTC 时间）
        let totalSeconds = f * 86400.0
        let hour = Int(totalSeconds / 3600)
        let minute = Int((totalSeconds - Double(hour) * 3600) / 60)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar.current.date(from: components) ?? Date()
    }
}
