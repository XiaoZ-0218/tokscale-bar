import XCTest
@testable import TokscaleBar

final class FormatTests: XCTestCase {
    func testCostUSD() {
        XCTAssertEqual(Format.cost(0.012), "$0.012")
        XCTAssertEqual(Format.cost(1.2), "$1.20")
        XCTAssertEqual(Format.cost(100), "$100")
    }

    func testCostCNYUsesRate() {
        XCTAssertEqual(Format.cost(1, currency: .cny, rate: 7.2), "¥7.20")
    }

    func testCompactWestern() {
        XCTAssertEqual(Format.compact(999), "999")
        XCTAssertEqual(Format.compact(1000), "1.0K")
        XCTAssertEqual(Format.compact(1_500_000), "1.5M")
        XCTAssertEqual(Format.compact(2_000_000_000), "2.0B")
    }

    func testCompactChinese() {
        XCTAssertEqual(Format.compactChinese(999), "999")
        XCTAssertEqual(Format.compactChinese(1000), "1000") // no 千 tier
        XCTAssertEqual(Format.compactChinese(10_000), "1.0万")
        XCTAssertEqual(Format.compactChinese(1_500_000), "150万")
        XCTAssertEqual(Format.compactChinese(100_000_000), "1.0亿")
    }
}

final class ReportDecodingTests: XCTestCase {
    /// Shrunk from real `tokscale --json --today` output; the second entry
    /// omits `reasoning` like older tokscale builds, and unknown keys
    /// (provider/performance/...) must be ignored.
    private let fixture = """
    {
      "entries": [
        {"client": "claude-code", "model": "claude-opus-4", "provider": "anthropic",
         "input": 100, "output": 200, "cacheRead": 300, "cacheWrite": 400,
         "reasoning": 50, "cost": 0.5, "messageCount": 3},
        {"client": "codex", "model": "gpt-5",
         "input": 10, "output": 20, "cacheRead": 30, "cacheWrite": 40,
         "cost": 0.1, "messageCount": 1}
      ],
      "totalInput": 110, "totalOutput": 220,
      "totalCacheRead": 330, "totalCacheWrite": 440,
      "totalMessages": 4, "totalCost": 0.6,
      "groupBy": "model"
    }
    """

    func testEntryTokensIncludeReasoning() throws {
        let report = try JSONDecoder().decode(Report.self, from: Data(fixture.utf8))
        XCTAssertEqual(report.entries[0].tokens, 1050)
        XCTAssertEqual(report.entries[1].tokens, 100) // missing reasoning decodes as nil
    }

    func testTotalTokensSumReasoningFromEntries() throws {
        let report = try JSONDecoder().decode(Report.self, from: Data(fixture.utf8))
        XCTAssertEqual(report.totalTokens, 110 + 220 + 330 + 440 + 50)
    }
}

final class PaddingTests: XCTestCase {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func day(_ date: String, cost: Double) -> DayUsage {
        DayUsage(date: date, totals: .init(tokens: 0, cost: cost, messages: 0))
    }

    func testPadHoursFills24AndParsesHour() {
        let payload = HourlyPayload(entries: [
            .init(hour: "2026-09-06 09:00", cost: 1.5),
            .init(hour: "2026-09-06 09:00", cost: 0.5), // same hour sums
        ])
        let hours = TokscaleService.padHours(payload)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9].cost, 2.0)
        XCTAssertEqual(hours[8].cost, 0)
    }

    func testPadWeekEndsTodayAndToleratesDuplicateDates() {
        let today = Self.dayFormatter.string(from: Date())
        let days = TokscaleService.padWeek([day(today, cost: 1), day(today, cost: 2)])
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.date, today)
        XCTAssertEqual(days.last?.totals.cost, 2) // last duplicate wins
    }

    func testPadMonthStartsOnTheFirst() {
        let days = TokscaleService.padMonth([])
        // Same calendar the implementation uses (Gregorian, local tz).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        XCTAssertEqual(days.count, calendar.component(.day, from: Date()))
        let firstDay = Self.dayFormatter.date(from: days[0].date).map { calendar.component(.day, from: $0) }
        XCTAssertEqual(firstDay, 1)
    }

    func testPadMonthToleratesDuplicateDates() {
        let today = Self.dayFormatter.string(from: Date())
        let days = TokscaleService.padMonth([day(today, cost: 1), day(today, cost: 2)])
        XCTAssertEqual(days.last?.totals.cost, 2) // last duplicate wins
    }
}

final class ClampRateTests: XCTestCase {
    func testClampRate() {
        XCTAssertEqual(Settings.clampRate(0), 0.1)
        XCTAssertEqual(Settings.clampRate(-1), 0.1)
        XCTAssertEqual(Settings.clampRate(.nan), Defaults.usdToCnyRate)
        XCTAssertEqual(Settings.clampRate(.infinity), Defaults.usdToCnyRate)
        XCTAssertEqual(Settings.clampRate(7.2), 7.2)
        XCTAssertEqual(Settings.clampRate(1000), 100)
    }
}

final class L10nErrorTests: XCTestCase {
    func testTimeoutCopy() {
        XCTAssertEqual(L10n(language: .zh).errorText(TokscaleError.timedOut), "tokscale 超时，请稍后重试")
        XCTAssertEqual(L10n(language: .en).errorText(TokscaleError.timedOut), "tokscale timed out")
    }

    func testInvalidPathCopyIncludesPath() {
        let path = "/tmp/not-a-binary"
        XCTAssertTrue(L10n(language: .zh).errorText(TokscaleError.invalidBinaryPath(path)).contains(path))
        XCTAssertTrue(L10n(language: .en).errorText(TokscaleError.invalidBinaryPath(path)).contains(path))
    }
}
