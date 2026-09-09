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

    /// A fixed instant so tests never flake across midnight.
    private let fixedNow: Date = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "2026-09-06 12:00")!
    }()

    func testPadWeekEndsOnNowAndToleratesDuplicateDates() {
        let today = Self.dayFormatter.string(from: fixedNow)
        let days = TokscaleService.padDays([day(today, cost: 1), day(today, cost: 2)], count: 7, now: fixedNow)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.date, "2026-09-06")
        XCTAssertEqual(days.first?.date, "2026-08-31")
        XCTAssertEqual(days.last?.totals.cost, 2) // last duplicate wins
    }

    func testPadThirtyDaysEndsOnNow() {
        let days = TokscaleService.padDays([], count: 30, now: fixedNow)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.first?.date, "2026-08-08")
        XCTAssertEqual(days.last?.date, "2026-09-06")
    }

    func testPadThirtyDaysToleratesDuplicateDates() {
        let today = Self.dayFormatter.string(from: fixedNow)
        let days = TokscaleService.padDays([day(today, cost: 1), day(today, cost: 2)], count: 30, now: fixedNow)
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

final class ChildEnvironmentTests: XCTestCase {
    /// The bug: Finder-launched apps get a bare PATH, so tokscale's
    /// `#!/usr/bin/env node` shebang fails with "env: node: No such file
    /// or directory". The child PATH must include the Homebrew prefixes.
    func testAddsHomebrewPrefixesToBareFinderPath() {
        let env = TokscaleService.childEnvironment(base: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let components = env["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertTrue(components.contains("/opt/homebrew/bin"))
        XCTAssertTrue(components.contains("/usr/local/bin"))
        XCTAssertLessThan(components.firstIndex(of: "/opt/homebrew/bin")!,
                          components.firstIndex(of: "/usr/bin")!)
    }

    func testDoesNotDuplicateExistingPrefixes() {
        let env = TokscaleService.childEnvironment(base: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"])
        XCTAssertEqual(env["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    func testMissingPathFallsBackToSystemDefault() {
        let env = TokscaleService.childEnvironment(base: [:])
        XCTAssertTrue(env["PATH"]!.contains("/usr/bin"))
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
