import Foundation
import ServiceManagement

enum MenuMetric: String, CaseIterable, Identifiable {
    case cost, tokens, messages
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cost: return "费用"
        case .tokens: return "Tokens"
        case .messages: return "消息数"
        }
    }
}

enum RefreshInterval: TimeInterval, CaseIterable, Identifiable {
    case minute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: TimeInterval { rawValue }
    var label: String {
        switch self {
        case .minute: return "1 分钟"
        case .fiveMinutes: return "5 分钟"
        case .fifteenMinutes: return "15 分钟"
        }
    }
}

final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var menuMetric: MenuMetric {
        didSet { defaults.set(menuMetric.rawValue, forKey: "menuMetric") }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }
    @Published var tokscalePath: String {
        didSet { defaults.set(tokscalePath, forKey: "tokscalePath") }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    init() {
        menuMetric = MenuMetric(rawValue: defaults.string(forKey: "menuMetric") ?? "") ?? .cost
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = RefreshInterval(rawValue: interval) ?? .fiveMinutes
        tokscalePath = defaults.string(forKey: "tokscalePath") ?? ""
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
