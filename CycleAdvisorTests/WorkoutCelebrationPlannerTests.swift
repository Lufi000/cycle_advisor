import XCTest
@testable import CycleAdvisor

/// 庆祝计划（spec §2.3）：延迟 1 分钟、同一 workout 只庆祝一次、窗口内多次完成只留最后一次
final class WorkoutCelebrationPlannerTests: XCTestCase {

    func testFireDateIsOneMinuteAfterEnd() {
        let end = Date()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: UUID(), activityKey: "running", activityName: "跑步",
            workoutEnd: end, now: end, celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.fireDate.timeIntervalSince(end) ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(plan?.posterAssetName, "WorkoutPosterRunning")
    }

    func testDuplicateWorkoutNotCelebrated() {
        let uuid = UUID()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: uuid, activityKey: "yoga", activityName: "瑜伽",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: [uuid]
        )
        XCTAssertNil(plan)
    }

    func testUnknownActivityFallsBackToPark() {
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: UUID(), activityKey: "unknown_999", activityName: "Frisbee",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.posterAssetName, "WorkoutPosterPark")
    }

    func testNotificationIDContainsUUID() {
        let uuid = UUID()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: uuid, activityKey: "running", activityName: "跑步",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.notificationID, "workout.celebration.\(uuid.uuidString)")
    }
}
