import XCTest
@testable import TokscaleBar

final class ROITests: XCTestCase {
    private func entry(_ client: String, _ model: String, _ cost: Double) -> Report.Entry {
        Report.Entry(client: client, model: model, input: 0, output: 0,
                     cacheRead: 0, cacheWrite: 0, reasoning: nil,
                     cost: cost, messageCount: 0)
    }

    private var entries: [Report.Entry] {
        [
            entry("zcode", "claude-opus-4.6", 71.30),
            entry("grok", "grok-4.6", 63.80),
            entry("zcode", "grok-4.6", 43.12),
            entry("codex", "k3-256k", 7.41),
        ]
    }

    func testKeywordMatchesModelNameCaseInsensitive() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["CLAUDE"]), 71.30, accuracy: 1e-9)
    }

    func testKeywordMatchesClientName() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["grok"]), 63.80 + 43.12, accuracy: 1e-9)
    }

    func testMultipleKeywordsUnion() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["claude", "k3"]), 71.30 + 7.41, accuracy: 1e-9)
    }

    /// 空白关键词被忽略；全部为空 = 匹配所有 entry。
    func testEmptyKeywordsMatchEverything() {
        let total = entries.reduce(0) { $0 + $1.cost }
        XCTAssertEqual(ROI.matchedCost(entries, keywords: []), total, accuracy: 1e-9)
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["  ", ""]), total, accuracy: 1e-9)
    }

    func testNoMatchIsZero() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["llama"]), 0)
    }

    func testMultipleUSD() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 20, currency: .usd, rate: 7.2), 2.4, accuracy: 1e-9)
    }

    /// CNY 价格先按汇率折成 USD 再算倍数：¥144 / 7.2 = $20。
    func testMultipleCNY() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 144, currency: .cny, rate: 7.2), 2.4, accuracy: 1e-9)
    }

    /// 价格为 0 或负不产生除零/负倍数。
    func testMultipleZeroPriceIsZero() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 0, currency: .usd, rate: 7.2), 0)
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: -5, currency: .usd, rate: 7.2), 0)
    }
}
