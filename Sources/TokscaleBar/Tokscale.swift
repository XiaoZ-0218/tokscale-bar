import Foundation

// MARK: - Decoded models matching tokscale's JSON output

struct Report: Decodable {
    struct Entry: Decodable {
        let client: String
        let model: String
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        /// Reasoning tokens; optional so older tokscale builds still decode.
        let reasoning: Int?
        let cost: Double
        let messageCount: Int

        var tokens: Int { input + output + cacheRead + cacheWrite + (reasoning ?? 0) }
    }

    let entries: [Entry]
    let totalInput: Int
    let totalOutput: Int
    let totalCacheRead: Int
    let totalCacheWrite: Int
    let totalMessages: Int
    let totalCost: Double

    /// The report's top-level totals exclude reasoning, so sum it from
    /// entries to stay consistent with `graph`'s totals.tokens.
    var totalTokens: Int {
        totalInput + totalOutput + totalCacheRead + totalCacheWrite
            + entries.reduce(0) { $0 + ($1.reasoning ?? 0) }
    }
}

struct DayUsage: Decodable {
    struct Totals: Decodable {
        let tokens: Int
        let cost: Double
        let messages: Int
    }
    let date: String // YYYY-MM-DD
    let totals: Totals
}

struct HourUsage {
    let hour: Int // 0...23
    let cost: Double
}

private struct GraphPayload: Decodable {
    let contributions: [DayUsage]
}

struct HourlyPayload: Decodable {
    struct Entry: Decodable {
        let hour: String // "YYYY-MM-DD HH:00"
        let cost: Double
    }
    let entries: [Entry]
}

struct Snapshot {
    let today: Report
    let week: Report
    let last30: Report
    let all: Report
    let hours: [HourUsage]      // always 24 entries, zero-filled
    let weekDays: [DayUsage]    // 7 entries ending today, zero-filled
    let last30Days: [DayUsage]  // 30 entries ending today, zero-filled
    let allDays: [DayUsage]     // full history from `graph`, deduped and ascending
}

// MARK: - Service

enum TokscaleError: Error {
    case binaryNotFound
    case invalidBinaryPath(String)
    case timedOut
    case failed(String)
}

final class TokscaleService {
    /// Settings-provided override; empty means auto-detect.
    var binaryPath: String = ""

    /// isExecutableFile alone accepts directories (the search bit), so a
    /// usable binary must be a regular executable file.
    private func isExecutableBinary(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// A custom path must be executable — silently falling back to another
    /// binary would make the settings field lie. Empty means auto-detect.
    private func resolveBinary() throws -> String {
        if !binaryPath.isEmpty {
            guard isExecutableBinary(binaryPath) else {
                throw TokscaleError.invalidBinaryPath(binaryPath)
            }
            return binaryPath
        }
        for path in ["/opt/homebrew/bin/tokscale", "/usr/local/bin/tokscale"] {
            if isExecutableBinary(path) { return path }
        }
        throw TokscaleError.binaryNotFound
    }

    /// Max wall-clock time for one tokscale invocation before SIGTERM/SIGKILL.
    private let timeout: TimeInterval = 20

    /// Apps launched by Finder/launchd get a bare PATH ("/usr/bin:/bin:…"),
    /// but tokscale is a `#!/usr/bin/env node` script and node lives in the
    /// Homebrew prefix — without it, the child dies with
    /// "env: node: No such file or directory". Prepend the usual prefixes
    /// unless they already appear, so a user's own PATH ordering still wins.
    static func childEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var components = current.split(separator: ":").map(String.init)
        for prefix in ["/usr/local/bin", "/opt/homebrew/bin"] where !components.contains(prefix) {
            components.insert(prefix, at: 0)
        }
        env["PATH"] = components.joined(separator: ":")
        return env
    }

