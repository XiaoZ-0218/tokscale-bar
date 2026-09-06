import Foundation
import ServiceManagement

enum MenuMetric: String, CaseIterable, Identifiable {
    case cost, tokens, messages
    var id: String { rawValue }
}

enum RefreshInterval: TimeInterval, CaseIterable, Identifiable {
    case minute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    var id: TimeInterval { rawValue }
}

/// Shared default values so Settings, Format, and the views stop
/// duplicating literals.
enum Defaults {
    static let usdToCnyRate: Double = 7.2
    static let usdToCnyRateRange: ClosedRange<Double> = 0.1...100
}

final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Set false to mutate settings in-memory only (used by --render-png previews).
    var persists = true

    @Published var menuMetric: MenuMetric {
        didSet { guard persists else { return }; defaults.set(menuMetric.rawValue, forKey: "menuMetric") }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { guard persists else { return }; defaults.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }
    @Published var tokscalePath: String {
        didSet { guard persists else { return }; defaults.set(tokscalePath, forKey: "tokscalePath") }
    }
    @Published var unitStyle: UnitStyle {
        didSet { guard persists else { return }; defaults.set(unitStyle.rawValue, forKey: "unitStyle") }
    }
    @Published var language: AppLanguage {
        didSet { guard persists else { return }; defaults.set(language.rawValue, forKey: "language") }
    }
    @Published var currency: AppCurrency {
        didSet { guard persists else { return }; defaults.set(currency.rawValue, forKey: "currency") }
    }
    @Published var usdToCnyRate: Double {
        didSet {
            let clamped = Self.clampRate(usdToCnyRate)
            if usdToCnyRate != clamped {
                // Hop out of the TextField commit before publishing the
                // correction back, so it can't land mid view-update. Only
                // correct if nothing newer was written meanwhile (NaN != NaN,
                // so compare it structurally).
                let written = usdToCnyRate
                DispatchQueue.main.async {
                    let current = self.usdToCnyRate
                    if current == written || (current.isNaN && written.isNaN) {
                        self.usdToCnyRate = clamped
                    }
                }
                return
            }
            guard persists else { return }
            defaults.set(usdToCnyRate, forKey: "usdToCnyRate")
        }
    }

    /// A TextField can submit 0 or negatives; keep the rate usable no
    /// matter where the write came from.
    static func clampRate(_ rate: Double) -> Double {
        guard rate.isFinite else { return Defaults.usdToCnyRate }
        return min(max(rate, Defaults.usdToCnyRateRange.lowerBound),
                   Defaults.usdToCnyRateRange.upperBound)
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard persists, !applyingLaunchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }
    /// Reentrancy guard: reverting the toggle inside `applyLaunchAtLogin`'s
    /// catch fires `didSet` again, which must not re-apply (stack overflow).
    private var applyingLaunchAtLogin = false

    var l10n: L10n { L10n(language: language) }

    init() {
        menuMetric = MenuMetric(rawValue: defaults.string(forKey: "menuMetric") ?? "") ?? .cost
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = RefreshInterval(rawValue: interval) ?? .fiveMinutes
        tokscalePath = defaults.string(forKey: "tokscalePath") ?? ""
        let savedLanguage = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .systemDefault
        language = savedLanguage
        // zh defaults to 万/亿 units, en to K/M/B; an explicit saved choice wins.
        unitStyle = UnitStyle(rawValue: defaults.string(forKey: "unitStyle") ?? "")
            ?? (savedLanguage == .zh ? .chinese : .western)
        let savedCurrency = AppCurrency(rawValue: defaults.string(forKey: "currency") ?? "")
        currency = savedCurrency ?? (savedLanguage == .zh ? .cny : .usd)
        let rate = defaults.double(forKey: "usdToCnyRate")
        usdToCnyRate = rate > 0 ? Self.clampRate(rate) : Defaults.usdToCnyRate
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        applyingLaunchAtLogin = true
        defer { applyingLaunchAtLogin = false }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned/dev bundles may fail; revert toggle to reflect reality.
            // Skip the write when already in sync so didSet doesn't fire again.
            let enabled = SMAppService.mainApp.status == .enabled
            if launchAtLogin != enabled { launchAtLogin = enabled }
        }
    }
}
