# 液态玻璃 UI + 订阅回本倍数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 TokscaleBar 的 popover 升级为液态玻璃视觉 + 全元素 hover/点击详情，并新增订阅管理与"本周期回本倍数"自动计算。

**Architecture:** 渐进增强（路线 A）：Theme 层双路径玻璃（macOS 26+ 原生 `glassEffect`，低版本 vibrancy+高光回退）→ 订阅模块（新文件 `Subscription.swift`：模型 + 周期数学 + ROI + Store）→ 交互层（BarChart tooltip、行展开）。数据获取复用 tokscale CLI，每个去重后的计费周期窗口一次 `--since/--until` 查询。

**Tech Stack:** Swift 6.4 / SwiftUI + AppKit（NSPopover）、XCTest、UserDefaults JSON 持久化、macOS 13 部署目标（26+ API 走 `#available`）。

**Spec:** `docs/superpowers/specs/2026-09-20-liquid-glass-subscriptions-design.md`

## Global Constraints

- 部署目标保持 **macOS 13**（`Package.swift` 不动）；所有 macOS 26+ API 必须包在 `if #available(macOS 26.0, *)` / `@available` 里。
- 已验证的 SDK 事实（Xcode 27, macOS 27 SDK）：`glassEffect(_:in:)` 签名 `nonisolated public func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`，`@available(macOS 26.0, *)`，定义在 SwiftUICore（SwiftUI 自动 re-export，直接 `import SwiftUI` 可用）。`Glass` 有 `.regular` / `.clear` / `.identity` / `.tint(_:)` / `.interactive(_:)`。
- 测试用 **XCTest**（`final class XxxTests: XCTestCase` + `@testable import TokscaleBar`），不用 swift-testing。
- 日期数学一律用 `Dates.calendar`（Gregorian + POSIX locale + autoupdatingCurrent 时区）；日期 key 用 `Dates.dayString(_:)`。
- 金额显示一律走 `Format.cost(_:currency:rate:)`；tokens 显示走 `Format.tokens(_:_:)`。
- 所有用户可见字符串必须中英双语进 `L10n`（`zh ? "" : ""` 模式），禁止在视图里写死文案。
- Commit 遵循 Conventional Commits（`feat:` / `test:` / `refactor:` / `docs:`），每个任务结束提交一次。
- 持久化遵循现有 `Settings.persists` 模式：mock / `--render-png` / 测试不得写真实 UserDefaults。
- 现有测试必须保持绿（`swift test` 当前 69 passed, 2 skipped）。

---

### Task 0: 数字显示格式 — 具体数字选项

**Files:**
- Modify: `Sources/TokscaleBar/L10n.swift:24-27`（`UnitStyle` 加 `exact` case）
- Modify: `Sources/TokscaleBar/Tokscale.swift:504-509`（`Format.tokens` 加分支 + 手写千分位）
- Modify: `Sources/TokscaleBar/PopoverView.swift`（SettingsView 数字单位 picker `.frame(width: 150)` → `210`，容纳 3 段）
- Test: `Tests/TokscaleBarTests/TokscaleBarTests.swift`（Format 测试区追加，紧跟现有 compact/compactChinese 测试）

**Interfaces:**
- Consumes: 现有 `UnitStyle`（`L10n.swift:24`）、`Format.tokens(_:_:)`（`Tokscale.swift:504`）
- Produces: `UnitStyle.exact`（rawValue `"exact"`，旧版本遇到该持久化值回落默认，无迁移）；`Format.tokens(_:, .exact)` 返回千分位完整数字。调用方（菜单栏标题、hero、模型行、tooltip）零改动自动生效。

- [ ] **Step 1: 写失败测试**

在 `Tests/TokscaleBarTests/TokscaleBarTests.swift` 现有 `compactChinese` 测试（约 23-27 行）之后追加：

```swift
    func testExactTokensKeepFullDigits() {
        XCTAssertEqual(Format.tokens(0, .exact), "0")
        XCTAssertEqual(Format.tokens(999, .exact), "999")
        XCTAssertEqual(Format.tokens(1_234, .exact), "1,234")
        XCTAssertEqual(Format.tokens(152_000_000, .exact), "152,000,000")
    }
```

Run: `swift test --filter testExactTokensKeepFullDigits 2>&1 | tail -3`
Expected: 编译失败 —— `UnitStyle` 没有 `exact` case

- [ ] **Step 2: 实现**

a) `Sources/TokscaleBar/L10n.swift:24-27` 的 `UnitStyle` 改为：

```swift
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
```

b) `Sources/TokscaleBar/Tokscale.swift` 的 `Format.tokens`（504-509 行）改为：

```swift
    static func tokens(_ value: Int, _ unit: UnitStyle = .western) -> String {
        switch unit {
        case .western: return compact(Double(value))
        case .chinese: return compactChinese(Double(value))
        case .exact: return exact(value)
        }
    }

    /// Full digits with comma groups (1,234,567). Hand-rolled: no formatter,
    /// no locale dependence, deterministic in tests.
    static func exact(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (index, char) in digits.enumerated() where index > 0 {
            if (digits.count - index) % 3 == 0 { grouped += "," }
            grouped.append(char)
        }
        grouped.append(digits.last!) // the loop above skipped index 0; empty string can't reach here (digits is "0" at minimum)
        return (value < 0 ? "-" : "") + grouped
    }
```

实现注意：上面的 `exact` 循环写法容易绕晕，用更直白的等价实现替换：

```swift
    /// Full digits with comma groups (1,234,567). Hand-rolled: no formatter,
    /// no locale dependence, deterministic in tests.
    static func exact(_ value: Int) -> String {
        let digits = String(abs(value))
        let grouped = digits.reversed().enumerated().map { index, char in
            index > 0 && index % 3 == 0 ? "\(char)," : "\(char)"
        }.reversed().joined()
        return (value < 0 ? "-" : "") + grouped
    }
```

c) `Sources/TokscaleBar/PopoverView.swift` 设置页「数字单位」那一行（`settingRow(l10n.numberUnits)`，约 699-707 行）的 `.frame(width: 150)` 改为 `.frame(width: 210)`。

- [ ] **Step 3: 运行确认通过 + 全量回归**

