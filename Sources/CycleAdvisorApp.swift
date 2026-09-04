import SwiftUI

@main
struct CycleAdvisorApp: App {

    init() {
        UserDefaults.standard.register(defaults: ["thinkingMode": ThinkingMode.fast.rawValue])
        // 一次性迁移:清掉旧版默认昵称「Lufi」,之后用户设置的名字(包括 Lufi)正常保留。
        DisplayName.migrateLegacyDefaultIfNeeded()
        // 语言完全跟随系统(iOS 13+ per-app 语言在系统设置里改)。
        // 旧版 App 内切换器会同时写 appLanguagePreference 和 AppleLanguages 两个 key;
        // 而系统的 per-app 语言设置只写 AppleLanguages——所以只有发现遗留的
        // appLanguagePreference 时才连 AppleLanguages 一起清,否则它是系统管的,不能碰
        // (无条件删除会把用户在系统设置里的 per-app 语言抹掉,回落到系统大语言)。
        if UserDefaults.standard.object(forKey: "appLanguagePreference") != nil {
            UserDefaults.standard.removeObject(forKey: "appLanguagePreference")
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                // App 的视觉设计(暖羊皮纸主题、Theme.background/cardBackground 等)只针对浅色模式做过适配,
                // 让系统级 List / NavigationStack / Toolbar 跟着暗色走会出现"侧边栏一到晚上就变黑"这种割裂感,
                // 这里统一锁定浅色模式。如果未来要做夜间模式,再换成 .auto 并补齐 Theme 的深色变体即可。
                .preferredColorScheme(.light)
        }
    }
}
