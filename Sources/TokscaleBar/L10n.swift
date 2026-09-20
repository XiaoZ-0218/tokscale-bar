import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        case .system: return "跟随系统 / System"
        }
    }
    var locale: Locale { Locale(identifier: resolved == .zh ? "zh_CN" : "en_US") }

    /// The concrete language behind a choice; `.system` follows the OS.
    var resolved: AppLanguage { self == .system ? .systemDefault : self }

    /// System default: Chinese when the preferred language is Chinese.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }
}

enum UnitStyle: String, CaseIterable, Identifiable {
    case western, chinese, exact // K/M/B vs 万/亿 vs full digits
    var id: String { rawValue }
    var label: String {
        switch self {
        case .western: return "K / M / B"
        case .chinese: return "万 / 亿"
        case .exact: return "1,234,567"
        }
    }
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
    private var zh: Bool { language.resolved == .zh }

    var locale: Locale { language.locale }

    // Periods
    func periodLabel(_ period: Period) -> String {
        switch period {
        case .today: return zh ? "今天" : "Today"
        case .week: return zh ? "近 7 天" : "7 Days"
        case .last30: return zh ? "近 30 天" : "30 Days"
        case .all: return zh ? "全部" : "All"
        }
    }

    func heroTitle(_ period: Period, metric: HeroMetric = .cost) -> String {
        switch (period, metric) {
        case (.today, .cost): return zh ? "今日花费" : "Today's Spend"
        case (.week, .cost): return zh ? "近 7 天花费" : "Last 7 Days"
        case (.last30, .cost): return zh ? "近 30 天花费" : "Last 30 Days"
        case (.all, .cost): return zh ? "全部花费" : "All Time"
        case (.today, .tokens): return zh ? "今日 Tokens" : "Today's Tokens"
        case (.week, .tokens): return zh ? "近 7 天 Tokens" : "Last 7 Days Tokens"
        case (.last30, .tokens): return zh ? "近 30 天 Tokens" : "Last 30 Days Tokens"
        case (.all, .tokens): return zh ? "全部 Tokens" : "All Time Tokens"
        }
    }

    func messagesPill(_ count: Int) -> String {
        if zh { return "\(count) 条消息" }
        return count == 1 ? "1 message" : "\(count) messages"
    }

    /// "tokens" stays untranslated in zh — it's the industry term.
    func tokensPill(_ formattedCount: String) -> String {
        "\(formattedCount) tokens"
    }

    var vsYesterday: String { zh ? "较昨日" : "vs yesterday" }
    var quit: String { zh ? "退出" : "Quit" }
    var quitApp: String { zh ? "退出 TokscaleBar" : "Quit TokscaleBar" }
    var retry: String { zh ? "重试" : "Retry" }
    var refreshNow: String { zh ? "立即刷新" : "Refresh now" }

    // Charts
    var hourlyChart: String { zh ? "分时段" : "Hourly" }
    var noUsageYet: String { zh ? "还没有用量" : "No usage yet" }
    var dailyChart: String { zh ? "每日花费" : "Daily Spend" }
    var monthlyChart: String { zh ? "每月花费" : "Monthly Spend" }

    /// "2026-09" -> "9月" / "Sep"
    func monthLabel(_ yyyyMM: String) -> String {
        guard let month = Int(yyyyMM.suffix(2)), (1...12).contains(month) else { return yyyyMM }
        if zh { return "\(month)月" }
        return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1]
    }

    func hourLabel(_ hour: Int) -> String {
        zh ? "\(hour)时" : "\(hour):00"
    }

    var weekdayLetters: [String] {
        zh ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"]
    }

    // Breakdowns
    func topModels(_ count: Int) -> String {
        if zh { return "模型 TOP \(count)" }
        return count == 1 ? "TOP 1 MODEL" : "TOP \(count) MODELS"
    }
    var byClient: String { zh ? "客户端占比" : "BY CLIENT" }
    // Entry detail grid
    var detailInput: String { zh ? "输入" : "Input" }
    var detailOutput: String { zh ? "输出" : "Output" }
    var detailCacheRead: String { zh ? "缓存读" : "Cache read" }
    var detailCacheWrite: String { zh ? "缓存写" : "Cache write" }
    var detailReasoning: String { zh ? "推理" : "Reasoning" }
    var detailMessages: String { zh ? "消息" : "Messages" }
    var other: String { zh ? "其他" : "Other" }
    var subscriptionsUnavailable: String { zh ? "订阅暂不可用" : "Subscriptions unavailable" }

    // Subscriptions / ROI
    var roiTitle: String { zh ? "订阅回本" : "Payback" }
    var quotas: String { zh ? "配额" : "Quotas" }
    var addSubscription: String { zh ? "添加订阅" : "Add subscription" }
    var subscriptionsEmpty: String {
        zh ? "点 + 添加订阅，自动计算本周期回本倍数"
           : "Tap + to add a subscription and track its payback"
    }
    var perMonth: String { zh ? "/月" : "/mo" }
    /// "9/15 – 10/14 · 剩 10 天" / "Sep 15 – Oct 14 · 10d left"
    func cycleLine(_ start: String, _ end: String, daysLeft: Int) -> String {
        zh ? "\(start) – \(end) · 剩 \(daysLeft) 天" : "\(start) – \(end) · \(daysLeft)d left"
    }
    var cycleSpend: String { zh ? "本周期已用" : "Spent this cycle" }
    func toBreakEven(_ costText: String) -> String {
        zh ? "还差 \(costText) 回本" : "\(costText) to break even"
    }
    var brokeEven: String { zh ? "已回本" : "Paid off" }
    var spendUnavailable: String { zh ? "花费数据不可用" : "Spend unavailable" }
    var fieldName: String { zh ? "名称" : "Name" }
    var fieldPrice: String { zh ? "价格" : "Price" }
    var fieldBillingDay: String { zh ? "账单日" : "Billing day" }
    func dayOfMonth(_ day: Int) -> String {
        zh ? "每月 \(day) 号" : "Day \(day)"
    }
    var fieldKeywords: String { zh ? "关键词" : "Keywords" }
    var placeholderSubName: String { zh ? "Claude Pro" : "Claude Pro" }
    /// The zh example uses the full-width comma to hint both forms work.
    var placeholderKeywords: String { zh ? "claude，anthropic" : "claude, anthropic" }
    var keywordsFooter: String {
        zh ? "逗号分隔，匹配模型/客户端名；留空算全部"
           : "Comma-separated, matched against model/client names; empty matches everything"
    }
    var deleteSubscription: String { zh ? "删除订阅" : "Delete subscription" }

    func usageReset(_ metric: UsageMetric) -> String? {
        UsageMetric.resetLabel(resetsAt: metric.resetsAt, locale: locale, zh: zh)
    }

    // Settings
    var settingsTitle: String { zh ? "设置" : "Settings" }
    var back: String { zh ? "返回" : "Back" }
    var menuBarShows: String { zh ? "菜单栏显示" : "Menu Bar Shows" }
    var heroShows: String { zh ? "主卡片显示" : "Hero Shows" }
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

    func metricLabel(_ metric: HeroMetric) -> String {
        metricLabel(metric == .cost ? MenuMetric.cost : .tokens)
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