Run: `swift test --filter testExactTokensKeepFullDigits 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: 新测试 PASS；全量 70 passed, 2 skipped

- [ ] **Step 4: Commit**

```bash
git add Sources/TokscaleBar/L10n.swift Sources/TokscaleBar/Tokscale.swift Sources/TokscaleBar/PopoverView.swift Tests/TokscaleBarTests/TokscaleBarTests.swift
git commit -m "feat: exact-number unit style alongside K/M/B and 万/亿"
```

---

### Task 1: Subscription 模型 + 计费周期数学

**Files:**
- Create: `Sources/TokscaleBar/Subscription.swift`
- Test: `Tests/TokscaleBarTests/BillingCycleTests.swift`

**Interfaces:**
- Consumes: `Dates.calendar`, `Dates.dayString(_:)`（已存在于 `Sources/TokscaleBar/Dates.swift`）；`AppCurrency`（已存在于 `L10n.swift`）
- Produces（后续任务依赖这些签名）:
  - `struct Subscription: Codable, Identifiable, Equatable { var id: UUID; var name: String; var price: Double; var currency: AppCurrency; var billingDay: Int; var keywords: [String] }`
  - `struct BillingCycle: Equatable { let start: Date; let end: Date }`（`[start, end)`，end 是下个周期起点）
  - `enum Billing { static func currentCycle(billingDay: Int, now: Date = Date(), calendar: Calendar = Dates.calendar) -> BillingCycle }`
  - `struct CycleKey: Hashable { let since: String; let until: String }`

- [ ] **Step 1: 写失败测试**

新建 `Tests/TokscaleBarTests/BillingCycleTests.swift`：

```swift
import XCTest
@testable import TokscaleBar

final class BillingCycleTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Dates.calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// now 在本月账单日之前 → 周期从上个月开始。
    func testNowBeforeBillingDayStartsLastMonth() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 3))
        XCTAssertEqual(cycle.start, date(2026, 8, 15))
        XCTAssertEqual(cycle.end, date(2026, 9, 15))
    }

    /// 账单日当天 → 新周期今天开始。
    func testOnBillingDayStartsToday() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 15))
        XCTAssertEqual(cycle.start, date(2026, 9, 15))
        XCTAssertEqual(cycle.end, date(2026, 10, 15))
    }

    func testAfterBillingDayRunsToNextMonth() {
        let cycle = Billing.currentCycle(billingDay: 15, now: date(2026, 9, 20))
        XCTAssertEqual(cycle.start, date(2026, 9, 15))
        XCTAssertEqual(cycle.end, date(2026, 10, 15))
    }

    /// 31 号账单日在 30 天的月份 clamp 到月末。
    func testBillingDay31ClampsToShortMonth() {
        let cycle = Billing.currentCycle(billingDay: 31, now: date(2026, 9, 20))
        XCTAssertEqual(cycle.start, date(2026, 8, 31))
        XCTAssertEqual(cycle.end, date(2026, 9, 30))
    }

    /// 2 月 clamp 到 28；且下月（3 月）恢复 31。
    func testFebruaryClampThenMarchRestores31() {
        let feb = Billing.currentCycle(billingDay: 31, now: date(2026, 2, 10))
        XCTAssertEqual(feb.start, date(2026, 1, 31))
        XCTAssertEqual(feb.end, date(2026, 2, 28))

        let mar = Billing.currentCycle(billingDay: 31, now: date(2026, 3, 15))
        XCTAssertEqual(mar.start, date(2026, 2, 28))
        XCTAssertEqual(mar.end, date(2026, 3, 31))
    }

    /// 3/31 当天的周期终点是 4/30。
    func testMarch31CycleEndsApril30() {
        let cycle = Billing.currentCycle(billingDay: 31, now: date(2026, 3, 31))
        XCTAssertEqual(cycle.start, date(2026, 3, 31))
        XCTAssertEqual(cycle.end, date(2026, 4, 30))
    }

    /// 跨年：1 月初的周期从上一年 12 月开始。
    func testYearBoundary() {
        let cycle = Billing.currentCycle(billingDay: 10, now: date(2026, 1, 5))
        XCTAssertEqual(cycle.start, date(2025, 12, 10))
        XCTAssertEqual(cycle.end, date(2026, 1, 10))
    }

    /// 越界账单日 clamp 到 1...31。
    func testOutOfRangeBillingDayClamps() {
        let low = Billing.currentCycle(billingDay: 0, now: date(2026, 9, 20))
        XCTAssertEqual(low.start, date(2026, 9, 1))
        XCTAssertEqual(low.end, date(2026, 10, 1))

        let high = Billing.currentCycle(billingDay: 45, now: date(2026, 9, 20))
        XCTAssertEqual(high.start, date(2026, 8, 31))
        XCTAssertEqual(high.end, date(2026, 9, 30))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter BillingCycleTests 2>&1 | tail -5`
Expected: 编译失败，"cannot find 'Billing' in scope"

- [ ] **Step 3: 实现**

新建 `Sources/TokscaleBar/Subscription.swift`：

```swift
import Foundation

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
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter BillingCycleTests 2>&1 | tail -3`
Expected: 8 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/TokscaleBar/Subscription.swift Tests/TokscaleBarTests/BillingCycleTests.swift
git commit -m "feat: add Subscription model and billing-cycle math"
```

---

### Task 2: ROI 匹配与倍数计算

**Files:**
- Modify: `Sources/TokscaleBar/Subscription.swift`（追加 `ROI` enum）
- Test: `Tests/TokscaleBarTests/ROITests.swift`

**Interfaces:**
- Consumes: `Report.Entry`（`Sources/TokscaleBar/Tokscale.swift:6`，memberwise init 对 `@testable` 可见）；`Subscription`（Task 1）；`AppCurrency`（`L10n.swift:30`）
- Produces:
  - `enum ROI { static func matchedCost(_ entries: [Report.Entry], keywords: [String]) -> Double; static func multiple(costUSD: Double, price: Double, currency: AppCurrency, rate: Double) -> Double }`

- [ ] **Step 1: 写失败测试**

新建 `Tests/TokscaleBarTests/ROITests.swift`：

```swift
import XCTest
@testable import TokscaleBar

final class ROITests: XCTestCase {
    private func entry(_ client: String, _ model: String, _ cost: Double) -> Report.Entry {
        Report.Entry(client: client, model: model, input: 0, output: 0,
                     cacheRead: 0, cacheWrite: 0, reasoning: nil,
                     cost: cost, messageCount: 0)
    }

    private var entries: [Report.Entry] {
        [
            entry("zcode", "claude-opus-4.6", 71.30),
            entry("grok", "grok-4.6", 63.80),
            entry("zcode", "grok-4.6", 43.12),
            entry("codex", "k3-256k", 7.41),
        ]
    }

    func testKeywordMatchesModelNameCaseInsensitive() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["CLAUDE"]), 71.30, accuracy: 1e-9)
    }

    func testKeywordMatchesClientName() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["grok"]), 63.80 + 43.12, accuracy: 1e-9)
    }

    func testMultipleKeywordsUnion() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["claude", "k3"]), 71.30 + 7.41, accuracy: 1e-9)
    }

    /// 空白关键词被忽略；全部为空 = 匹配所有 entry。
    func testEmptyKeywordsMatchEverything() {
        let total = entries.reduce(0) { $0 + $1.cost }
        XCTAssertEqual(ROI.matchedCost(entries, keywords: []), total, accuracy: 1e-9)
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["  ", ""]), total, accuracy: 1e-9)
    }

    func testNoMatchIsZero() {
        XCTAssertEqual(ROI.matchedCost(entries, keywords: ["llama"]), 0)
    }

    func testMultipleUSD() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 20, currency: .usd, rate: 7.2), 2.4, accuracy: 1e-9)
    }

    /// CNY 价格先按汇率折成 USD 再算倍数：¥144 / 7.2 = $20。
    func testMultipleCNY() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 144, currency: .cny, rate: 7.2), 2.4, accuracy: 1e-9)
    }

    /// 价格为 0 或负不产生除零/负倍数。
    func testMultipleZeroPriceIsZero() {
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: 0, currency: .usd, rate: 7.2), 0)
        XCTAssertEqual(ROI.multiple(costUSD: 48, price: -5, currency: .usd, rate: 7.2), 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter ROITests 2>&1 | tail -5`
Expected: 编译失败，"cannot find 'ROI' in scope"

- [ ] **Step 3: 实现**

在 `Sources/TokscaleBar/Subscription.swift` 末尾追加：

```swift
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
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter ROITests 2>&1 | tail -3`
Expected: 9 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/TokscaleBar/Subscription.swift Tests/TokscaleBarTests/ROITests.swift
git commit -m "feat: add ROI keyword matching and payback multiple"
```

---

### Task 3: SubscriptionStore 持久化

**Files:**
- Modify: `Sources/TokscaleBar/Subscription.swift`（追加 `SubscriptionStore`）
- Test: `Tests/TokscaleBarTests/SubscriptionStoreTests.swift`

**Interfaces:**
- Consumes: `Subscription`（Task 1）
- Produces:
  - `final class SubscriptionStore: ObservableObject`，属性 `var persists = true`、`@Published private(set) var subscriptions: [Subscription]`，方法 `init(defaults: UserDefaults = .standard)`、`add(_:)`、`update(_:)`、`remove(id: UUID)`、`replace(_: [Subscription])`（mock 用，不写盘）

- [ ] **Step 1: 写失败测试**

新建 `Tests/TokscaleBarTests/SubscriptionStoreTests.swift`：

```swift
import XCTest
@testable import TokscaleBar

final class SubscriptionStoreTests: XCTestCase {
    /// 每个测试一个全新 suite，互不影响也不碰真实 UserDefaults。
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SubscriptionStoreTests.\(UUID().uuidString)")!
    }

    private func sample(name: String = "Claude Pro") -> Subscription {
        Subscription(name: name, price: 20, currency: .usd, billingDay: 15, keywords: ["claude"])
    }

    func testAddPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        let sub = sample()
        store.add(sub)

        let reloaded = SubscriptionStore(defaults: defaults)
        XCTAssertEqual(reloaded.subscriptions, [sub])
    }

    func testUpdateWritesNewValues() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        var sub = sample()
        store.add(sub)
        sub.price = 40
        sub.billingDay = 1
        store.update(sub)

        let reloaded = SubscriptionStore(defaults: defaults)
        XCTAssertEqual(reloaded.subscriptions.first?.price, 40)
        XCTAssertEqual(reloaded.subscriptions.first?.billingDay, 1)
    }

    func testRemoveDeletes() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        let sub = sample()
        store.add(sub)
        store.remove(id: sub.id)

        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }

    /// persists=false（mock / render-png）不得写盘。
    func testNonPersistingStoreWritesNothing() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        store.persists = false
        store.add(sample())

        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }

    /// replace 是 mock 通道：改内存，不落盘。
    func testReplaceSwapsInMemoryOnly() {
        let defaults = makeDefaults()
        let store = SubscriptionStore(defaults: defaults)
        store.add(sample(name: "Real"))
        store.replace([sample(name: "Mock")])

        XCTAssertEqual(store.subscriptions.map(\.name), ["Mock"])
        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions.map(\.name), ["Real"])
    }

    /// 磁盘上的坏数据不得 crash，按空列表处理。
    func testCorruptDataLoadsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "subscriptions.v1")
        XCTAssertEqual(SubscriptionStore(defaults: defaults).subscriptions, [])
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter SubscriptionStoreTests 2>&1 | tail -5`
Expected: 编译失败，"cannot find 'SubscriptionStore' in scope"

- [ ] **Step 3: 实现**

在 `Sources/TokscaleBar/Subscription.swift` 末尾追加：

```swift
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
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter SubscriptionStoreTests 2>&1 | tail -3`
Expected: 6 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/TokscaleBar/Subscription.swift Tests/TokscaleBarTests/SubscriptionStoreTests.swift
git commit -m "feat: add SubscriptionStore persistence"
```

