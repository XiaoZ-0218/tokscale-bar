import XCTest
@testable import TokscaleBar

final class MockCycleReportTests: XCTestCase {
    /// Mock 数据必须覆盖每个 mock 订阅的当前周期窗口，预览才不空窗。
    func testCycleReportsCoverEveryMockSubscription() {
        let now = Date()
        let reports = Mock.cycleReports(for: Mock.subscriptions)
        for sub in Mock.subscriptions {
            let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
            let key = CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
            XCTAssertNotNil(reports[key], "missing cycle report for \(sub.name)")
        }
    }

    /// Mock 订阅要覆盖 ≥1 倍和 <1 倍两种状态（绿色/橙色徽章都能看到）。
    func testMockSubscriptionsShowBothSidesOfBreakeven() {
        let now = Date()
        let reports = Mock.cycleReports(for: Mock.subscriptions)
        let multiples = Mock.subscriptions.map { sub -> Double in
            let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
            let key = CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
            let cost = ROI.matchedCost(reports[key]?.entries ?? [], keywords: sub.keywords)
            return ROI.multiple(costUSD: cost, price: sub.price, currency: sub.currency,
                                rate: Defaults.usdToCnyRate)
        }
        XCTAssertTrue(multiples.contains { $0 >= 1 }, "need a paid-off mock: \(multiples)")
        XCTAssertTrue(multiples.contains { $0 > 0 && $0 < 1 }, "need a not-yet mock: \(multiples)")
    }
}
