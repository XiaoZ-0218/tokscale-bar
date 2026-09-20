import XCTest
@testable import TokscaleBar

final class UsageAccountDecodingTests: XCTestCase {
    func testDecodesRealTokscaleShape() throws {
        let json = """
        [
          {
            "provider": "Codex",
            "account": {"id": "abc", "is_active": true},
            "plan": "Free",
            "email": "a@b.com",
            "metrics": [
              {
                "label": "30d",
                "used_percent": 0.0,
                "remaining_percent": 100.0,
                "remaining_label": null,
                "resets_at": "2026-10-19T02:17:26+00:00"
              }
            ],
            "reset_credits": {"available_count": 0},
            "credit_status": {"has_credits": false, "unlimited": false, "overage_limit_reached": false},
            "spend_control": {"reached": false}
          }
        ]
        """
        let accounts = try JSONDecoder().decode([UsageAccount].self, from: Data(json.utf8))
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].provider, "Codex")
        XCTAssertEqual(accounts[0].plan, "Free")
        XCTAssertEqual(accounts[0].email, "a@b.com")
        XCTAssertEqual(accounts[0].metrics.count, 1)
        XCTAssertEqual(accounts[0].metrics[0].label, "30d")
        XCTAssertEqual(accounts[0].metrics[0].usedPercent, 0)
        XCTAssertEqual(accounts[0].metrics[0].remainingPercent, 100)
        XCTAssertNil(accounts[0].metrics[0].remainingLabel)
        XCTAssertEqual(accounts[0].metrics[0].resetsAt, "2026-10-19T02:17:26+00:00")
    }

    func testMissingOptionalFieldsStillDecode() throws {
        let json = """
        [{"provider":"Kimi","metrics":[{"label":"Weekly","used_percent":66.0,"remaining_percent":34.0}]}]
        """
        let accounts = try JSONDecoder().decode([UsageAccount].self, from: Data(json.utf8))
        XCTAssertNil(accounts[0].plan)
        XCTAssertNil(accounts[0].email)
        XCTAssertNil(accounts[0].metrics[0].remainingLabel)
        XCTAssertNil(accounts[0].metrics[0].resetsAt)
    }
}

final class UsagePrimaryMetricTests: XCTestCase {
    private func metric(_ label: String, used: Double, remaining: Double? = nil) -> UsageMetric {
        UsageMetric(label: label, usedPercent: used, remainingPercent: remaining ?? (100 - used),
                    remainingLabel: nil, resetsAt: nil)
    }

    func testPrefersWeeklyWhenPresent() {
        let account = UsageAccount(
            provider: "Kimi", plan: nil, email: nil,
            metrics: [metric("Session", used: 0), metric("Weekly", used: 66)]
        )
        XCTAssertEqual(account.primaryMetric?.label, "Weekly")
    }

    func testFallsBackToHighestUsedPercent() {
        let account = UsageAccount(
            provider: "Copilot", plan: "Individual", email: nil,
            metrics: [metric("Chat", used: 0), metric("Completions", used: 0.7), metric("Premium", used: 100)]
        )
        XCTAssertEqual(account.primaryMetric?.label, "Premium")
    }

    func testEmptyMetricsHasNoPrimary() {
        let account = UsageAccount(provider: "X", plan: nil, email: nil, metrics: [])
        XCTAssertNil(account.primaryMetric)
        XCTAssertEqual(account.secondaryMetrics.count, 0)
    }

    func testSecondaryMetricsOmitThePrimary() {
        let account = UsageAccount(
            provider: "Copilot", plan: nil, email: nil,
            metrics: [metric("Chat", used: 0), metric("Weekly", used: 40), metric("Premium", used: 100)]
        )
        XCTAssertEqual(account.primaryMetric?.label, "Weekly")
        XCTAssertEqual(account.secondaryMetrics.map(\.label), ["Chat", "Premium"])
    }
}

final class UsageResetLabelTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let en = Locale(identifier: "en_US")
    private let zh = Locale(identifier: "zh_CN")

    func testNilResetsAtIsNil() {
        XCTAssertNil(UsageMetric.resetLabel(resetsAt: nil, now: Date(), locale: en, zh: false, timeZone: utc))
    }

    func testUnparseableResetsAtIsNil() {
        XCTAssertNil(UsageMetric.resetLabel(resetsAt: "not-a-date", now: Date(), locale: en, zh: false, timeZone: utc))
    }

    func testHoursFromNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let at = ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 3600 + 5 * 60))
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: at, now: now, locale: en, zh: false, timeZone: utc), "in 3h")
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: at, now: now, locale: zh, zh: true, timeZone: utc), "3 小时后")
    }

    func testSameCalendarDayUsesClock() {
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: "2026-01-01T15:30:00Z", now: now, locale: en, zh: false, timeZone: utc),
                       "15:30")
    }

    func testWithinAWeekUsesWeekday() {
        let now = Date(timeIntervalSince1970: 1_767_225_600) // Thursday 2026-01-01 UTC
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: "2026-01-04T11:22:00Z", now: now, locale: en, zh: false, timeZone: utc),
                       "Sun")
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: "2026-01-04T11:22:00Z", now: now, locale: zh, zh: true, timeZone: utc),
                       "周日")
    }

    func testFarFutureUsesMonthDay() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: "2026-10-19T02:17:26Z", now: now, locale: en, zh: false, timeZone: utc),
                       "Oct 19")
        XCTAssertEqual(UsageMetric.resetLabel(resetsAt: "2026-10-19T02:17:26Z", now: now, locale: zh, zh: true, timeZone: utc),
                       "10月19日")
    }
}

final class UsageL10nTests: XCTestCase {
    func testSectionAndUnavailableCopy() {
        XCTAssertEqual(L10n(language: .zh).quotas, "配额")
        XCTAssertEqual(L10n(language: .en).quotas, "Quotas")
        XCTAssertEqual(L10n(language: .zh).subscriptionsUnavailable, "订阅暂不可用")
        XCTAssertEqual(L10n(language: .en).subscriptionsUnavailable, "Subscriptions unavailable")
    }
}
