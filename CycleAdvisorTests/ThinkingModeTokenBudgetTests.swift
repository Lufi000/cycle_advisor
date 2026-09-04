import XCTest
@testable import CycleAdvisor

/// 回归测试：DeepSeek 推理模型（deepseek-reasoner）把思考内容和正式回答
/// 合并计入 max_tokens。深度模式若沿用 800 上限，思考会耗尽额度，
/// 导致正式回答为空（finish_reason="length"），用户看到"AI 未返回内容"。
final class ThinkingModeTokenBudgetTests: XCTestCase {

    func testDeepModeHasHeadroomForReasoningTokens() {
        XCTAssertEqual(ThinkingMode.fast.chatMaxTokens, 800)
        // 深度模式额度必须显著大于快速模式：回答本体之外要给推理留空间
        XCTAssertGreaterThanOrEqual(ThinkingMode.deep.chatMaxTokens, ThinkingMode.fast.chatMaxTokens * 4)
    }
}
