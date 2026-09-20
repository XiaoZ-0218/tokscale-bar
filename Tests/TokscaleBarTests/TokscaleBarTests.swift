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

    func testExactTokensKeepFullDigits() {
        XCTAssertEqual(Format.tokens(0, .exact), "0")
        XCTAssertEqual(Format.tokens(999, .exact), "999")
        XCTAssertEqual(Format.tokens(1_234, .exact), "1,234")
        XCTAssertEqual(Format.tokens(152_000_000, .exact), "152,000,000")
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
        let today = Dates.dayString(fixedNow)
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

    func testMonthlyCostsGroupsAndOrdersByMonth() {
        let days = [
            day("2026-08-31", cost: 1),
            day("2026-07-01", cost: 2),
            day("2026-08-01", cost: 4),
        ]
        let months = TokscaleService.monthlyCosts(days)
        XCTAssertEqual(months.map(\.month), ["2026-07", "2026-08"])
        XCTAssertEqual(months.map(\.cost), [2, 5])
    }

    func testPadThirtyDaysToleratesDuplicateDates() {
        let today = Dates.dayString(fixedNow)
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

// MARK: - Process management (fake tokscale binary in a temp dir)

final class TokscaleServiceProcessTests: XCTestCase {
    private var tempDir: URL!

    /// Valid minimal payloads in the shape of real tokscale output.
    private let reportJSON = #"{"entries":[],"totalInput":0,"totalOutput":0,"totalCacheRead":0,"totalCacheWrite":0,"totalMessages":0,"totalCost":0}"#
    private let hourlyJSON = #"{"entries":[{"hour":"2026-09-06 09:00","cost":1.5}]}"#
    private let graphJSON = #"{"contributions":[{"date":"2026-09-06","totals":{"tokens":100,"cost":1.5,"messages":3}}]}"#
    private let usageJSON = #"[{"provider":"Kimi","metrics":[{"label":"Weekly","used_percent":66.0,"remaining_percent":34.0,"remaining_label":"34/100 left","resets_at":"2026-09-20T03:22:58Z"}]}]"#

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokscalebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes an executable shell script and returns its path.
    private func writeFakeBinary(_ contents: String, name: String = "tokscale") throws -> String {
        let path = tempDir.appendingPathComponent(name).path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// A fake tokscale that answers every job with a valid minimal payload;
    /// job selection mirrors TokscaleService.Job's first argument.
    private func writeFullFakeBinary() throws -> String {
        try writeFakeBinary("""
            #!/bin/bash
            if [ "$1" = "graph" ]; then
              echo '\(graphJSON)'
              exit 0
            fi
            if [ "$1" = "hourly" ]; then
              echo '\(hourlyJSON)'
              exit 0
            fi
            if [ "$1" = "usage" ]; then
              echo '\(usageJSON)'
              exit 0
            fi
            echo '\(reportJSON)'
            """)
    }

    func testFetchUsageDecodesAccountsFromFakeBinary() throws {
        let accounts = try makeService(pointingAt: try writeFullFakeBinary()).fetchUsage()
        XCTAssertEqual(accounts.map(\.provider), ["Kimi"])
        XCTAssertEqual(accounts[0].primaryMetric?.label, "Weekly")
        XCTAssertEqual(accounts[0].primaryMetric?.remainingPercent, 34)
    }

    private func makeService(pointingAt path: String) -> TokscaleService {
        let service = TokscaleService()
        service.binaryPath = path
        return service
    }

    /// Mirrors TokscaleService.isExecutableBinary (private): a usable
    /// binary is a regular executable file, not a directory.
    private func isUsableBinary(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    func testNonZeroExitSurfacesStderrInFailedError() throws {
        let path = try writeFakeBinary("""
            #!/bin/bash
            echo "synthetic tokscale failure" >&2
            exit 3
            """)
        XCTAssertThrowsError(try makeService(pointingAt: path).fetchSnapshot()) { error in
            guard let tokscaleError = error as? TokscaleError,
                  case .failed(let message) = tokscaleError else {
                return XCTFail("expected .failed, got \(error)")
            }
            XCTAssertTrue(message.contains("synthetic tokscale failure"))
        }
    }

    func testMalformedGraphJSONBecomesFailedWithJobName() throws {
        let path = try writeFakeBinary("""
            #!/bin/bash
            if [ "$1" = "graph" ]; then
              echo 'not json at all'
              exit 0
            fi
            if [ "$1" = "hourly" ]; then
              echo '\(hourlyJSON)'
              exit 0
            fi
            echo '\(reportJSON)'
            """)
        XCTAssertThrowsError(try makeService(pointingAt: path).fetchSnapshot()) { error in
            guard let tokscaleError = error as? TokscaleError,
                  case .failed(let message) = tokscaleError else {
                return XCTFail("expected .failed, got \(error)")
            }
            XCTAssertTrue(message.contains("graph"), "message should name the job: \(message)")
            XCTAssertTrue(message.contains("failed to decode"), "message should mention the decode failure: \(message)")
        }
    }

    func testHungProcessTimesOut() throws {
        // TokscaleService.timeout is a private constant (20s) with no
        // injection point, so exercising the timedOut path would stall the
        // suite for 20+ seconds. Skipped until the timeout is injectable.
        throw XCTSkip("timeout is a private 20s constant and cannot be shortened for tests")
    }

    func testFetchSnapshotAssemblesPaddedViewsFromFakeBinary() throws {
        let service = makeService(pointingAt: try writeFullFakeBinary())
        let snapshot = try service.fetchSnapshot()
        XCTAssertEqual(snapshot.today.totalCost, 0)
        XCTAssertEqual(snapshot.weekDays.count, 7)
        XCTAssertEqual(snapshot.last30Days.count, 30)
        // GraphPayload is private, so its minimal decode shape is covered
        // here end-to-end instead of via a direct JSONDecoder test.
        XCTAssertEqual(snapshot.allDays.map(\.date), ["2026-09-06"])
        XCTAssertEqual(snapshot.allDays[0].totals.tokens, 100)
        XCTAssertEqual(snapshot.hours.count, 24)
        XCTAssertEqual(snapshot.hours[9].cost, 1.5)
        XCTAssertEqual(snapshot.hours[8].cost, 0)
    }

    func testResolvesBinaryFromPATHWhenHomebrewPrefixesMiss() throws {
        // resolveBinary checks the Homebrew prefixes before scanning PATH;
        // a real installation there would shadow the temp binary.
        let shadowed = ["/opt/homebrew/bin/tokscale", "/usr/local/bin/tokscale"]
            .contains(where: isUsableBinary)
        if shadowed {
            throw XCTSkip("a Homebrew tokscale would shadow the PATH fallback")
        }
        try writeFullFakeBinary()
        let oldPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", tempDir.path, 1)
        defer { setenv("PATH", oldPath, 1) }
        let service = TokscaleService()
        service.binaryPath = "" // auto-detect
        let snapshot = try service.fetchSnapshot()
        XCTAssertEqual(snapshot.allDays.map(\.date), ["2026-09-06"])
        XCTAssertEqual(snapshot.hours[9].cost, 1.5)
    }
}

// MARK: - History dedup

final class DedupedDaysTests: XCTestCase {
    private func day(_ date: String, cost: Double) -> DayUsage {
        DayUsage(date: date, totals: .init(tokens: 0, cost: cost, messages: 0))
    }

    func testSortsAscendingAndLastWriteWins() {
        let days = [
            day("2026-09-06", cost: 1),
            day("2026-09-04", cost: 2),
            day("2026-09-06", cost: 3), // duplicate date: last write wins
            day("2026-09-05", cost: 4),
        ]
        let deduped = TokscaleService.dedupedDays(days)
        XCTAssertEqual(deduped.map(\.date), ["2026-09-04", "2026-09-05", "2026-09-06"])
        XCTAssertEqual(deduped.map(\.totals.cost), [2, 4, 3])
    }
}

// MARK: - Payload decoding

final class PayloadDecodingTests: XCTestCase {
    /// Minimal real-shape `hourly --json` output.
    func testHourlyPayloadMinimalDecode() throws {
        let json = #"{"entries":[{"hour":"2026-09-06 00:00","cost":0},{"hour":"2026-09-06 09:00","cost":1.5}]}"#
        let payload = try JSONDecoder().decode(HourlyPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.entries.count, 2)
        XCTAssertEqual(payload.entries[1].hour, "2026-09-06 09:00")
        XCTAssertEqual(payload.entries[1].cost, 1.5)
    }

    func testHourlyPayloadEmptyEntries() throws {
        let payload = try JSONDecoder().decode(HourlyPayload.self, from: Data(#"{"entries":[]}"#.utf8))
        XCTAssertTrue(payload.entries.isEmpty)
    }
}

// MARK: - Format boundaries

final class FormatBoundaryTests: XCTestCase {
    func testCostNonPositiveIsBareZero() {
        XCTAssertEqual(Format.cost(0), "$0")
        XCTAssertEqual(Format.cost(-1), "$0")
        XCTAssertEqual(Format.cost(-0.5, currency: .cny, rate: 7.2), "¥0")
    }

    /// The display tier is chosen on the value rounded at that tier's
    /// precision, so a boundary like 99.996 renders "$100" without ever
    /// crossing into a misleading tier ("$100.00" / "$99.100").
    func testCostTierBoundaries() {
        XCTAssertEqual(Format.cost(99.996), "$100")
        XCTAssertEqual(Format.cost(99.995), "$100")
        XCTAssertEqual(Format.cost(99.994), "$99.99")
        XCTAssertEqual(Format.cost(0.9995), "$1.00")
        XCTAssertEqual(Format.cost(0.9949), "$0.995")
        // The Double literal 0.995 is fractionally below 0.995, so the
        // %.2f tier honestly renders "0.99" — within-tier rounding, not a
        // tier crossing.
        XCTAssertEqual(Format.cost(0.995), "$0.99")
    }

    /// Rounded-tier rule: 999999.9 belongs to the M tier ("1.0M"), never
    /// "1000.0K"; the plain tier ends at 999.5 so 999 stays "999".
    func testCompactRoundedTierBoundaries() {
        XCTAssertEqual(Format.compact(999), "999")
        XCTAssertEqual(Format.compact(999.5), "1.0K")
        XCTAssertEqual(Format.compact(999999.9), "1.0M")
        XCTAssertEqual(Format.compact(999949), "999.9K")
        XCTAssertEqual(Format.compact(999950), "1.0M")
        XCTAssertEqual(Format.compact(999949999), "999.9M")
        XCTAssertEqual(Format.compact(999950000), "1.0B")
        XCTAssertEqual(Format.compact(-1500), "-1.5K")
    }

    func testCompactChineseRoundedTierBoundaries() {
        XCTAssertEqual(Format.compactChinese(999), "999")
        XCTAssertEqual(Format.compactChinese(9999), "9999") // below the 万 tier
        XCTAssertEqual(Format.compactChinese(9_999_999), "1000万")
        XCTAssertEqual(Format.compactChinese(99_999_999), "1.0亿") // rounds up, not "10000万"
        XCTAssertEqual(Format.compactChinese(100_000_000), "1.0亿")
        XCTAssertEqual(Format.compactChinese(-15000), "-1.5万")
    }

    func testTokensRoutesThroughUnitStyle() {
        XCTAssertEqual(Format.tokens(1500, .western), "1.5K")
        XCTAssertEqual(Format.tokens(2_000_000, .western), "2.0M")
        XCTAssertEqual(Format.tokens(15000, .chinese), "1.5万")
        XCTAssertEqual(Format.tokens(150_000_000, .chinese), "1.5亿")
    }
}

// MARK: - Hourly padding against malformed CLI output

final class PadHoursMalformedTests: XCTestCase {
    func testSkipsEntriesWithoutParseableInRangeHour() {
        let payload = HourlyPayload(entries: [
            .init(hour: "2026-09-06 09:00", cost: 1),
            .init(hour: "2026-09-06T10:00", cost: 2),  // ISO "T" variant parses
            .init(hour: "2026-09-06", cost: 4),        // no time component
            .init(hour: "not a timestamp", cost: 8),   // unparseable
            .init(hour: "2026-09-06 25:00", cost: 16), // hour out of range
            .init(hour: "2026-09-06 09:00", cost: 1),  // same valid hour sums
        ])
        let hours = TokscaleService.padHours(payload)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9].cost, 2)
        XCTAssertEqual(hours[10].cost, 2)
        // Only the two parseable entries contribute; the malformed costs
        // (4 + 8 + 16) must not leak into any slot.
        XCTAssertEqual(hours.reduce(0) { $0 + $1.cost }, 4)
    }
}

// MARK: - L10n error text and month labels

final class L10nErrorTextTests: XCTestCase {
    func testBinaryNotFoundBilingual() {
        XCTAssertEqual(L10n(language: .zh).errorText(TokscaleError.binaryNotFound),
                       "找不到 tokscale，请在设置里指定路径")
        XCTAssertEqual(L10n(language: .en).errorText(TokscaleError.binaryNotFound),
                       "tokscale not found — set its path in Settings")
    }

    /// A non-empty failure message passes through untouched in both
    /// languages — tokscale's own stderr is the most useful copy.
    func testFailedPassesThroughNonEmptyMessageInBothLanguages() {
        XCTAssertEqual(L10n(language: .zh).errorText(TokscaleError.failed("disk full")), "disk full")
        XCTAssertEqual(L10n(language: .en).errorText(TokscaleError.failed("disk full")), "disk full")
    }

    func testFailedEmptyMessageFallsBackPerLanguage() {
        XCTAssertEqual(L10n(language: .zh).errorText(TokscaleError.failed("")), "tokscale 执行失败")
        XCTAssertEqual(L10n(language: .en).errorText(TokscaleError.failed("")), "tokscale failed")
    }
}

final class L10nMonthLabelTests: XCTestCase {
    func testValidMonthLabels() {
        XCTAssertEqual(L10n(language: .zh).monthLabel("2026-01"), "1月")
        XCTAssertEqual(L10n(language: .zh).monthLabel("2026-09"), "9月")
        XCTAssertEqual(L10n(language: .en).monthLabel("2026-09"), "Sep")
        XCTAssertEqual(L10n(language: .en).monthLabel("2026-12"), "Dec")
    }

    /// Out-of-range or unparseable months fall back to the raw key instead
    /// of trapping on the month-name array.
    func testInvalidMonthFallsBackToRawKey() {
        XCTAssertEqual(L10n(language: .en).monthLabel("2026-13"), "2026-13")
        XCTAssertEqual(L10n(language: .en).monthLabel("2026-00"), "2026-00")
        XCTAssertEqual(L10n(language: .zh).monthLabel("2026-13"), "2026-13")
        XCTAssertEqual(L10n(language: .en).monthLabel("not-a-month"), "not-a-month")
    }
}

// MARK: - System language resolution

final class AppLanguageSystemTests: XCTestCase {
    /// `.system` follows the OS locale, so assert equivalence with
    /// `systemDefault` rather than hardcoding zh or en.
    func testSystemResolvesLikeSystemDefault() {
        let system = L10n(language: .system)
        let resolved = L10n(language: .systemDefault)
        XCTAssertEqual(AppLanguage.system.resolved, AppLanguage.systemDefault)
        XCTAssertEqual(system.locale, resolved.locale)
        XCTAssertEqual(system.errorText(TokscaleError.binaryNotFound),
                       resolved.errorText(TokscaleError.binaryNotFound))
        XCTAssertEqual(system.monthLabel("2026-09"), resolved.monthLabel("2026-09"))
        XCTAssertEqual(system.heroTitle(.today), resolved.heroTitle(.today))
    }
}

// MARK: - Settings rate persistence on launch

final class SettingsRateInitTests: XCTestCase {
    /// Mirror of Settings.Key.usdToCnyRate's raw value (the enum is private).
    private let key = "usdToCnyRate"

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// A stale out-of-range rate on disk is clamped at launch and the
    /// corrected value is written back, so the next launch can't offer the
    /// stale one back to the user.
    func testOutOfRangeStoredRateIsClampedAndRewritten() {
        UserDefaults.standard.set(1000.0, forKey: key)
        let settings = Settings()
        XCTAssertEqual(settings.usdToCnyRate, Defaults.usdToCnyRateRange.upperBound)
        XCTAssertEqual(UserDefaults.standard.double(forKey: key), Defaults.usdToCnyRateRange.upperBound)
    }

    func testNonPositiveStoredRateFallsBackToDefaultAndIsRewritten() {
        UserDefaults.standard.set(-3.0, forKey: key)
        let settings = Settings()
        XCTAssertEqual(settings.usdToCnyRate, Defaults.usdToCnyRate)
        XCTAssertEqual(UserDefaults.standard.double(forKey: key), Defaults.usdToCnyRate)
    }

    func testInRangeStoredRateSurvivesUnchanged() {
        UserDefaults.standard.set(7.0, forKey: key)
        let settings = Settings()
        XCTAssertEqual(settings.usdToCnyRate, 7.0)
        XCTAssertEqual(UserDefaults.standard.double(forKey: key), 7.0)
    }
}
