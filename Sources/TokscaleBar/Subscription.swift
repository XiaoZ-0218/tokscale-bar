import Foundation

// AppCurrency is a String raw-value enum without an explicit Codable
// conformance in L10n.swift; Subscription stores it, so declare it here.
extension AppCurrency: Codable {}

/// A paid AI subscription the user wants to track payback for.
/// `keywords` match report entries by model/client name (case-insensitive
/// substring); empty means "count everything".
struct Subscription: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var currency: AppCurrency
    var billingDay: Int // 1...31; out-of-range values clamp at math time
    var keywords: [String]
}

/// [start, end): start is the most recent billing day (today counts),
/// end is the next cycle's start.
struct BillingCycle: Equatable {
    let start: Date
    let end: Date
}

/// Identifies one tokscale `--since/--until` query window; subscriptions
/// sharing a billing day share one fetch.
struct CycleKey: Hashable {
    let since: String
    let until: String
}

enum Billing {
    static func clampedDay(_ billingDay: Int) -> Int {
        min(max(billingDay, 1), 31)
    }

    /// The billing date inside (year, month), clamped to the month's length
    /// (billing day 31 → Feb 28/29).
    private static func cycleStart(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        var comps = DateComponents(year: year, month: month)
        let firstOfMonth = calendar.date(from: comps)!
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        comps.day = min(day, daysInMonth)
        return calendar.date(from: comps)!
    }

    static func currentCycle(billingDay: Int, now: Date = Date(),
                             calendar: Calendar = Dates.calendar) -> BillingCycle {
        let day = clampedDay(billingDay)
        let ym = calendar.dateComponents([.year, .month], from: now)
        var start = cycleStart(year: ym.year!, month: ym.month!, day: day, calendar: calendar)
        if start > now {
            // This month's billing day is still ahead — the cycle opened last
            // month. Month arithmetic clamps (Mar 31 - 1mo = Feb 28), and
            // cycleStart re-derives from year/month, so clamping can't drift.
            let anchor = calendar.date(byAdding: .month, value: -1, to: start)!
            let pym = calendar.dateComponents([.year, .month], from: anchor)
            start = cycleStart(year: pym.year!, month: pym.month!, day: day, calendar: calendar)
        }
        let anchor = calendar.date(byAdding: .month, value: 1, to: start)!
        let nym = calendar.dateComponents([.year, .month], from: anchor)
        let end = cycleStart(year: nym.year!, month: nym.month!, day: day, calendar: calendar)
        return BillingCycle(start: start, end: end)
    }
}

enum ROI {
    /// Sum of costs for entries whose model or client contains any keyword
    /// (case-insensitive substring). Empty/blank keywords match everything.
    static func matchedCost(_ entries: [Report.Entry], keywords: [String]) -> Double {
        let needles = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !needles.isEmpty else { return entries.reduce(0) { $0 + $1.cost } }
        return entries.reduce(0) { sum, entry in
            let haystack = entry.model.lowercased() + "\u{0}" + entry.client.lowercased()
            return needles.contains(where: { haystack.contains($0) }) ? sum + entry.cost : sum
        }
    }

    /// Payback multiple: cycle cost in USD ÷ price in USD (CNY converts via rate).
    static func multiple(costUSD: Double, price: Double, currency: AppCurrency, rate: Double) -> Double {
        let priceUSD = currency == .cny ? price / max(rate, 0.01) : price
        guard priceUSD > 0 else { return 0 }
        return costUSD / priceUSD
    }
}

/// UserDefaults-backed list of subscriptions. Mirrors Settings' `persists`
/// switch so mock/render-png runs never dirty the user's real data.
final class SubscriptionStore: ObservableObject {
    var persists = true
    @Published private(set) var subscriptions: [Subscription] = []

    private let defaults: UserDefaults
    private static let key = "subscriptions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ subscription: Subscription) {
        subscriptions.append(subscription)
        save()
    }

    func update(_ subscription: Subscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        subscriptions[index] = subscription
        save()
    }

    func remove(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        save()
    }

    /// Mock/preview channel: swap the list in memory without touching disk.
    func replace(_ subscriptions: [Subscription]) {
        self.subscriptions = subscriptions
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Subscription].self, from: data) else { return }
        subscriptions = decoded
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(subscriptions) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