---

### Task 4: tokscale 区间查询 `fetchReport(since:until:)`

**Files:**
- Modify: `Sources/TokscaleBar/Tokscale.swift`（`Job` enum 后/`fetchUsage` 附近加公开方法）

**Interfaces:**
- Consumes: 私有 `run(_:)` 与 `decode(_:from:job:using:)`（同文件已存在）
- Produces: `func fetchReport(since: String, until: String) throws -> Report`（Task 5 的 AppModel 调用它）

无新单元测试：这是对子进程 `run()` 的薄封装，与现有 `Job.last30`（同参数模式，`Tokscale.swift:328-329`）行为一致；验证靠编译 + Task 10 的实机 preview。

- [ ] **Step 1: 实现**

在 `Sources/TokscaleBar/Tokscale.swift` 的 `fetchSnapshot()` 之后、`fetchUsage()` 之前插入：

```swift
    /// Arbitrary inclusive date range, e.g. one subscription's billing cycle.
    /// Same flags as the built-in last-30-days job.
    func fetchReport(since: String, until: String) throws -> Report {
        let data = try run(["--json", "--since", since, "--until", until, "--no-spinner"])
        return try Self.decode(Report.self, from: data, job: "range", using: JSONDecoder())
    }
```

- [ ] **Step 2: 编译验证**

Run: `swift build 2>&1 | tail -2`
Expected: Build complete

- [ ] **Step 3: Commit**

```bash
git add Sources/TokscaleBar/Tokscale.swift
git commit -m "feat: expose ranged report fetch for billing cycles"
```

