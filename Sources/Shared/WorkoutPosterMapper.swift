import Foundation

/// 运动大类（从 WorkoutDashboardView 抽出，iPhone / Watch 共用）
enum WorkoutActivityKind {
    case climbing
    case walking
    case running
    case yoga
    case cycling
    case swimming
    case strength
    case flexibility
    case dance
    case ballSports
    case cardio
    case other
}

/// 运动类型 → 插图 asset 名映射（iPhone dashboard 与 Watch 庆祝共用）
enum WorkoutPosterMapper {
    static func kind(key: String, name: String) -> WorkoutActivityKind {
        let key = key.lowercased()
        let text = "\(key) \(name)".lowercased()

        switch key {
        case "climbing":
            return .climbing
        case "walking", "hiking":
            return .walking
        case "running", "track_and_field", "wheelchair_run_pace":
            return .running
        case "yoga", "mind_and_body", "pilates", "tai_chi", "barre":
            return .yoga
        case "cycling", "hand_cycling", "swim_bike_run":
            return .cycling
        case "swimming", "water_fitness", "water_sports", "water_polo", "underwater_diving":
            return .swimming
        case "functional_strength_training", "traditional_strength_training", "core_training":
            return .strength
        case "flexibility", "preparation_and_recovery", "cooldown":
            return .flexibility
        case "dance", "dance_inspired_training", "cardio_dance", "social_dance":
            return .dance
        case "badminton", "baseball", "basketball", "cricket", "golf", "handball", "hockey", "lacrosse", "paddle_sports", "pickleball", "racquetball", "rugby", "soccer", "softball", "squash", "table_tennis", "tennis", "volleyball":
            return .ballSports
        case "cross_training", "elliptical", "high_intensity_interval_training", "jump_rope", "mixed_cardio", "mixed_metabolic_cardio_training", "stair_climbing", "stairs", "step_training":
            return .cardio
        default:
            break
        }

        if text.contains("攀岩") || text.contains("climb") { return .climbing }
        if text.contains("步行") || text.contains("散步") || text.contains("徒步") || text.contains("walk") || text.contains("hik") { return .walking }
        if text.contains("跑") || text.contains("run") { return .running }
        if text.contains("瑜伽") || text.contains("身心") || text.contains("普拉提") || text.contains("太极") || text.contains("yoga") || text.contains("pilates") { return .yoga }
        if text.contains("骑") || text.contains("cycling") || text.contains("bike") { return .cycling }
        if text.contains("游泳") || text.contains("水") || text.contains("swim") { return .swimming }
        if text.contains("力量") || text.contains("核心") || text.contains("strength") { return .strength }
        if text.contains("拉伸") || text.contains("柔韧") || text.contains("stretch") || text.contains("flexibility") { return .flexibility }
        if text.contains("舞") || text.contains("dance") { return .dance }
        if text.contains("球") || text.contains("ball") || text.contains("tennis") { return .ballSports }
        if text.contains("有氧") || text.contains("hiit") || text.contains("cardio") { return .cardio }
        return .other
    }

    /// 优先按具体运动 key 匹配对应配图，其次按运动大类匹配；没有的返回 nil（iPhone 端走自绘插画兜底）。
    static func posterAssetName(kind: WorkoutActivityKind, key: String?) -> String? {
        switch key?.lowercased() {
        case "tennis", "table_tennis":
            return "WorkoutPosterTennis"
        case "basketball":
            return "WorkoutPosterBasketball"
        case "badminton":
            return "WorkoutPosterBadminton"
        case "pickleball":
            return "WorkoutPosterPickleball"
        case "hiking":
            return "WorkoutPosterHiking"
        case "mind_and_body":
            return "WorkoutPosterMeditation"
        case "barre":
            return "WorkoutPosterBarre"
        case "surfing_sports":
            return "WorkoutPosterSurfing"
        case "underwater_diving":
            return "WorkoutPosterDiving"
        default:
            break
        }

        switch kind {
        case .climbing:
            return "WorkoutPosterBouldering"
        case .walking:
            return "WorkoutPosterWalk"
        case .running:
            return "WorkoutPosterRunning"
        case .ballSports:
            return "WorkoutPosterTennis"
        case .yoga:
            return "WorkoutPosterYoga"
        case .strength:
            return "WorkoutPosterStrength"
        case .cycling:
            return "WorkoutPosterCycling"
        case .swimming:
            return "WorkoutPosterSwimming"
        default:
            return nil
        }
    }

    /// 庆祝页必须出图：未覆盖类型用 park 兜底（spec §2.3）
    static func celebrationAssetName(key: String, name: String) -> String {
        posterAssetName(kind: self.kind(key: key, name: name), key: key) ?? "WorkoutPosterPark"
    }
}
