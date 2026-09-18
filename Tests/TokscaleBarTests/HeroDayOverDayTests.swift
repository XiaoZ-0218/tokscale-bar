import XCTest
@testable import TokscaleBar

final class HeroDayOverDayTests: XCTestCase {
    private func day(_ date: String, tokens: Int = 0, cost: Double = 0) -> DayUsage {
        DayUsage(date: date, totals: .init(tokens: tokens, cost: cost, messages: 0))
    }

    func testFewerThanTwoDaysReturnsNil() {
        XCTAssertNil(TokscaleService.dayOverDay([], metric: .cost))
        XCTAssertNil(TokscaleService.dayOverDay([], metric: .tokens))

        let one = [day("2026-09-17", tokens: 100, cost: 1)]
        XCTAssertNil(TokscaleService.dayOverDay(one, metric: .cost))
        XCTAssertNil(TokscaleService.dayOverDay(one, metric: .tokens))
    }

    func testCostReturnsNilWhenYesterdayCostIsAtOrBelowThreshold() {
        let atThreshold = [
            day("2026-09-16", cost: 0.005),
            day("2026-09-17", cost: 1),
        ]
        XCTAssertNil(TokscaleService.dayOverDay(atThreshold, metric: .cost))

        let belowThreshold = [
            day("2026-09-16", cost: 0),
            day("2026-09-17", cost: 1),
        ]
        XCTAssertNil(TokscaleService.dayOverDay(belowThreshold, metric: .cost))
    }

    func testCostGrowsTenPercentWhenYesterdayIsOneAndTodayIsOnePointOne() {
        let week = [
            day("2026-09-15", cost: 99),
            day("2026-09-16", cost: 1),
            day("2026-09-17", cost: 1.1),
        ]
        let delta = TokscaleService.dayOverDay(week, metric: .cost)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!, 0.1, accuracy: 1e-9)
    }

    func testTokensReturnsNilWhenYesterdayTokensAreZero() {
        let week = [
            day("2026-09-16", tokens: 0),
            day("2026-09-17", tokens: 80),
        ]
        XCTAssertNil(TokscaleService.dayOverDay(week, metric: .tokens))
    }

    func testTokensDropsTwentyPercentWhenYesterdayIs100AndTodayIs80() {
        let week = [
            day("2026-09-15", tokens: 9_999),
            day("2026-09-16", tokens: 100),
            day("2026-09-17", tokens: 80),
        ]
        let delta = TokscaleService.dayOverDay(week, metric: .tokens)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!, -0.2, accuracy: 1e-9)
    }

    /// Token fields would yield -0.2; cost must still be +0.1.
    func testCostMetricIgnoresTokenFields() {
        let week = [
            day("2026-09-16", tokens: 100, cost: 1),
            day("2026-09-17", tokens: 80, cost: 1.1),
        ]
        let delta = TokscaleService.dayOverDay(week, metric: .cost)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!, 0.1, accuracy: 1e-9)
    }

    /// Cost fields would yield +0.1; tokens must still be -0.2.
    func testTokensMetricIgnoresCostFields() {
        let week = [
            day("2026-09-16", tokens: 100, cost: 1),
            day("2026-09-17", tokens: 80, cost: 1.1),
        ]
        let delta = TokscaleService.dayOverDay(week, metric: .tokens)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!, -0.2, accuracy: 1e-9)
    }
}