---

### Task 5: AppModel 接入订阅 Store + 周期报表拉取 + Mock

**Files:**
- Modify: `Sources/TokscaleBar/main.swift`（`AppModel` 属性 + `refresh()` 第三路并发 + `pinnedSnapshot` mock 接线）
- Modify: `Sources/TokscaleBar/Mock.swift`（`Mock.subscriptions` + `Mock.cycleReports(for:)`）
- Test: `Tests/TokscaleBarTests/MockCycleReportTests.swift`

**Interfaces:**
- Consumes: `Subscription` / `Billing` / `CycleKey`（Task 1）、`SubscriptionStore`（Task 3）、`fetchReport(since:until:)`（Task 4）
- Produces:
  - `AppModel.subscriptionStore: SubscriptionStore`
  - `AppModel.cycleReports: [CycleKey: Report]`（`@Published`）
  - `Mock.subscriptions: [Subscription]`、`Mock.cycleReports(for: [Subscription]) -> [CycleKey: Report]`

- [ ] **Step 1: 写失败测试**

新建 `Tests/TokscaleBarTests/MockCycleReportTests.swift`：

```swift
import XCTest
@testable import TokscaleBar

final class MockCycleReportTests: XCTestCase {
    /// Mock 数据必须覆盖每个 mock 订阅的当前周期窗口，预览才不空窗。
    func testCycleReportsCoverEveryMockSubscription() {
        let now = Date()
        let reports = Mock.cycleReports(for: Mock.subscriptions)
        for sub in Mock.subscriptions {
            let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
            let key = CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
            XCTAssertNotNil(reports[key], "missing cycle report for \(sub.name)")
        }
    }

    /// Mock 订阅要覆盖 ≥1 倍和 <1 倍两种状态（绿色/橙色徽章都能看到）。
    func testMockSubscriptionsShowBothSidesOfBreakeven() {
        let now = Date()
        let reports = Mock.cycleReports(for: Mock.subscriptions)
        let multiples = Mock.subscriptions.map { sub -> Double in
            let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
            let key = CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
            let cost = ROI.matchedCost(reports[key]?.entries ?? [], keywords: sub.keywords)
            return ROI.multiple(costUSD: cost, price: sub.price, currency: sub.currency,
                                rate: Defaults.usdToCnyRate)
        }
        XCTAssertTrue(multiples.contains { $0 >= 1 }, "need a paid-off mock: \(multiples)")
        XCTAssertTrue(multiples.contains { $0 > 0 && $0 < 1 }, "need a not-yet mock: \(multiples)")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter MockCycleReportTests 2>&1 | tail -5`
Expected: 编译失败，"value of type 'Mock' has no member 'subscriptions'"

- [ ] **Step 3: 实现 Mock**

在 `Sources/TokscaleBar/Mock.swift` 的 `usage` 属性之后追加：

```swift
    /// Two subscriptions covering both badge states: Claude Pro pays for
    /// itself on the week report (~3.5×), Kimi does not (~0.6×).
    static var subscriptions: [Subscription] {
        [
            Subscription(name: "Claude Pro", price: 20, currency: .usd, billingDay: 1,
                         keywords: ["claude"]),
            Subscription(name: "Kimi", price: 99, currency: .cny, billingDay: 15,
                         keywords: ["kimi", "k3"]),
        ]
    }

    /// One report per distinct current-cycle window; reuses the week report,
    /// whose entries already mix claude / grok / k3 models.
    static func cycleReports(for subscriptions: [Subscription]) -> [CycleKey: Report] {
        let now = Date()
        var reports: [CycleKey: Report] = [:]
        for sub in subscriptions {
            let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
            let key = CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
            reports[key] = reports[key] ?? snapshot.week
        }
        return reports
    }
```

- [ ] **Step 4: 实现 AppModel 接线**

`Sources/TokscaleBar/main.swift`：

a) `AppModel` 属性区（`@Published var usageError` 之后）加：

```swift
    @Published var cycleReports: [CycleKey: Report] = [:]

    let subscriptionStore = SubscriptionStore()
```

注意：`let settings = Settings()` 已存在，`subscriptionStore` 紧随其后即可。属性初始化顺序无依赖。

b) `pinnedSnapshot.didSet` 的 mock 分支（`main.swift:29-32`，即 `usage = Mock.usage` 那段）改为：

```swift
            if pinnedSnapshot != nil {
                usage = Mock.usage
                usageError = nil
                subscriptionStore.replace(Mock.subscriptions)
                cycleReports = Mock.cycleReports(for: Mock.subscriptions)
            }
```

c) `refresh()` 里第二路（usage）之后、`group.wait()` 之前加第三路：

```swift
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                // One tokscale query per distinct cycle window; subscriptions
                // sharing a billing day share the fetch.
                let now = Date()
                var keys = Set<CycleKey>()
                for sub in self.subscriptionStore.subscriptions {
                    let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
                    keys.insert(CycleKey(since: Dates.dayString(cycle.start),
                                         until: Dates.dayString(now)))
                }
                var results: [CycleKey: Report] = [:]
                let resultsLock = NSLock()
                let fetches = DispatchGroup()
                for key in keys {
                    fetches.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { fetches.leave() }
                        // A failed window leaves no entry; the card shows
                        // "spend unavailable" instead of poisoning others.
                        if let report = try? self.service.fetchReport(since: key.since, until: key.until) {
                            resultsLock.lock()
                            results[key] = report
                            resultsLock.unlock()
                        }
                    }
                }
                fetches.wait()
                DispatchQueue.main.async {
                    guard self.fetchesLiveData else { return }
                    self.cycleReports = results
                }
            }
```

（`keys` 为空时 `fetches` 立即返回，`cycleReports` 清空——删除所有订阅后状态自然复位。）

- [ ] **Step 5: 运行确认通过**

Run: `swift test --filter MockCycleReportTests 2>&1 | tail -3 && swift build 2>&1 | tail -1`
Expected: 2 tests passed + Build complete

- [ ] **Step 6: 全量回归**

Run: `swift test 2>&1 | tail -3`
Expected: 全部通过（原 69 + 新增 25）

- [ ] **Step 7: Commit**

```bash
git add Sources/TokscaleBar/main.swift Sources/TokscaleBar/Mock.swift Tests/TokscaleBarTests/MockCycleReportTests.swift
git commit -m "feat: fetch per-cycle reports and wire subscription mock data"
```

---

### Task 6: 液态玻璃卡片（双路径 CardStyle）

**Files:**
- Modify: `Sources/TokscaleBar/Theme.swift`（重写 `CardStyle`，调用方签名不变）