    private func run(_ arguments: [String]) throws -> Data {
        let binary = try resolveBinary()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = Self.childEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        // Drain both pipes concurrently: a child that fills stderr's ~64KB
        // buffer would otherwise block forever while we wait on stdout.
        // Writes go through a lock so there's no data race on the buffers.
        let bufferLock = NSLock()
        var outData = Data()
        var errData = Data()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            bufferLock.lock()
            outData = data
            bufferLock.unlock()
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            bufferLock.lock()
            errData = data
            bufferLock.unlock()
            reads.leave()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                if process.processIdentifier > 0 { process.terminate() } // SIGTERM
                if exited.wait(timeout: .now() + 1) == .timedOut,
                   process.isRunning, process.processIdentifier > 0 {
                    kill(process.processIdentifier, SIGKILL)
                    // A child in uninterruptible sleep survives even SIGKILL
                    // briefly; keep this wait bounded too — the path throws
                    // timedOut regardless of what terminationStatus says.
                    _ = exited.wait(timeout: .now() + 2)
                } else {
                    process.waitUntilExit() // settles terminationStatus
                }
                // A killed child can leave the pipes held open by a
                // grandchild, so the drain wait must be bounded too. Don't
                // close the read ends here: closing under a blocked
                // readDataToEndOfFile can raise NSFileHandleOperationException
                // on the reader thread and abort the process. Worst case is a
                // couple of sleeping reader threads; the UI still recovers.
                _ = reads.wait(timeout: .now() + 1)
                throw TokscaleError.timedOut
            }
            // else: exited on its own right at the deadline — fall through
            // and treat it like a normal exit.
        }
        process.waitUntilExit() // no-op once terminated; settles terminationStatus
        // The process is dead, so its output is already in the pipe buffers;
        // if a grandchild holds them open, fail instead of blocking forever.
        if reads.wait(timeout: .now() + 2) == .timedOut {
            throw TokscaleError.failed("tokscale exited but its output streams never closed")
        }
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw TokscaleError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outData
    }

    private enum Job: Int, CaseIterable {
        case today, week, last30, all, hourly, graph

        var arguments: [String] {
            switch self {
            case .today: return ["--json", "--today", "--no-spinner"]
            case .week: return ["--json", "--week", "--no-spinner"]
            // tokscale has no "last N days" shortcut; --since/--until are inclusive.
            case .last30: return ["--json", "--since", TokscaleService.dayString(daysAgo: 29),
                                  "--until", TokscaleService.dayString(daysAgo: 0), "--no-spinner"]
            // No date flags: tokscale reports its full history.
            case .all: return ["--json", "--no-spinner"]
            case .hourly: return ["hourly", "--json", "--today", "--no-spinner"]
            case .graph: return ["graph", "--no-spinner"]
            }
        }
    }

    func fetchSnapshot() throws -> Snapshot {
        // Run the five tokscale queries concurrently; each takes ~3s.
        var outputs: [Job: Data] = [:]
        var firstError: Error?
        let lock = NSLock()
        let group = DispatchGroup()
        for job in Job.allCases {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    let data = try self.run(job.arguments)
                    lock.lock(); outputs[job] = data; lock.unlock()
                } catch {
                    lock.lock(); firstError = firstError ?? error; lock.unlock()
                }
            }
        }
        group.wait()
        guard let todayData = outputs[.today], let weekData = outputs[.week],
              let last30Data = outputs[.last30], let allData = outputs[.all],
              let hourlyData = outputs[.hourly], let graphData = outputs[.graph] else {
            throw firstError ?? TokscaleError.failed("unknown")
        }

        let decoder = JSONDecoder()
        let graph = try decoder.decode(GraphPayload.self, from: graphData)
        let hourly = try decoder.decode(HourlyPayload.self, from: hourlyData)
        return Snapshot(
            today: try decoder.decode(Report.self, from: todayData),
            week: try decoder.decode(Report.self, from: weekData),
            last30: try decoder.decode(Report.self, from: last30Data),
            all: try decoder.decode(Report.self, from: allData),
            hours: Self.padHours(hourly),
            weekDays: Self.padDays(graph.contributions, count: 7),
            last30Days: Self.padDays(graph.contributions, count: 30),
            allDays: Self.dedupedDays(graph.contributions)
        )
    }

    // MARK: - Zero-filling helpers

    /// POSIX locale + Gregorian calendar so a user on a non-Gregorian
    /// system calendar still parses tokscale's ISO dates correctly. Padding
    /// keys follow the local time zone ("today" means the Mac's today);
    /// autoupdating so a long-lived menu bar app survives timezone changes.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// All 24 hours of today, zero-filled.
    static func padHours(_ payload: HourlyPayload) -> [HourUsage] {
        var byHour: [Int: Double] = [:]
        for entry in payload.entries {
            // "2026-09-06 09:00" — take the HH of the time component.
            if let time = entry.hour.split(separator: " ").last,
               let hour = Int(time.prefix(2)) {
                byHour[hour, default: 0] += entry.cost
            }
        }
        return (0..<24).map { HourUsage(hour: $0, cost: byHour[$0] ?? 0) }
    }

    /// YYYY-MM-DD of `daysAgo` days before today, in the local time zone.
    private static func dayString(daysAgo: Int) -> String {
        dayFormatter.string(from: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!)
    }

