import Foundation

// MARK: - Decoded models matching `tokscale --json` and `tokscale graph --week`

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

private struct GraphPayload: Decodable {
    let contributions: [DayUsage]
}

struct Snapshot {
    let today: Report
    let month: Report
    let week: [DayUsage] // always 7 entries, zero-filled
}

// MARK: - Service

enum TokscaleError: Error, LocalizedError {
    case binaryNotFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "找不到 tokscale，请在设置里指定路径"
        case .failed(let msg): return msg.isEmpty ? "tokscale 执行失败" : msg
        }
    }
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

    func fetchSnapshot() throws -> Snapshot {
        let decoder = JSONDecoder()
        let today = try decoder.decode(Report.self, from: run(["--json", "--today", "--no-spinner"]))
        let month = try decoder.decode(Report.self, from: run(["--json", "--month", "--no-spinner"]))
        let graph = try decoder.decode(GraphPayload.self, from: run(["graph", "--week", "--no-spinner"]))
        return Snapshot(today: today, month: month, week: Self.padWeek(graph.contributions))
    }

    /// Ensure exactly 7 days ending today, filling gaps with zeros.
    private static func padWeek(_ days: [DayUsage]) -> [DayUsage] {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let key = formatter.string(from: date)
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

    static func tokens(_ value: Int) -> String {
        compact(Double(value))
    }

    static func compact(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1e9)
        case 1_000_000...: return String(format: "%.1fM", value / 1e6)
        case 1_000...: return String(format: "%.1fK", value / 1e3)
        default: return String(format: "%.0f", value)
        }
    }
}