**Interfaces:**
- Consumes: 已验证的 `glassEffect(_:in:)`（macOS 26+）
- Produces: 不变 —— 所有 `.card(radius:)` 调用点（`PopoverView.swift` 7 处）自动获得玻璃质感

- [ ] **Step 1: 实现**

把 `Sources/TokscaleBar/Theme.swift:31-42` 的 `CardStyle` 替换为：

```swift
/// The standard content card. macOS 26+ gets real Liquid Glass; older systems
/// get a frosted fallback — a vibrancy-adjacent surface with a top edge
/// highlight that fakes the glass rim. Callers keep one modifier either way.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.white.opacity(0.1), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: radius * 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .allowsHitTesting(false)
                }
        }
    }
}
```

注意 `body` 必须加 `@ViewBuilder`，否则 `if #available` 分支无法类型检查。

- [ ] **Step 2: 编译 + 全量测试**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: Build complete + 全部通过

- [ ] **Step 3: 渲染截图验证玻璃质感**

```bash
swift run TokscaleBar --render-png /tmp/glass-today.png --mock --period today --lang zh
swift run TokscaleBar --render-png /tmp/glass-week.png --mock --period week --lang en
```

人工查看两张截图：卡片应呈半透明玻璃质感而非灰底（本机 macOS 27 走原生路径）。

- [ ] **Step 4: Commit**

```bash
git add Sources/TokscaleBar/Theme.swift
git commit -m "feat: liquid glass cards with frosted fallback"
```

---

### Task 7: BarChart hover 高亮 + tooltip

**Files:**
- Modify: `Sources/TokscaleBar/Charts.swift`（`BarChart` 重写）
- Modify: `Sources/TokscaleBar/Tokscale.swift:453-459`（`monthlyCosts` 增加 tokens）
- Modify: `Sources/TokscaleBar/PopoverView.swift:330-386`（chartSection 传 labels/details）
- Modify: `Tests/TokscaleBarTests/TokscaleBarTests.swift:106-115`（monthlyCosts 测试补 tokens 断言）

**Interfaces:**
- Consumes: `Format.cost` / `Format.tokens`（调用方格式化）、`l10n.hourLabel/monthLabel`、已有 `shortDate`
- Produces:
  - `BarChart(values: [Double], highlight: Int? = nil, maxBarHeight: CGFloat = 60, labels: [String] = [], details: [String] = [])`
  - `TokscaleService.monthlyCosts(_:) -> [(month: String, cost: Double, tokens: Int)]`

- [ ] **Step 1: 更新 monthlyCosts 测试（失败先行）**

`Tests/TokscaleBarTests/TokscaleBarTests.swift:106-115` 的 `testMonthlyCostsGroupsAndOrdersByMonth` 改为：

```swift
    func testMonthlyCostsGroupsAndOrdersByMonth() {
        let days = [
            day("2026-08-31", tokens: 100, cost: 1),
            day("2026-07-01", tokens: 200, cost: 2),
            day("2026-08-01", tokens: 300, cost: 4),
        ]
        let months = TokscaleService.monthlyCosts(days)
        XCTAssertEqual(months.map(\.month), ["2026-07", "2026-08"])
        XCTAssertEqual(months.map(\.cost), [2, 5])
        XCTAssertEqual(months.map(\.tokens), [200, 400])
    }
```

（该文件顶部的 `day(_:)` helper 需确认签名支持 tokens 参数；`HeroDayOverDayTests` 的 helper 是 `day(_:tokens:cost:)`，照搬即可——若 `TokscaleBarTests.swift` 的 helper 没有 tokens 参数，把它改成 `day(_:tokens: Int = 0, cost: Double = 0)` 同样模式。）

Run: `swift test --filter testMonthlyCostsGroupsAndOrdersByMonth 2>&1 | tail -3`
Expected: 编译失败（tuple 无 `tokens` 成员）

- [ ] **Step 2: 扩展 monthlyCosts**

`Sources/TokscaleBar/Tokscale.swift:453-459` 改为：

```swift
    /// Per-calendar-month totals, ascending. yyyy-MM keys sort lexically,
    /// which is also chronological. Tokens ride along for chart tooltips.
    static func monthlyCosts(_ days: [DayUsage]) -> [(month: String, cost: Double, tokens: Int)] {
        var byMonth: [String: (cost: Double, tokens: Int)] = [:]
        for day in days {
            let key = String(day.date.prefix(7))
            byMonth[key, default: (0, 0)].cost += day.totals.cost
            byMonth[key, default: (0, 0)].tokens += day.totals.tokens
        }
        return byMonth.sorted { $0.key < $1.key }
            .map { (month: $0.key, cost: $0.value.cost, tokens: $0.value.tokens) }
    }
```

注意：`byMonth[key, default: (0, 0)].cost += ...` 这种对 dictionary default 的 tuple 成员修改，Swift 不支持链式两次求值——实际写法应为：

```swift
    static func monthlyCosts(_ days: [DayUsage]) -> [(month: String, cost: Double, tokens: Int)] {
        var byMonth: [String: (cost: Double, tokens: Int)] = [:]
        for day in days {
            let key = String(day.date.prefix(7))
            var bucket = byMonth[key] ?? (cost: 0, tokens: 0)
            bucket.cost += day.totals.cost
            bucket.tokens += day.totals.tokens
            byMonth[key] = bucket
        }
        return byMonth.sorted { $0.key < $1.key }
            .map { (month: $0.key, cost: $0.value.cost, tokens: $0.value.tokens) }
    }
```

Run: `swift test --filter testMonthlyCostsGroupsAndOrdersByMonth 2>&1 | tail -3`
Expected: PASS

- [ ] **Step 3: 重写 BarChart 支持 hover tooltip**

`Sources/TokscaleBar/Charts.swift` 的 `BarChart`（第 3-36 行）替换为：