/// Full history, last write per date wins, ascending by date.
    static func dedupedDays(_ days: [DayUsage]) -> [DayUsage] {
        Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
            .values
            .sorted { $0.date < $1.date }
    }

    /// Per-calendar-month cost totals, ascending. yyyy-MM keys sort lexically,
    /// which is also chronological.
    static func monthlyCosts(_ days: [DayUsage]) -> [(month: String, cost: Double)] {
        var byMonth: [String: Double] = [:]
        for day in days {
            byMonth[String(day.date.prefix(7)), default: 0] += day.totals.cost
        }
        return byMonth.sorted { $0.key < $1.key }.map { (month: $0.key, cost: $0.value) }
    }

    /// `count` days ending `now`, zero-filled. `now` is injectable for tests.
    static func padDays(_ days: [DayUsage], count: Int, now: Date = Date()) -> [DayUsage] {
        // graph can repeat a date; uniqueKeysWithValues would trap.
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            let key = dayFormatter.string(from: date)
            return byDate[key] ?? DayUsage(date: key, totals: .init(tokens: 0, cost: 0, messages: 0))
        }
    }
}

// MARK: - Formatting

enum Format {
    static func cost(_ value: Double, currency: AppCurrency = .usd, rate: Double = Defaults.usdToCnyRate) -> String {
        let amount = currency == .cny ? value * rate : value
        let symbol = currency.symbol
        if amount >= 100 { return String(format: "%@%.0f", symbol, amount) }
        if amount >= 1 { return String(format: "%@%.2f", symbol, amount) }
        if amount < 0.001 { return "\(symbol)0" } // a bare zero, not 0.000
        return String(format: "%@%.3f", symbol, amount)
    }

    static func tokens(_ value: Int, _ unit: UnitStyle = .western) -> String {
        switch unit {
        case .western: return compact(Double(value))
        case .chinese: return compactChinese(Double(value))
        }
    }

    static func compact(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1e9)
        case 1_000_000...: return String(format: "%.1fM", value / 1e6)
        case 1_000...: return String(format: "%.1fK", value / 1e3)
        default: return String(format: "%.0f", value)
        }
    }

    /// 千 is dropped: "1.0千" reads unnaturally in Chinese, so anything
    /// below 1万 stays a plain number.
    static func compactChinese(_ value: Double) -> String {
        switch abs(value) {
        case 100_000_000...: return String(format: "%.1f亿", value / 1e8)
        case 1_000_000...: return String(format: "%.0f万", value / 1e4)
        case 10_000...: return String(format: "%.1f万", value / 1e4)
        default: return String(format: "%.0f", value)
        }
    }
}
