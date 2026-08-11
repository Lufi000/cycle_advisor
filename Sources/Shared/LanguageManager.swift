import Foundation
import SwiftUI
import ObjectiveC

/// 应用内语言切换支持。
///
/// 默认情况下 SwiftUI 与 `String(localized:)` 都走 `Bundle.main` 查表，
/// 这里通过把 `Bundle.main` 替换成一个会按用户偏好查 lproj 的子类，
/// 实现「无需重启即可切换语言」。
///
/// 触发刷新有两条路径：
///  1. 视图层把 `LanguageManager.shared.refreshTrigger` 接到根视图的 `.id(...)`，
///     语言改变时会重建视图树，让所有 `Text("key")` 重新查表。
///  2. 在根视图设置 `.environment(\.locale, ...)`，让日期/数字等系统格式化也跟着变。
@Observable
final class LanguageManager {

    static let shared = LanguageManager()

    /// 支持的应用语言。`system` 表示跟随系统。
    enum AppLanguage: String, CaseIterable, Identifiable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        var id: String { rawValue }

        /// 用于在 Picker 中展示的本地化标题。
        var displayName: String {
            switch self {
            case .system: return String(localized: "settings.language.system")
            case .english: return String(localized: "settings.language.english")
            case .simplifiedChinese: return String(localized: "settings.language.chinese")
            }
        }

        /// 对应的 lproj 资源名。`nil` 时表示跟随系统。
        var resourceCode: String? {
            switch self {
            case .system: return nil
            case .english: return "en"
            case .simplifiedChinese: return "zh-Hans"
            }
        }
    }

    private static let storageKey = "appLanguagePreference"

    /// 当前生效的语言偏好。改变时会立即触发界面刷新。
    var current: AppLanguage {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
            // 同步给系统一份，确保下次冷启动时 Apple 的本地化体系也能挑到正确的 lproj。
            if let code = current.resourceCode {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            refreshTrigger = UUID()
        }
    }

    /// 让根视图通过 `.id(refreshTrigger)` 监听切换；每次切换都会重建视图树，
    /// 从而让所有 `Text("key")` / `String(localized:)` 重新走 Bundle 查表。
    private(set) var refreshTrigger: UUID = UUID()

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            self.current = stored
        } else {
            self.current = .system
        }
    }

    /// 当前应该使用的 `Locale`（数字、日期等格式化会跟着这个走）。
    var effectiveLocale: Locale {
        if let code = current.resourceCode {
            return Locale(identifier: code)
        }
        // 跟随系统
        return Locale.current
    }

    /// 解析当前要使用的 lproj Bundle；找不到时回退到 main bundle。
    func resolvedBundle() -> Bundle {
        guard
            let code = current.resourceCode,
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return Bundle.main
        }
        return bundle
    }

    /// 在 App 启动时调用一次。把 `Bundle.main` 偷偷换成 `RuntimeLocalizedBundle`，
    /// 这样任何 `String(localized:)` / `Text("key")` / `NSLocalizedString` 都会通过我们重写的方法查表。
    static func installRuntimeLocalizationOverride() {
        guard object_getClass(Bundle.main) != RuntimeLocalizedBundle.self else { return }
        object_setClass(Bundle.main, RuntimeLocalizedBundle.self)
    }
}

/// 替换 `Bundle.main` 的子类。所有 `localizedString(forKey:value:table:)` 调用都先去用户选定的 lproj 查表，
/// 没命中再回退到原始资源。
///
/// `Bundle` 在 SDK 里被标注成 `@unchecked Sendable`，按 Swift 的规则，子类需要显式
/// 重新声明这一致性，否则会出现 "must restate inherited '@unchecked Sendable' conformance" 警告。
final class RuntimeLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let bundle = LanguageManager.shared.resolvedBundle()
        if bundle !== self {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