```swift
/// Vertical bar chart for hourly or daily costs. Bars at `highlight` index use
/// the brand gradient. `labels`/`details` (same count as `values`) feed the
/// hover tooltip: title line + pre-formatted value line. Callers format
/// strings because the chart stays currency/locale-agnostic.
struct BarChart: View {
    let values: [Double]
    var highlight: Int? = nil
    var maxBarHeight: CGFloat = 60
    var labels: [String] = []
    var details: [String] = []

    @State private var hovering: Int?

    var body: some View {
        let peak = max(values.max() ?? 0, 0.0001)
        let corner: CGFloat = values.count > 12 ? 2.5 : 4
        HStack(alignment: .bottom, spacing: values.count > 12 ? 3 : 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                UnevenRoundedRectangle(topLeadingRadius: corner, bottomLeadingRadius: 1,
                                       bottomTrailingRadius: 1, topTrailingRadius: corner,
                                       style: .continuous)
                    .fill(style(for: index))
                    .frame(height: 4 + maxBarHeight * max(value / peak, 0))
                    .frame(maxWidth: .infinity)
                    .shadow(color: index == highlight ? Color.brand.opacity(0.5) : .clear,
                            radius: 5, y: 1)
                    .opacity(hovering == nil || hovering == index ? 1 : 0.45)
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 ? index : nil }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: values)
        .animation(.easeOut(duration: 0.1), value: hovering)
        .overlay(alignment: .top) { tooltip }
    }

    /// Floating readout above the hovered bar, clamped so it never clips the
    /// chart's left/right edge.
    @ViewBuilder
    private var tooltip: some View {
        if let index = hovering, values.indices.contains(index) {
            GeometryReader { geo in
                let barWidth = geo.size.width / CGFloat(max(values.count, 1))
                let centerX = barWidth * (CGFloat(index) + 0.5)
                VStack(spacing: 1) {
                    if labels.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 9, weight: .semibold))
                    }
                    if details.indices.contains(index) {
                        Text(details[index])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .fixedSize()
                .position(x: min(max(centerX, 50), max(geo.size.width - 50, 50)), y: 12)
                .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }

    private func style(for index: Int) -> AnyShapeStyle {
        // Hover promotes the touched bar to the brand gradient; the default
        // highlight (today/last) only applies when nothing is hovered.
        if index == hovering ?? highlight { return AnyShapeStyle(brandGradient) }
        return AnyShapeStyle(LinearGradient(
            colors: [Color.primary.opacity(0.2), Color.primary.opacity(0.1)],
            startPoint: .top, endPoint: .bottom
        ))
    }
}
```

- [ ] **Step 4: chartSection 传 labels/details**

`Sources/TokscaleBar/PopoverView.swift:330-386` 的 `chartSection`，把四个 `BarChart(...)` 调用分别改为：

```swift
                case .today:
                    BarChart(values: values,
                             highlight: Calendar.current.component(.hour, from: Date()),
                             maxBarHeight: 52,
                             labels: snapshot.hours.map { l10n.hourLabel($0.hour) },
                             details: values.map { cost($0) })
                    hourAxis
                case .week:
                    BarChart(values: values,
                             highlight: values.count - 1,
                             maxBarHeight: 52,
                             labels: snapshot.weekDays.map { shortDate($0.date) },
                             details: snapshot.weekDays.map {
                                 cost($0.totals.cost) + " · " + Format.tokens($0.totals.tokens, settings.unitStyle)
                             })
                    weekAxis(snapshot.weekDays)
                case .last30:
                    BarChart(values: values,
                             highlight: values.count - 1,
                             maxBarHeight: 52,
                             labels: snapshot.last30Days.map { shortDate($0.date) },
                             details: snapshot.last30Days.map {
                                 cost($0.totals.cost) + " · " + Format.tokens($0.totals.tokens, settings.unitStyle)
                             })
                    last30Axis(snapshot.last30Days)
                case .all:
                    BarChart(values: values,
                             highlight: values.count - 1,
                             maxBarHeight: 52,
                             labels: months.map { l10n.monthLabel($0.month) },
                             details: months.map {
                                 cost($0.cost) + " · " + Format.tokens($0.tokens, settings.unitStyle)
                             })
                    allAxis(months.map(\.month))
```

- [ ] **Step 5: 编译 + 全量测试 + 截图**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: Build complete + 全部通过

```bash
swift run TokscaleBar --render-png /tmp/chart-week.png --mock --period week
```

人工确认图表正常渲染（tooltip 是 hover 态，截图里看不到属预期；`--preview-window --mock` 里人工 hover 验证）。

- [ ] **Step 6: Commit**

```bash
git add Sources/TokscaleBar/Charts.swift Sources/TokscaleBar/Tokscale.swift Sources/TokscaleBar/PopoverView.swift Tests/TokscaleBarTests/TokscaleBarTests.swift
git commit -m "feat: chart bar hover tooltips with per-bar details"
```

---

### Task 8: 模型行点击展开明细

**Files:**
- Modify: `Sources/TokscaleBar/L10n.swift`（新增明细字段字符串）
- Modify: `Sources/TokscaleBar/PopoverView.swift`（`modelBreakdown` + `ModelRow`）

**Interfaces:**
- Consumes: `Report.Entry` 的 `input/output/cacheRead/cacheWrite/reasoning/messageCount`；`Format.tokens`；现有 `ModelRow`（`PopoverView.swift:564-614`）
- Produces: `L10n.detailInput/detailOutput/detailCacheRead/detailCacheWrite/detailReasoning/detailMessages`；PopoverView 的 `@State expandedEntry: String?`（entry 身份 = `"client|model"`）

- [ ] **Step 1: L10n 新增**

`Sources/TokscaleBar/L10n.swift` 的 `var byClient` 之后追加：

```swift
    // Entry detail grid
    var detailInput: String { zh ? "输入" : "Input" }
    var detailOutput: String { zh ? "输出" : "Output" }
    var detailCacheRead: String { zh ? "缓存读" : "Cache read" }
    var detailCacheWrite: String { zh ? "缓存写" : "Cache write" }
    var detailReasoning: String { zh ? "推理" : "Reasoning" }
    var detailMessages: String { zh ? "消息" : "Messages" }
```

- [ ] **Step 2: 手风琴状态 + ModelRow 展开**

a) `PopoverView` 的 `@State private var period` 旁加：

```swift
    @State private var expandedEntry: String?
```

b) `modelBreakdown`（`PopoverView.swift:444-457`）中 `ModelRow(...)` 调用改为：

```swift
                ForEach(Array(top.enumerated()), id: \.offset) { index, entry in
                    ModelRow(rank: index + 1, entry: entry, maxCost: maxCost,
                             tokensText: Format.tokens(entry.tokens, settings.unitStyle),
                             costText: cost(entry.cost),
                             expanded: expandedEntry == entry.stableID,
                             unitStyle: settings.unitStyle,
                             l10n: l10n,
                             onToggle: {
                                 withAnimation(.easeInOut(duration: 0.18)) {
                                     expandedEntry = expandedEntry == entry.stableID ? nil : entry.stableID
                                 }
                             })
                }
```

c) `Report.Entry` 需要 `stableID`——`Sources/TokscaleBar/Tokscale.swift` 的 `Report.Entry` 内（`var tokens` 之后）加：

```swift
        /// One client can serve the same model name, so identity needs both.
        var stableID: String { client + "|" + model }
```

