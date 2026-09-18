import Foundation
import ServiceManagement

enum MenuMetric: String, CaseIterable, Identifiable {
    case cost, tokens, messages
    var id: String { rawValue }
}

enum HeroMetric: String, CaseIterable, Identifiable {
    case cost, tokens
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

    /// UserDefaults keys. Raw values are the on-disk format and must stay stable.
    private enum Key: String {
        case menuMetric, heroMetric, refreshInterval, tokscalePath, unitStyle, language, currency, usdToCnyRate
    }

    @Published var menuMetric: MenuMetric {
        didSet { guard persists else { return }; defaults.set(menuMetric.rawValue, forKey: Key.menuMetric.rawValue) }
    }
    @Published var heroMetric: HeroMetric {
        didSet { guard persists else { return }; defaults.set(heroMetric.rawValue, forKey: Key.heroMetric.rawValue) }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { guard persists else { return }; defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval.rawValue) }
    }
    @Published var tokscalePath: String {
        didSet { guard persists else { return }; defaults.set(tokscalePath, forKey: Key.tokscalePath.rawValue) }
    }
    @Published var unitStyle: UnitStyle {
        didSet { guard persists else { return }; defaults.set(unitStyle.rawValue, forKey: Key.unitStyle.rawValue) }
    }
    @Published var language: AppLanguage {
        didSet { guard persists else { return }; defaults.set(language.rawValue, forKey: Key.language.rawValue) }
    }
    @Published var currency: AppCurrency {
        didSet { guard persists else { return }; defaults.set(currency.rawValue, forKey: Key.currency.rawValue) }
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
            defaults.set(usdToCnyRate, forKey: Key.usdToCnyRate.rawValue)
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
        menuMetric = MenuMetric(rawValue: defaults.string(forKey: Key.menuMetric.rawValue) ?? "") ?? .cost
        heroMetric = HeroMetric(rawValue: defaults.string(forKey: Key.heroMetric.rawValue) ?? "") ?? .cost
        let interval = defaults.double(forKey: Key.refreshInterval.rawValue)
        refreshInterval = RefreshInterval(rawValue: interval) ?? .fiveMinutes
        tokscalePath = defaults.string(forKey: Key.tokscalePath.rawValue) ?? ""
        let savedLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.language.rawValue) ?? "") ?? .systemDefault
        language = savedLanguage
        // zh defaults to 万/亿 units, en to K/M/B; an explicit saved choice wins.
        unitStyle = UnitStyle(rawValue: defaults.string(forKey: Key.unitStyle.rawValue) ?? "")
            ?? (savedLanguage.resolved == .zh ? .chinese : .western)
        let savedCurrency = AppCurrency(rawValue: defaults.string(forKey: Key.currency.rawValue) ?? "")
        currency = savedCurrency ?? (savedLanguage.resolved == .zh ? .cny : .usd)
        let rate = defaults.double(forKey: Key.usdToCnyRate.rawValue)
        let initialRate = rate > 0 ? Self.clampRate(rate) : Defaults.usdToCnyRate
        usdToCnyRate = initialRate
        // Property observers don't fire during init, so persist a corrected
        // rate once here; otherwise a stale out-of-range value on disk would
        // be offered back to the user on the next launch. Read the clamped
        // value from the local, not self — stored properties aren't all
        // initialized until launchAtLogin is set below.
        if persists, initialRate != rate {
            defaults.set(initialRate, forKey: Key.usdToCnyRate.rawValue)
        }
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
            // A stale registration makes register() throw; clear it and retry
            // once before giving up on the toggle. Don't sniff error codes —
            // SMAppService's thrown codes don't reliably match the documented
            // kSMError* values across macOS versions.
            if launchAtLogin {
                try? SMAppService.mainApp.unregister()
                if (try? SMAppService.mainApp.register()) != nil { return }
            }
            // Unsigned/dev bundles may fail; revert toggle to reflect reality.
            // Skip the write when already in sync so didSet doesn't fire again.
            let enabled = SMAppService.mainApp.status == .enabled
            if launchAtLogin != enabled { launchAtLogin = enabled }
        }
    }
}
