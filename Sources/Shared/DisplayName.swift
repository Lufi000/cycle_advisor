import Foundation

/// 用户昵称统一处理：空字符串视为未设置，界面据此显示无昵称的问候语。
enum DisplayName {
    /// 旧版本硬编码的默认昵称；历史安装可能已把它写入 UserDefaults。
    static let legacyFallback = "Lufi"
    /// UserDefaults 标记：旧的默认值迁移是否已完成。
    private static let migrationKey = "displayName.legacyMigrated"

    /// 归一化昵称：去除首尾空白。用户设置的任何名字（包括 Lufi）都会保留。
    static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 一次性迁移：只把「从未设置过、由旧版默认值写入的 Lufi」清掉；
    /// 迁移完成后，用户之后设置的任何名字都会正常保留和显示。
    static func migrateLegacyDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        if defaults.string(forKey: "displayName") == legacyFallback {
            defaults.removeObject(forKey: "displayName")
        }
        defaults.set(true, forKey: migrationKey)
    }
}