d) `ModelRow`（`PopoverView.swift:564-614`）整体替换为：

```swift
/// One ranked model row: proportional cost bar underneath, lifts on hover,
/// and taps open a token-breakdown grid (input/output/cache/reasoning/messages).
private struct ModelRow: View {
    let rank: Int
    let entry: Report.Entry
    let maxCost: Double
    let tokensText: String
    let costText: String
    let expanded: Bool
    let unitStyle: UnitStyle
    let l10n: L10n
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(rank)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, alignment: .leading)
                Text(entry.model)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.client)
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(tokensText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Text(costText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 54, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: geo.size.width * entry.cost / maxCost)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.05 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .accessibilityAddTraits(.isButton)

            if expanded {
                detailGrid
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    /// Two-column token breakdown. Reasoning hides when the model reports none.
    private var detailGrid: some View {
        let rows: [(String, String)] = [
            (l10n.detailInput, Format.tokens(entry.input, unitStyle)),
            (l10n.detailOutput, Format.tokens(entry.output, unitStyle)),
            (l10n.detailCacheRead, Format.tokens(entry.cacheRead, unitStyle)),
            (l10n.detailCacheWrite, Format.tokens(entry.cacheWrite, unitStyle)),
        ] + (entry.reasoning.map { [(l10n.detailReasoning, Format.tokens($0, unitStyle))] } ?? [])
        + [(l10n.detailMessages, "\(entry.messageCount)")]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                         alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    Text(row.0)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 2)
                    Text(row.1)
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 3: 编译 + 测试 + 截图**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: Build complete + 全部通过

```bash
swift run TokscaleBar --render-png /tmp/models.png --mock --period week
```

- [ ] **Step 4: Commit**

```bash
git add Sources/TokscaleBar/L10n.swift Sources/TokscaleBar/PopoverView.swift Sources/TokscaleBar/Tokscale.swift
git commit -m "feat: expandable model rows with token breakdown"
```

---

### Task 9: 订阅回本 section + 行内编辑器

**Files:**
- Modify: `Sources/TokscaleBar/L10n.swift`（订阅/回本/编辑器字符串）
- Modify: `Sources/TokscaleBar/PopoverView.swift`（新 `roiSection`、订阅行、编辑器；usage section 标题改「配额」）

**Interfaces:**
- Consumes: `Subscription`/`Billing`/`CycleKey`/`ROI`（Task 1–2）、`SubscriptionStore`（Task 3）、`AppModel.cycleReports`/`subscriptionStore`（Task 5）、`Format.cost`、现有 `usageBar` 样式
- Produces: `L10n.roiTitle/quotas/addSubscription/subscriptionsEmpty/perMonth/cycleLine/toBreakEven/brokeEven/spendUnavailable/fieldName/fieldPrice/fieldBillingDay/dayOfMonth/fieldKeywords/keywordsFooter/deleteSubscription`；无新类型——全部是 PopoverView 私有视图

- [ ] **Step 1: L10n 新增**

`Sources/TokscaleBar/L10n.swift` Task 8 的明细字符串之后追加：

```swift
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
    var keywordsFooter: String {
        zh ? "逗号分隔，匹配模型/客户端名；留空算全部"
           : "Comma-separated, matched against model/client names; empty matches everything"
    }
    var deleteSubscription: String { zh ? "删除订阅" : "Delete subscription" }
```

并把现有 `var subscriptions`（`L10n.swift:112`）的注释改为仅 ROI section 使用——不删 key，usage section 改用 `quotas`：

`Sources/TokscaleBar/PopoverView.swift:185` 的 `sectionTitle(l10n.subscriptions)` 改为 `sectionTitle(l10n.quotas)`。

- [ ] **Step 2: ROI section 骨架 + 数据胶水**

`PopoverView` 的 `@State` 区加：

```swift
    @State private var expandedSubscription: UUID?
```

`dashboard` 里 `heroCard(...)` 之后、`subscriptionsCard` 之前插入 `roiSection`。

私有方法（放在 `// MARK: Subscriptions` 注释块前，自成 `// MARK: - ROI`）：

```swift
    // MARK: - ROI

    private static let roiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Dates.calendar
        f.dateFormat = "M/d"
        return f
    }()

    private func cycleKey(for sub: Subscription, now: Date = Date()) -> CycleKey {
        let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: now)
        return CycleKey(since: Dates.dayString(cycle.start), until: Dates.dayString(now))
    }

    /// nil = this window's fetch failed or hasn't landed yet.
    private func cycleSpend(for sub: Subscription) -> Double? {
        guard let report = model.cycleReports[cycleKey(for: sub)] else { return nil }
        return ROI.matchedCost(report.entries, keywords: sub.keywords)
    }

    private func priceText(_ sub: Subscription) -> String {
        let amount = sub.currency == .cny ? sub.price : sub.price
        return "\(sub.currency.symbol)\(amount.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", amount) : String(format: "%.2f", amount))\(l10n.perMonth)"
    }

    @ViewBuilder
    private var roiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(l10n.roiTitle)
                Spacer()
                Button(action: addSubscription) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(l10n.addSubscription)
            }
            if model.subscriptionStore.subscriptions.isEmpty {
                Text(l10n.subscriptionsEmpty)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.subscriptionStore.subscriptions) { sub in
                        subscriptionRow(sub)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 12)
    }

    private func addSubscription() {
        let sub = Subscription(name: "", price: 20, currency: settings.currency,
                               billingDay: 1, keywords: [])
        model.subscriptionStore.add(sub)
        expandedSubscription = sub.id
        model.refresh()
    }
```

- [ ] **Step 3: 订阅行（徽章 + 进度条）**

```swift
    private func subscriptionRow(_ sub: Subscription) -> some View {
        let spend = cycleSpend(for: sub)
        let multiple = spend.map {
            ROI.multiple(costUSD: $0, price: sub.price, currency: sub.currency,
                         rate: settings.usdToCnyRate)
        }
        let expanded = expandedSubscription == sub.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(sub.name.isEmpty ? l10n.fieldName : sub.name)
                    .font(.system(size: 11, weight: .semibold))
                Text(priceText(sub))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                if let multiple {
                    Text(String(format: "×%.1f", multiple))
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(multiple >= 1 ? Color.brand : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background((multiple >= 1 ? Color.brand : .orange).opacity(0.12), in: Capsule())
                } else {
                    Text(l10n.spendUnavailable)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            if let spend, let multiple {
                roiBar(multiple: min(multiple, 1), reached: multiple >= 1)
                let cycle = Billing.currentCycle(billingDay: sub.billingDay, now: Date())
                let daysLeft = max(0, Dates.calendar.dateComponents(
                    [.day], from: Dates.calendar.startOfDay(for: Date()),
                    to: Dates.calendar.startOfDay(for: cycle.end)).day ?? 0)
                let startText = Self.roiDateFormatter.string(from: cycle.start)
                let endText = Self.roiDateFormatter.string(
                    from: Dates.calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end)
                Text(l10n.cycleLine(startText, endText, daysLeft: daysLeft)
                     + " · " + l10n.cycleSpend + " "
                     + cost(spend))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if expanded {
                subscriptionEditor(sub)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedSubscription = expanded ? nil : sub.id
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    /// Payback progress: cost vs price. Green once the sub paid for itself.
    private func roiBar(multiple: Double, reached: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(reached ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.orange))
                    .frame(width: max(4, geo.size.width * multiple))
            }
        }
        .frame(height: 4)
    }
```

