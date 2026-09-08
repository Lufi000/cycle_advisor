import XCTest
@testable import CycleAdvisor

/// 备孕模式开关：默认关闭；旧版 JSON（无该字段）解码兼容
final class UserProfileConceptionTests: XCTestCase {

    /// 默认关闭
    func testDefaultIsFalse() {
        XCTAssertFalse(UserProfile.empty.isTryingToConceive)
    }

    /// 旧版档案 JSON（无 isTryingToConceive 字段）解码不丢数据、默认 false
    func testLegacyJSONDecodesWithDefaultFalse() throws {
        let legacyJSON = """
        {
          "bodyInfo": {},
          "accumulatedStats": {
            "cycleLengths": [28, 29],
            "periodDurations": [5],
            "flowPatternByDay": {},
            "symptomFrequencies": {},
            "cyclesRecorded": 2,
            "version": 0
          },
          "workoutStats": {
            "topActivities": [],
            "weeklyFrequency": 0,
            "avgDurationMinutes": 0
          },
          "lifestyle": {
            "dietaryPreferences": [],
            "knownSensitivities": []
          },
          "knownConditions": [],
          "lastUpdated": 700000000,
          "version": 1
        }
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(profile.isTryingToConceive)
        XCTAssertEqual(profile.accumulatedStats.cycleLengths, [28, 29])
    }

    /// 开启后编码往返保留
    func testRoundTripPreservesFlag() throws {
        var profile = UserProfile.empty
        profile.isTryingToConceive = true
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertTrue(decoded.isTryingToConceive)
    }
}
