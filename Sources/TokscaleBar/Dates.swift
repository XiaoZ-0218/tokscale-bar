import Foundation

/// Shared date helpers for tokscale's ISO-style date keys. POSIX locale +
/// Gregorian calendar so a user on a non-Gregorian system calendar still
/// formats and parses them correctly; the time zone is autoupdating so a
/// long-lived menu bar app survives timezone changes.
///
/// DateFormatter is not thread-safe and these are shared between the
/// background fetch thread and the main-thread UI, so all formatter access
/// goes through the lock-guarded functions — never touch `dayFormatter`
/// directly.
enum Dates {
    /// Gregorian calendar matching the formatter configuration; used for
    /// date arithmetic so `date(byAdding:)` and `string(from:)` stay aligned.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    /// YYYY-MM-DD day keys, matching tokscale's `graph`/`hourly` output.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// YYYY-MM month keys; they sort lexically, which is also chronological.
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let lock = NSLock()

    static func dayString(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dayFormatter.string(from: date)
    }

    static func dayDate(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return dayFormatter.date(from: string)
    }

    static func monthString(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return monthFormatter.string(from: date)
    }
}
