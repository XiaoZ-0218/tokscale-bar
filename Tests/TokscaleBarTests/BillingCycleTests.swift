import XCTest
@testable import TokscaleBar

final class BillingCycleTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Dates.calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// now 在本月账单日之前 → 周期从上个月开始。
    func testNowBeforeBillingDayStartsLastMonth() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 3))
        XCTAssertEqual(cycle.start, date(2026, 8, 15))
        XCTAssertEqual(cycle.end, date(2026, 9, 15))
    }

    /// 账单日当天 → 新周期今天开始。
    func testOnBillingDayStartsToday() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 15))
        XCTAssertEqual(cycle.start, date(2026, 9, 15))
        XCTAssertEqual(cycle.end, date(2026, 10, 15))
    }

    func testAfterBillingDayRunsToNextMonth() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 20))
        XCTAssertEqual(cycle.start, date(2026, 9, 15))
        XCTAssertEqual(cycle.end, date(2026, 10, 15))
    }

    /// 31 号账单日在 30 天的月份 clamp 到月末。
    func testBillingDay31ClampsToShortMonth() {
        let cycle = Billing.currentCycle(billingDay: 31, now: date(2026, 9, 20))
        XCTAssertEqual(cycle.start, date(2026, 8, 31))
        XCTAssertEqual(cycle.end, date(2026, 9, 30))
    }

    /// 2 月 clamp 到 28；且下月（3 月）恢复 31。
    func testFebruaryClampThenMarchRestores31() {
        let feb = Billing.currentCycle(billingDay: 31, now: date(2026, 2, 10))
        XCTAssertEqual(feb.start, date(2026, 1, 31))
        XCTAssertEqual(feb.end, date(2026, 2, 28))

        let mar = Billing.currentCycle(billingDay: 31, now: date(2026, 3, 15))
        XCTAssertEqual(mar.start, date(2026, 2, 28))
        XCTAssertEqual(mar.end, date(2026, 3, 31))
    }

    /// 3/31 当天的周期终点是 4/30。
    func testMarch31CycleEndsApril30() {
        let cycle = Billing.currentCycle(billingDay: 31, now: date(2026, 3, 31))
        XCTAssertEqual(cycle.start, date(2026, 3, 31))
        XCTAssertEqual(cycle.end, date(2026, 4, 30))
    }

    /// 跨年：1 月初的周期从上一年 12 月开始。
    func testYearBoundary() {
        let cycle = Billing.currentCycle(billingDay: 10, now: date(2026, 1, 5))
        XCTAssertEqual(cycle.start, date(2025, 12, 10))
        XCTAssertEqual(cycle.end, date(2026, 1, 10))
    }

    /// 越界账单日 clamp 到 1...31。
    func testOutOfRangeBillingDayClamps() {
        let low = Billing.currentCycle(billingDay: 0, now: date(2026, 9, 20))
        XCTAssertEqual(low.start, date(2026, 9, 1))
        XCTAssertEqual(low.end, date(2026, 10, 1))

        let high = Billing.currentCycle(billingDay: 45, now: date(2026, 9, 20))
        XCTAssertEqual(high.start, date(2026, 8, 31))
        XCTAssertEqual(high.end, date(2026, 9, 30))
    }
}
