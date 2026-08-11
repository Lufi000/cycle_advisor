import Foundation
import SwiftUI

// MARK: - Solar Term (节气)

/// 24 节气，rawValue 为对应的太阳黄经度数
enum SolarTerm: Int, CaseIterable, Codable, Identifiable {
    // 春
    case lichun    = 315  // 立春
    case yushui    = 330  // 雨水
    case jingzhe   = 345  // 惊蛰
    case chunfen   = 0    // 春分
    case qingming  = 15   // 清明
    case guyu      = 30   // 谷雨
    // 夏
    case lixia     = 45   // 立夏
    case xiaoman   = 60   // 小满
    case mangzhong = 75   // 芒种
    case xiazhi    = 90   // 夏至
    case xiaoshu   = 105  // 小暑
    case dashu     = 120  // 大暑
    // 秋
    case liqiu     = 135  // 立秋
    case chushu    = 150  // 处暑
    case bailu     = 165  // 白露
    case qiufen    = 180  // 秋分
    case hanlu     = 195  // 寒露
    case shuangjang = 210 // 霜降
    // 冬
    case lidong    = 225  // 立冬
    case xiaoxue   = 240  // 小雪
    case daxue     = 255  // 大雪
    case dongzhi   = 270  // 冬至
    case xiaohan   = 285  // 小寒
    case dahan     = 300  // 大寒

    var id: Int { rawValue }

    /// 太阳黄经度数
    var longitude: Double { Double(rawValue) }

    /// 本地化显示名
    var displayName: String {
        NSLocalizedString("solar.\(key)", comment: "")
    }

    /// 气候描述
    var climateSummary: String {
        NSLocalizedString("solar.\(key).climate", comment: "")
    }

    /// 养生建议
    var wellnessTip: String {
        NSLocalizedString("solar.\(key).wellness", comment: "")
    }

    /// 本地化 key
    var key: String {
        switch self {
        case .lichun:    return "lichun"
        case .yushui:    return "yushui"
        case .jingzhe:   return "jingzhe"
        case .chunfen:   return "chunfen"
        case .qingming:  return "qingming"
        case .guyu:      return "guyu"
        case .lixia:     return "lixia"
        case .xiaoman:   return "xiaoman"
        case .mangzhong: return "mangzhong"
        case .xiazhi:    return "xiazhi"
        case .xiaoshu:   return "xiaoshu"
        case .dashu:     return "dashu"
        case .liqiu:     return "liqiu"
        case .chushu:    return "chushu"
        case .bailu:     return "bailu"
        case .qiufen:    return "qiufen"
        case .hanlu:     return "hanlu"
        case .shuangjang: return "shuangjang"
        case .lidong:    return "lidong"
        case .xiaoxue:   return "xiaoxue"
        case .daxue:     return "daxue"
        case .dongzhi:   return "dongzhi"
        case .xiaohan:   return "xiaohan"
        case .dahan:     return "dahan"
        }
    }

    var emoji: String {
        switch self {
        case .lichun:    return "🌱"
        case .yushui:    return "🌧️"
        case .jingzhe:   return "⛈️"
        case .chunfen:   return "🌸"
        case .qingming:  return "🍃"
        case .guyu:      return "🌾"
        case .lixia:     return "☀️"
        case .xiaoman:   return "🌿"
        case .mangzhong: return "🌾"
        case .xiazhi:    return "🔆"
        case .xiaoshu:   return "🌡️"
        case .dashu:     return "🥵"
        case .liqiu:     return "🍂"
        case .chushu:    return "🌅"
        case .bailu:     return "💧"
        case .qiufen:    return "🍁"
        case .hanlu:     return "🥶"
        case .shuangjang: return "❄️"
        case .lidong:    return "🧣"
        case .xiaoxue:   return "🌨️"
        case .daxue:     return "❄️"
        case .dongzhi:   return "🏔️"
        case .xiaohan:   return "🥶"
        case .dahan:     return "🧊"
        }
    }

    var assetName: String {
        switch self {
        case .lichun:    return "SolarTerm_lichun"
        case .yushui:    return "SolarTerm_yushui"
        case .jingzhe:   return "SolarTerm_jingzhe"
        case .chunfen:   return "SolarTerm_chunfen"
        case .qingming:  return "SolarTerm_qingming"
        case .guyu:      return "SolarTerm_guyu"
        case .lixia:     return "SolarTerm_lixia"
        case .xiaoman:   return "SolarTerm_xiaoman"
        case .mangzhong: return "SolarTerm_mangzhong"
        case .xiazhi:    return "SolarTerm_xiazhi"
        case .xiaoshu:   return "SolarTerm_xiaoshu"
        case .dashu:     return "SolarTerm_dashu"
        case .liqiu:     return "SolarTerm_liqiu"
        case .chushu:    return "SolarTerm_chushu"
        case .bailu:     return "SolarTerm_bailu"
        case .qiufen:    return "SolarTerm_qiufen"
        case .hanlu:     return "SolarTerm_hanlu"
        case .shuangjang: return "SolarTerm_shuangjiang"
        case .lidong:    return "SolarTerm_lidong"
        case .xiaoxue:   return "SolarTerm_xiaoxue"
        case .daxue:     return "SolarTerm_daxue"
        case .dongzhi:   return "SolarTerm_dongzhi"
        case .xiaohan:   return "SolarTerm_xiaohan"
        case .dahan:     return "SolarTerm_dahan"
        }
    }

    /// 所属季节
    var season: Season {
        switch self {
        case .lichun, .yushui, .jingzhe, .chunfen, .qingming, .guyu:
            return .spring
        case .lixia, .xiaoman, .mangzhong, .xiazhi, .xiaoshu, .dashu:
            return .summer
        case .liqiu, .chushu, .bailu, .qiufen, .hanlu, .shuangjang:
            return .autumn
        case .lidong, .xiaoxue, .daxue, .dongzhi, .xiaohan, .dahan:
            return .winter
        }
    }

    /// 按立春起的年序排列
    static let calendarOrder: [SolarTerm] = [
        .lichun, .yushui, .jingzhe, .chunfen, .qingming, .guyu,
        .lixia, .xiaoman, .mangzhong, .xiazhi, .xiaoshu, .dashu,
        .liqiu, .chushu, .bailu, .qiufen, .hanlu, .shuangjang,
        .lidong, .xiaoxue, .daxue, .dongzhi, .xiaohan, .dahan
    ]
}

// MARK: - Season (季节)

enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    var displayName: String {
        NSLocalizedString("season.\(rawValue)", comment: "")
    }

    var color: Color {
        switch self {
        case .spring: return Theme.phaseFollicular
        case .summer: return Theme.phaseOvulation
        case .autumn: return Theme.phaseLuteal
        case .winter: return Theme.phaseMenstrual
        }
    }
}

// MARK: - Solar Term Info (某年某节气的具体日期)

struct SolarTermInfo: Identifiable, Equatable {
    let id: String
    let term: SolarTerm
    let date: Date
    let year: Int

    init(term: SolarTerm, date: Date, year: Int) {
        self.id = "\(term.key)-\(year)"
        self.term = term
        self.date = date
        self.year = year
    }
}
