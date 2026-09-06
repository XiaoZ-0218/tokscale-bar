import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var label: String { self == .zh ? "中文" : "English" }
    var locale: Locale { Locale(identifier: self == .zh ? "zh_CN" : "en_US") }

    /// System default: Chinese when the preferred language is Chinese.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }
}

enum UnitStyle: String, CaseIterable, Identifiable {
    case western, chinese // K/M/B vs 万/亿
    var id: String { rawValue }
    var label: String { self == .western ? "K / M" : "万 / 亿" }
}

enum AppCurrency: String, CaseIterable, Identifiable {
    case usd, cny
    var id: String { rawValue }
    var label: String { self == .usd ? "USD $" : "CNY ¥" }
    var symbol: String { self == .usd ? "$" : "¥" }
}

/// All user-visible strings, keyed off the selected in-app language.
struct L10n {
    let language: AppLanguage
    private var zh: Bool { language == .zh }

    var locale: Locale { language.locale }

    // Periods
    func periodLabel(_ period: Period) -> String {
        switch period {
        case .today: return zh ? "今天" : "Today"
        case .week: return zh ? "近 7 天" : "7 Days"
        case .month: return zh ? "本月" : "Month"
        }
    }

    func heroTitle(_ period: Period) -> String {
        switch period {
        case .today: return zh ? "今日花费" : "Today's Spend"
        case .week: return zh ? "近 7 天花费" : "Last 7 Days"
        case .month: return zh ? "本月花费" : "This Month"
        }
    }

    func messagesPill(_ count: Int) -> String {
        zh ? "\(count) 条消息" : "\(count) messages"
    }

    var vsYesterday: String { zh ? "较昨日" : "vs yesterday" }

    // Charts
    var hourlyChart: String { zh ? "分时段" : "Hourly" }
    var dailyChart: String { zh ? "每日花费" : "Daily Spend" }

    func hourLabel(_ hour: Int) -> String {
        zh ? "\(hour)时" : "\(hour):00"
    }

    var weekdayLetters: [String] {
        zh ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"]
    }

    // Breakdowns
    func topModels(_ count: Int) -> String {
        zh ? "模型 TOP \(count)" : "TOP \(count) MODELS"
    }
    var byClient: String { zh ? "客户端占比" : "BY CLIENT" }
    var other: String { zh ? "其他" : "Other" }

    // Settings
    var settingsTitle: String { zh ? "设置" : "Settings" }
    var menuBarShows: String { zh ? "菜单栏显示" : "Menu Bar Shows" }
    var refreshEvery: String { zh ? "刷新间隔" : "Refresh Every" }
    var launchAtLogin: String { zh ? "登录时启动" : "Launch at Login" }
    var numberUnits: String { zh ? "数字单位" : "Number Units" }
    var languageLabel: String { zh ? "语言" : "Language" }
    var currencyLabel: String { zh ? "货币" : "Currency" }
    var rateLabel: String { zh ? "汇率 USD→CNY" : "Rate USD→CNY" }
    var tokscalePath: String { zh ? "TOKSCALE 路径" : "TOKSCALE PATH" }
    var autoDetect: String { zh ? "留空自动检测" : "Auto-detect" }
    var privacyNote: String {
        zh ? "数据来自本机 tokscale CLI，全部留在本地。"
           : "Data comes from the local tokscale CLI and never leaves your Mac."
    }

    func metricLabel(_ metric: MenuMetric) -> String {
        switch metric {
        case .cost: return zh ? "费用" : "Cost"
        case .tokens: return "Tokens"
        case .messages: return zh ? "消息数" : "Messages"
        }
    }

    func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .minute: return zh ? "1 分钟" : "1 min"
        case .fiveMinutes: return zh ? "5 分钟" : "5 min"
        case .fifteenMinutes: return zh ? "15 分钟" : "15 min"
        }
    }

    // Errors
    func errorText(_ error: Error) -> String {
        guard let tokscaleError = error as? TokscaleError else { return error.localizedDescription }
        switch tokscaleError {
        case .binaryNotFound:
            return zh ? "找不到 tokscale，请在设置里指定路径"
                      : "tokscale not found — set its path in Settings"
        case .invalidBinaryPath(let path):
            return zh ? "tokscale 路径不可执行：\(path)"
                      : "tokscale path is not executable: \(path)"
        case .timedOut:
            return zh ? "tokscale 超时，请稍后重试" : "tokscale timed out"
        case .failed(let message):
            if !message.isEmpty { return message }
            return zh ? "tokscale 执行失败" : "tokscale failed"
        }
    }
}
