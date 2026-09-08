import XCTest
@testable import CycleAdvisor

/// 聊天症状抽取的响应解析：正常 JSON / 空数组 / 畸形 JSON / 未知类型过滤
final class SymptomExtractorTests: XCTestCase {

    /// 正常 JSON 解析
    func testParsesValidResponse() {
        let content = """
        {"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "fatigue", "date_ref": "yesterday"}]}
        """
        let result = LLMService.parseExtractedSymptoms(from: content)
        XCTAssertEqual(result, [
            ExtractedSymptom(type: .nausea, dateRef: "today"),
            ExtractedSymptom(type: .fatigue, dateRef: "yesterday"),
        ])
    }

    /// 空数组
    func testParsesEmptyArray() {
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: #"{"symptoms": []}"#), [])
    }

    /// 畸形 JSON → 空数组（不抛错）
    func testMalformedJSONYieldsEmpty() {
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: "not json at all"), [])
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: #"{"symptoms": "nope"}"#), [])
    }

    /// markdown 围栏与 think 块被清理
    func testCleansMarkdownFence() {
        let content = "```json\n{\"symptoms\": [{\"type\": \"headache\", \"date_ref\": null}]}\n```"
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: content),
                       [ExtractedSymptom(type: .headache, dateRef: nil)])
    }

    /// 未知症状类型被过滤，合法条目保留
    func testUnknownTypesFiltered() {
        let content = """
        {"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "teleportation", "date_ref": null}]}
        """
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: content),
                       [ExtractedSymptom(type: .nausea, dateRef: "today")])
    }

    /// date_ref 映射：yesterday → 昨天；today/null → 今天；来源固定 chatExtracted
    func testDateRefMapping() {
        let now = Date()
        let today = ExtractedSymptom(type: .nausea, dateRef: "today").record(now: now)
        let yesterday = ExtractedSymptom(type: .nausea, dateRef: "yesterday").record(now: now)
        let nullRef = ExtractedSymptom(type: .nausea, dateRef: nil).record(now: now)

        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInToday(today.date))
        XCTAssertTrue(calendar.isDateInYesterday(yesterday.date))
        XCTAssertTrue(calendar.isDateInToday(nullRef.date))
        XCTAssertEqual(today.source, .chatExtracted)
    }
}
