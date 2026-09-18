import XCTest
@testable import TokscaleBar

final class HeroTitleTests: XCTestCase {
    func testCostTitlesMatchCurrentCopy() {
        let zh = L10n(language: .zh)
        let en = L10n(language: .en)
        XCTAssertEqual(zh.heroTitle(.today, metric: .cost), "今日花费")
        XCTAssertEqual(en.heroTitle(.today, metric: .cost), "Today's Spend")
        XCTAssertEqual(zh.heroTitle(.week, metric: .cost), "近 7 天花费")
        XCTAssertEqual(en.heroTitle(.week, metric: .cost), "Last 7 Days")
        XCTAssertEqual(zh.heroTitle(.last30, metric: .cost), "近 30 天花费")
        XCTAssertEqual(en.heroTitle(.last30, metric: .cost), "Last 30 Days")
        XCTAssertEqual(zh.heroTitle(.all, metric: .cost), "全部花费")
        XCTAssertEqual(en.heroTitle(.all, metric: .cost), "All Time")
    }

    func testTokenTitles() {
        let zh = L10n(language: .zh)
        let en = L10n(language: .en)
        XCTAssertEqual(zh.heroTitle(.today, metric: .tokens), "今日 Tokens")
        XCTAssertEqual(en.heroTitle(.today, metric: .tokens), "Today's Tokens")
        XCTAssertEqual(zh.heroTitle(.week, metric: .tokens), "近 7 天 Tokens")
        XCTAssertEqual(en.heroTitle(.week, metric: .tokens), "Last 7 Days Tokens")
        XCTAssertEqual(zh.heroTitle(.last30, metric: .tokens), "近 30 天 Tokens")
        XCTAssertEqual(en.heroTitle(.last30, metric: .tokens), "Last 30 Days Tokens")
        XCTAssertEqual(zh.heroTitle(.all, metric: .tokens), "全部 Tokens")
        XCTAssertEqual(en.heroTitle(.all, metric: .tokens), "All Time Tokens")
    }

    /// Existing one-argument call sites must keep the cost titles.
    func testDefaultMetricIsCost() {
        XCTAssertEqual(L10n(language: .zh).heroTitle(.today), "今日花费")
        XCTAssertEqual(L10n(language: .en).heroTitle(.today), "Today's Spend")
    }

    func testHeroShowsLabel() {
        XCTAssertEqual(L10n(language: .zh).heroShows, "主卡片显示")
        XCTAssertEqual(L10n(language: .en).heroShows, "Hero Shows")
    }
}
