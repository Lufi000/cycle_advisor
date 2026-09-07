import Foundation

/// 待触发的运动庆祝（spec §2.3）
struct PendingCelebration: Codable, Equatable {
    let workoutUUID: UUID
    let activityKey: String
    let posterAssetName: String
    let fireDate: Date

    var notificationID: String { "workout.celebration.\(workoutUUID.uuidString)" }
}

/// 庆祝计划器：纯逻辑，可单测。watchOS 触发流程见 Task 9。
enum WorkoutCelebrationPlanner {
    /// 与 Apple 体能训练总结页错开的固定延迟
    static let delay: TimeInterval = 60

    /// 返回 nil 表示该 workout 已庆祝过，不再重复
    static func plan(workoutUUID: UUID, activityKey: String, activityName: String,
                     workoutEnd: Date, now: Date, celebratedUUIDs: Set<UUID>) -> PendingCelebration? {
        guard !celebratedUUIDs.contains(workoutUUID) else { return nil }
        return PendingCelebration(
            workoutUUID: workoutUUID,
            activityKey: activityKey,
            posterAssetName: WorkoutPosterMapper.celebrationAssetName(key: activityKey, name: activityName),
            fireDate: max(workoutEnd, now) + delay
        )
    }
}
