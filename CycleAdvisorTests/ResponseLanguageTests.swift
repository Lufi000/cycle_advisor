import XCTest
@testable import CycleAdvisor

/// 回归测试：法/西等拉丁字母语言曾一律被脚本统计法判成英文，
/// 导致用户用法语打招呼、AI 却用英文回复。
/// 拉丁文字无法靠字符区间区分语种，必须用语义级语言识别。
final class ResponseLanguageTests: XCTestCase {

    typealias Lang = LLMService.ResponseLanguage

    private func detect(_ text: String, fallback: Lang = .english) -> Lang {
        LLMService.responseLanguage(for: text, fallback: fallback)
    }

    // MARK: - 拉丁字母语言要区分语种

    func testFrenchGreetingDetectedAsFrench() {
        XCTAssertEqual(detect("Bonjour ! Comment allez-vous aujourd'hui ?"), .french)
    }

    func testSpanishQuestionDetectedAsSpanish() {
        XCTAssertEqual(detect("¿Cómo estás? ¿Qué deporte me recomiendas para hoy?"), .spanish)
    }

    func testEnglishQuestionDetectedAsEnglish() {
        XCTAssertEqual(detect("How should I adjust my training plan today?"), .english)
    }

    // MARK: - 不支持的拉丁语种回退系统偏好语言

    func testUnsupportedLatinLanguageFallsBack() {
        XCTAssertEqual(detect("Guten Tag, wie geht es Ihnen heute?", fallback: .french), .french)
    }

    // MARK: - 原有行为不变

    func testAmbiguousEnglishGreetingUsesFallback() {
        XCTAssertEqual(detect("hello", fallback: .simplifiedChinese), .simplifiedChinese)
    }

    func testJapaneseDetectedByKana() {
        XCTAssertEqual(detect("今日はどんな運動がおすすめですか？"), .japanese)
    }

    func testKoreanDetectedByHangul() {
        XCTAssertEqual(detect("오늘 어떤 운동을 추천해줄 수 있나요?"), .korean)
    }

    func testChineseDetectedByCJK() {
        XCTAssertEqual(detect("今天适合做什么运动？"), .simplifiedChinese)
    }
}