注意：`priceText` 里简化分支其实两侧相同——直接：

```swift
    private func priceText(_ sub: Subscription) -> String {
        let formatted = sub.price.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", sub.price)
            : String(format: "%.2f", sub.price)
        return "\(sub.currency.symbol)\(formatted)\(l10n.perMonth)"
    }
```

- [ ] **Step 4: 行内编辑器**

```swift
    /// Live-editing form: every change writes straight to the store and
    /// triggers a refetch so the badge updates immediately.
    private func subscriptionEditor(_ sub: Subscription) -> some View {
        let binding = Binding<Subscription>(
            get: { model.subscriptionStore.subscriptions.first { $0.id == sub.id } ?? sub },
            set: { model.subscriptionStore.update($0) }
        )
        let keywordText = Binding<String>(
            get: { binding.wrappedValue.keywords.joined(separator: ", ") },
            set: { text in
                var copy = binding.wrappedValue
                copy.keywords = text.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                model.subscriptionStore.update(copy)
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
            editorRow(l10n.fieldName) {
                TextField("Claude Pro", text: binding.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { model.refresh() }
            }
            editorRow(l10n.fieldPrice) {
                TextField("20", value: binding.price, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onSubmit { model.refresh() }
                Picker("", selection: binding.currency) {
                    ForEach(AppCurrency.allCases) { Text($0.symbol).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 84)
            }
            editorRow(l10n.fieldBillingDay) {
                Stepper(l10n.dayOfMonth(binding.wrappedValue.billingDay),
                        value: binding.billingDay, in: 1...31)
                    .font(.system(size: 11))
                    .onChange(of: binding.wrappedValue.billingDay) { _, _ in model.refresh() }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.fieldKeywords)
                    .font(.system(size: 10))
                TextField("claude, anthropic", text: keywordText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { model.refresh() }
                Text(l10n.keywordsFooter)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                Button(l10n.deleteSubscription) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedSubscription = nil
                        model.subscriptionStore.remove(id: sub.id)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func editorRow<Content: View>(_ title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10))
                .frame(width: 44, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
    }
```

`onChange(of:)` 双参数闭包是 macOS 14+ API——部署目标是 macOS 13，改用旧式单参数闭包：` .onChange(of: binding.wrappedValue.billingDay) { _ in model.refresh() }`。

- [ ] **Step 5: 编译 + 测试 + 截图**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: Build complete + 全部通过

```bash
swift run TokscaleBar --render-png /tmp/roi-today.png --mock --period today --lang zh
swift run TokscaleBar --render-png /tmp/roi-en.png --mock --period today --lang en
```

人工确认：「订阅回本」卡片出现，Claude Pro 绿色 ×3.x 徽章 + 满格进度条，Kimi 橙色 ×0.x；配额区标题为「配额」。

- [ ] **Step 6: Commit**

```bash
git add Sources/TokscaleBar/L10n.swift Sources/TokscaleBar/PopoverView.swift
git commit -m "feat: subscription payback section with inline editor"
```

---

### Task 10: 全量验证

**Files:**
- 无新文件；验证 + 必要时修小问题

- [ ] **Step 1: 全量构建与测试**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: Build complete；全部测试通过（69 原有 + 26 新增 = 95，2 skipped）

- [ ] **Step 2: 截图矩阵**

```bash
for p in today week last30 all; do
  swift run TokscaleBar --render-png "/tmp/final-$p.png" --mock --period "$p" --lang zh
done
swift run TokscaleBar --render-png /tmp/final-en.png --mock --period today --lang en
swift run TokscaleBar --render-png /tmp/final-empty.png --state empty
```

人工逐张检查：玻璃卡片、徽章颜色、tooltip 布局空间、空态不炸版。

- [ ] **Step 3: 交互手测**

```bash
swift run TokscaleBar --preview-window --mock
```

手测清单：
- hover 图表柱子 → 高亮 + tooltip，贴边不裁剪
- 点击模型行 → 展开明细，点另一行 → 手风琴切换，再点 → 收起
- 订阅区 + → 新增空订阅并展开编辑器；改名称/价格/账单日/关键词 → 立即保存（重开 preview 后仍在）
- 删除订阅 → 行消失，badge 区收缩
- hero 卡点击仍切换 cost/tokens；设置页正常往返

- [ ] **Step 4: 实机验证（真实 tokscale 数据）**

```bash
swift run TokscaleBar --preview-window
```

确认真实订阅数据加载、倍数计算合理；无 tokscale 数据时错误横幅正常。

- [ ] **Step 5: 更新 README（若提及 UI 结构）**

检查 `README.md` 是否有需要同步的功能描述/截图列表；有则更新，无则跳过。

---

## Self-Review 记录

- **Spec 覆盖**：玻璃双路径（T6）✓ 配色收敛（T6 卡片中性化 + T9 徽章语义色）✓ 图表 tooltip（T7）✓ 模型行展开（T8）✓ 订阅行展开+编辑（T9）✓ 订阅模型/账单日/关键词（T1–3）✓ 周期查询并发+去重（T5）✓ 配额区改名（T9 Step 1）✓ Mock 预览（T5）✓ 测试（T1/2/3/5/7）✓
- **类型一致性**：`CycleKey`（T1 定义，T5/T9 使用）✓；`ROI.matchedCost(_:keywords:)` 签名一致 ✓；`monthlyCosts` 三元组在 T7 统一定义与消费 ✓；`stableID` 在 T8 定义并使用 ✓。
- **已知遗留**：`glassEffect` 在 popover 内的真实观感以 T6 Step 3 截图为准，若原生材质过重，备选方案是把 `.regular` 换成 `.clear` 或回退 vibrancy——属视觉微调，不改架构。
