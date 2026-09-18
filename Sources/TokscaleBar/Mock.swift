import Foundation

/// Deterministic fake data for UI development (`--mock` / `--state empty`).
/// Rich enough to exercise every dashboard section: delta badge, all three
/// charts, top-5 rows with several clients, and the share bar.
enum Mock {
    static var snapshot: Snapshot {
        Snapshot(
            today: report(todayEntries),
            week: report(weekEntries),
            last30: report(last30Entries),
            all: report(allEntries),
            hours: hourCurve,
            weekDays: pastDays(7, costs: [12.4, 28.1, 21.7, 35.2, 18.9, 41.5, 34.26]),
            last30Days: pastDays(30, costs: (1...30).map { 6 + 30 * abs(sin(Double($0) * 0.9)) }),
            allDays: pastDays(64, costs: (1...64).map { 4 + 28 * abs(sin(Double($0) * 0.7)) })
        )
    }

    /// All-zero snapshot: exercises the chart empty state and ¥0 hero.
    static var empty: Snapshot {
        Snapshot(
            today: .empty, week: .empty, last30: .empty, all: .empty,
            hours: (0..<24).map { HourUsage(hour: $0, cost: 0) },
            weekDays: pastDays(7, costs: [0, 0, 0, 0, 0, 0, 0]),
            last30Days: pastDays(30, costs: [Double](repeating: 0, count: 30)),
            allDays: []
        )
    }

    // MARK: Entries

    private static let todayEntries: [Report.Entry] = [
        entry("zcode", "claude-opus-4.6", 26_700_000, 12.77, 812, reasoning: 1_300_000),
        entry("grok", "grok-4.6", 7_700_000, 10.25, 640),
        entry("zcode", "grok-4.6", 9_000_000, 6.42, 431),
        entry("zcode", "glm-5.3-flash", 170_600_000, 3.43, 355),
        entry("codex", "k3-256k", 2_400_000, 1.27, 89),
    ]

    private static let weekEntries: [Report.Entry] = [
        entry("zcode", "claude-opus-4.6", 152_000_000, 71.30, 4_102, reasoning: 7_400_000),
        entry("grok", "grok-4.6", 48_000_000, 63.80, 3_980),
        entry("zcode", "grok-4.6", 61_000_000, 43.12, 2_714),
        entry("zcode", "glm-5.3-flash", 980_000_000, 19.66, 2_201),
        entry("codex", "k3-256k", 14_000_000, 7.41, 522),
        entry("kimi", "k3-256k", 3_100_000, 1.05, 76),
    ]

    private static let last30Entries: [Report.Entry] = weekEntries.map {
        entry($0.client, $0.model, $0.tokens * 4, $0.cost * 4.2, $0.messageCount * 4)
    }

    private static let allEntries: [Report.Entry] = weekEntries.map {
        entry($0.client, $0.model, $0.tokens * 9, $0.cost * 9.5, $0.messageCount * 9)
    }

    /// Reasoning tokens count toward `tokens`, so a non-nil value comes out
    /// of the cacheRead share to keep the sections summing to `tokens`.
    private static func entry(_ client: String, _ model: String, _ tokens: Int,
                              _ cost: Double, _ messages: Int,
                              reasoning: Int? = nil) -> Report.Entry {
        Report.Entry(
            client: client, model: model,
            input: tokens * 3 / 10, output: tokens / 10,
            cacheRead: tokens * 6 / 10 - (reasoning ?? 0), cacheWrite: 0,
            reasoning: reasoning, cost: cost, messageCount: messages
        )
    }

    private static func report(_ entries: [Report.Entry]) -> Report {
        Report(
            entries: entries,
            totalInput: entries.reduce(0) { $0 + $1.input },
            totalOutput: entries.reduce(0) { $0 + $1.output },
            totalCacheRead: entries.reduce(0) { $0 + $1.cacheRead },
            totalCacheWrite: 0,
            totalMessages: entries.reduce(0) { $0 + $1.messageCount },
            totalCost: entries.reduce(0) { $0 + $1.cost }
        )
    }

    // MARK: Time series

    /// Plausible daily rhythm: quiet night, morning ramp, midday peak.
    private static let hourCurve: [HourUsage] = {
        let costs: [Double] = [0.4, 0.2, 0.1, 0, 0, 0.1, 0.3, 0.8, 1.6, 2.9, 4.1, 4.8,
                               3.9, 2.6, 3.3, 4.4, 3.1, 2.2, 1.7, 1.2, 0.9, 0.7, 0.6, 0.5]
        return costs.enumerated().map { HourUsage(hour: $0.offset, cost: $0.element) }
    }()

    private static func pastDays(_ count: Int, costs: [Double]) -> [DayUsage] {
        assert(costs.count == count, "pastDays(\(count)) got \(costs.count) costs")
        return zip(0..<count, costs).map { i, cost in
            let date = Dates.calendar.date(byAdding: .day, value: i - count + 1, to: Date())!
            return DayUsage(
                date: Dates.dayString(date),
                totals: DayUsage.Totals(tokens: 0, cost: cost, messages: 0)
            )
        }
    }
}
