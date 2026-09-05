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
        let cost: Double
        let messageCount: Int

        var tokens: Int { input + output + cacheRead + cacheWrite }
    }

    let entries: [Entry]
    let totalInput: Int
    let totalOutput: Int
    let totalCacheRead: Int
    let totalCacheWrite: Int
    let totalMessages: Int
    let totalCost: Double

    var totalTokens: Int { totalInput + totalOutput + totalCacheRead + totalCacheWrite }
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

private struct HourlyPayload: Decodable {
    struct Entry: Decodable {
        let hour: String // "YYYY-MM-DD HH:00"
        let cost: Double
    }
    let entries: [Entry]
}

struct Snapshot {
    let today: Report
    let week: Report
    let month: Report
    let hours: [HourUsage]      // always 24 entries, zero-filled
    let weekDays: [DayUsage]    // 7 entries ending today, zero-filled
    let monthDays: [DayUsage]   // from the 1st to today, zero-filled
}

// MARK: - Service

enum TokscaleError: Error {
    case binaryNotFound
    case failed(String)
}

final class TokscaleService {
    /// Settings-provided override; empty means auto-detect.
    var binaryPath: String = ""

    private func resolveBinary() -> String? {
        if !binaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: binaryPath) {
            return binaryPath
        }
        for path in ["/opt/homebrew/bin/tokscale", "/usr/local/bin/tokscale"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func run(_ arguments: [String]) throws -> Data {
        guard let binary = resolveBinary() else { throw TokscaleError.binaryNotFound }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TokscaleError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    private enum Job: Int, CaseIterable {
        case today, week, month, hourly, graph

        var arguments: [String] {
            switch self {
            case .today: return ["--json", "--today", "--no-spinner"]
            case .week: return ["--json", "--week", "--no-spinner"]
            case .month: return ["--json", "--month", "--no-spinner"]
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
              let monthData = outputs[.month], let hourlyData = outputs[.hourly],
              let graphData = outputs[.graph] else {
            throw firstError ?? TokscaleError.failed("unknown")
        }

        let decoder = JSONDecoder()
        let graph = try decoder.decode(GraphPayload.self, from: graphData)
        let hourly = try decoder.decode(HourlyPayload.self, from: hourlyData)
        return Snapshot(
            today: try decoder.decode(Report.self, from: todayData),
            week: try decoder.decode(Report.self, from: weekData),
            month: try decoder.decode(Report.self, from: monthData),
            hours: Self.padHours(hourly),
            weekDays: Self.padWeek(graph.contributions),
            monthDays: Self.padMonth(graph.contributions)
        )
    }

    // MARK: - Zero-filling helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// All 24 hours of today, zero-filled.
    private static func padHours(_ payload: HourlyPayload) -> [HourUsage] {
        var byHour: [Int: Double] = [:]
        for entry in payload.entries {
            if let hour = Int(entry.hour.suffix(5).prefix(2)) {
                byHour[hour, default: 0] += entry.cost
            }
        }
        return (0..<24).map { HourUsage(hour: $0, cost: byHour[$0] ?? 0) }
    }

    /// 7 days ending today, zero-filled.
    private static func padWeek(_ days: [DayUsage]) -> [DayUsage] {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let key = dayFormatter.string(from: date)
            return byDate[key] ?? DayUsage(date: key, totals: .init(tokens: 0, cost: 0, messages: 0))
        }
    }

    /// Days of the current month from the 1st to today, zero-filled.
    private static func padMonth(_ days: [DayUsage]) -> [DayUsage] {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let calendar = Calendar.current
        let today = Date()
        let day = calendar.component(.day, from: today)
        return (0..<day).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let key = dayFormatter.string(from: date)
            return byDate[key] ?? DayUsage(date: key, totals: .init(tokens: 0, cost: 0, messages: 0))
        }
    }
}

// MARK: - Formatting

enum Format {
    static func cost(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.3f", value)
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

    static func compactChinese(_ value: Double) -> String {
        switch abs(value) {
        case 100_000_000...: return String(format: "%.1f亿", value / 1e8)
        case 1_000_000...: return String(format: "%.0f万", value / 1e4)
        case 10_000...: return String(format: "%.1f万", value / 1e4)
        case 1_000...: return String(format: "%.1f千", value / 1e3)
        default: return String(format: "%.0f", value)
        }
    }
}
