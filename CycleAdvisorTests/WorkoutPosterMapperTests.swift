import XCTest
@testable import CycleAdvisor

/// 运动类型 → 插图映射：具体 key 优先，其次运动大类，庆祝场景必须有图（park 兜底）
final class WorkoutPosterMapperTests: XCTestCase {

    func testSpecificKeyWins() {
        // table_tennis 属于 ballSports 大类，但有专属网球插图时按 key 走
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .ballSports, key: "badminton"), "WorkoutPosterBadminton")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .ballSports, key: "pickleball"), "WorkoutPosterPickleball")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .yoga, key: "barre"), "WorkoutPosterBarre")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: "surfing_sports"), "WorkoutPosterSurfing")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: "underwater_diving"), "WorkoutPosterDiving")
    }

    func testKindFallback() {
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .running, key: nil), "WorkoutPosterRunning")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .walking, key: nil), "WorkoutPosterWalk")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .climbing, key: nil), "WorkoutPosterBouldering")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .yoga, key: nil), "WorkoutPosterYoga")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .strength, key: nil), "WorkoutPosterStrength")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .cycling, key: nil), "WorkoutPosterCycling")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: nil), "WorkoutPosterSwimming")
        // 无专属图的大类返回 nil（iPhone 端走自绘插画兜底）
        XCTAssertNil(WorkoutPosterMapper.posterAssetName(kind: .cardio, key: nil))
        XCTAssertNil(WorkoutPosterMapper.posterAssetName(kind: .other, key: nil))
    }

    func testKindInference() {
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "hiking", name: "徒步"), .walking)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "mind_and_body", name: "身心"), .yoga)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "table_tennis", name: "乒乓球"), .ballSports)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "jump_rope", name: "跳绳"), .cardio)
        // 未知 key 走名称关键词
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "unknown_999", name: "攀岩"), .climbing)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "unknown_998", name: "Frisbee"), .other)
    }

    func testCelebrationAlwaysHasPoster() {
        XCTAssertEqual(WorkoutPosterMapper.celebrationAssetName(key: "running", name: "跑步"), "WorkoutPosterRunning")
        // 未覆盖类型兜底 park
        XCTAssertEqual(WorkoutPosterMapper.celebrationAssetName(key: "unknown_999", name: "Frisbee"), "WorkoutPosterPark")
    }

    func testWorkoutKeyFromActivityType() {
        XCTAssertEqual(HealthKitManager.workoutKey(for: .running), "running")
        XCTAssertEqual(HealthKitManager.workoutKey(for: .badminton), "badminton")
        XCTAssertEqual(HealthKitManager.workoutKey(for: .tableTennis), "table_tennis")
    }
}
