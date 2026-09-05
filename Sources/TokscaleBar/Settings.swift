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
    @Published var launchAtLogin: Bool {
        didSet { guard persists else { return }; applyLaunchAtLogin() }
    }

    var l10n: L10n { L10n(language: language) }

    init() {
        menuMetric = MenuMetric(rawValue: defaults.string(forKey: "menuMetric") ?? "") ?? .cost
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = RefreshInterval(rawValue: interval) ?? .fiveMinutes
        tokscalePath = defaults.string(forKey: "tokscalePath") ?? ""
        unitStyle = UnitStyle(rawValue: defaults.string(forKey: "unitStyle") ?? "") ?? .western
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .systemDefault
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned/dev bundles may fail; revert toggle to reflect reality.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
