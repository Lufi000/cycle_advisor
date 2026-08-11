import SwiftUI

@main
struct CycleAdvisorApp: App {
    /// 用户在设置里切换语言时，通过这个观察对象重建视图树。
    private let languageManager = LanguageManager.shared

    init() {
        UserDefaults.standard.register(defaults: ["thinkingMode": ThinkingMode.fast.rawValue])
        // 安装 Bundle 子类，使得 String(localized:) / Text("key") 都能跟随应用内语言设置。
        LanguageManager.installRuntimeLocalizationOverride()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                // 切换语言时，refreshTrigger 变化会让 .id() 重建视图树，所有本地化文案重新查表。
                .id(languageManager.refreshTrigger)
                // 让日期、数字等系统格式化也跟着应用内语言走。
                .environment(\.locale, languageManager.effectiveLocale)
                // App 的视觉设计（暖羊皮纸主题、Theme.background/cardBackground 等）只针对浅色模式做过适配，
                // 让系统级 List / NavigationStack / Toolbar 跟着暗色走会出现"侧边栏一到晚上就变黑"这种割裂感，
                // 这里统一锁定浅色模式。如果未来要做夜间模式，再换成 .auto 并补齐 Theme 的深色变体即可。
                .preferredColorScheme(.light)
        }
    }
}
