# 液态玻璃 UI + 交互详情 + 订阅回本倍数 — 设计文档

日期：2026-09-20
状态：已确认（用户在头脑风暴中逐项确认：多订阅分别计算、自定义账单日、关键词可编辑匹配、双路径玻璃、全元素详情、路线 A 渐进增强）

## 背景

TokscaleBar 是一个 macOS 菜单栏应用（SwiftUI popover，部署目标 macOS 13），展示 tokscale CLI 的花费/token 用量。当前痛点：

1. 配色丑 —— 大面积灰底卡片 + 绿色渐变标题，视觉沉闷。
2. 交互少 —— 图表和列表纯展示，无法查看单项详情。
3. 没有订阅概念 —— 用户付了订阅费（如 Claude Pro $20/月），看不到"本周期用回了多少倍"。

## 需求决策（已与用户确认）

| 决策点 | 结论 |
|---|---|
| 订阅结构 | 多个订阅，各自填写、分别计算回本倍数 |
| 周期界定 | 每个订阅自定义账单日（1–31），周期 = 最近账单日到下个账单日 |
| 花费归集 | 关键词匹配 model/client 名，关键词可编辑，默认取名称小写 |
| 玻璃实现 | 双路径：macOS 26+ 原生 Liquid Glass，低版本 vibrancy + 手写高光回退；部署目标保持 macOS 13 |
| 详情交互 | 全部元素：图表柱 hover tooltip、模型行点击展开、订阅行点击展开 |
| 实现路线 | A. 渐进增强：Theme 层 → 订阅模块 → 交互层，视图结构不重排 |

## 1. 视觉：液态玻璃主题（双路径）

- 新增 `glassCard(radius:)` 修饰符替换现有 `card()`：
  - macOS 26+：原生 `glassEffect(.regular, in:)`（确切 API 形态以本机 Xcode 27 编译验证为准；备选 `NSGlassEffectView` 桥接）。
  - 回退（macOS 13–25）：`NSVisualEffectView`/语义色底 + 顶部 1px 白色高光渐变（opacity ~0.1→0）+ 0.5pt 细描边，模拟玻璃边缘折射。
- Popover 大背景保留 `PopoverBackground`（NSVisualEffectView `.popover`），在 macOS 26+ 上系统材质自动呈现玻璃质感。
- 配色收敛：中性玻璃底为主；品牌绿（`Color.brand`）只用于点睛——图表高亮柱、回本达标徽章、正向语义。回本倍数 <1 用橙色。文字/数字走系统语义色（`.primary`/`.secondary`/`.tertiary`），深浅色模式自适应。
- 控件：macOS 26+ 按钮用 `.glass` 样式；回退路径 hover 淡入底色。可点元素统一 hover 反馈（亮度微升）。

## 2. 交互详情

- **图表 tooltip**：`BarChart` 增加可选 `labels: [String]`（轴标签）与 `details: [String]?`（tooltip 副行，如 tokens）。柱子 hover 时增亮/上浮，tooltip 浮于柱上方，贴近卡片边缘时水平翻转防止溢出；零值柱显示"无用量"语义。
- **模型行**：点击行内展开明细（输入/输出/缓存读/缓存写/推理 tokens、消息数），父视图持有 `expandedEntryID`，手风琴式单行展开。
- **订阅行**：点击展开 = 回本明细（周期范围、已匹配花费、价格、进度条）+ 编辑表单。
- Hero 卡片保持现有点击切换 cost/tokens。

## 3. 订阅与回本倍数

### 数据模型（新文件 `Sources/TokscaleBar/Subscription.swift`）

```swift
struct Subscription: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var price: Double
    var currency: AppCurrency  // 价格币种，独立于显示货币
    var billingDay: Int        // 1...31
    var keywords: [String]     // 小写包含匹配 entry.model / entry.client；空数组 = 匹配全部
}
```

`SubscriptionStore: ObservableObject`，UserDefaults 存 JSON 数组；遵循 `Settings.persists` 同款开关（mock / render-png 不写盘）。

### 周期数学（纯函数，注入 now 便于测试）

```swift
struct BillingCycle: Equatable { let start: Date; let end: Date } // [start, end)
static func currentCycle(billingDay: Int, now: Date, calendar: Calendar) -> BillingCycle
```

- 起点 = 最近的 D 日（含今天）；D 超过当月天数 clamp 到月末（2 月 31 → 28）。`now` 在本月 D 日之前 → 起点取上月 D。
- 终点 = 下一个周期的起点；每月独立 clamp（1 月 31 的订阅：2 月起点 2/28，3 月起点 3/31）。

### 回本倍数

```swift
static func matchedCost(entries: [Report.Entry], keywords: [String]) -> Double
static func multiple(costUSD: Double, price: Double, currency: AppCurrency, rate: Double) -> Double
```

- 匹配：keyword 小写后作为子串匹配 `entry.model` 或 `entry.client`；空 keywords 匹配全部。
- 倍数 = 周期内匹配花费(USD) ÷ 订阅价(USD)；CNY 价格先按 `rate` 折算成 USD。

### 数据获取

- `TokscaleService` 公开 `fetchReport(since:until:) -> Report`（复用现有 `run`/`decode`）。
- `AppModel.refresh()` 增加第三路并发：对每个订阅算 `currentCycle`，按 (start, end) 去重窗口，每窗口一次查询，结果存 `cycleReports: [CycleKey: Report]`（`CycleKey: Hashable`）。
- 单窗口失败只影响对应订阅卡片（显示"花费数据不可用"），不污染主仪表盘。
- Mock：`Mock.subscriptions` + 对应 cycle reports，`--mock`/`--render-png` 可直接预览。

### UI 位置

- Hero 卡下方新增「订阅回本」section：每行 = 名称 + 价格 + 倍数徽章（×2.4，≥1 绿 / <1 橙）+ 迷你进度条（周期花费 vs 订阅价）。头部 "+" 添加；空态显示引导文案。
- 点击行展开：回本明细 + 编辑表单（名称、价格+币种选择、账单日 1–31、关键词逗号分隔、删除按钮）。
- 现有 `tokscale usage` 配额区保留原样，标题由「订阅」改为「配额」以区分（L10n 新增 key）。

## 4. 文件改动

| 文件 | 改动 |
|---|---|
| `Sources/TokscaleBar/Theme.swift` | 玻璃样式系统（`glassCard`）、配色收敛 |
| `Sources/TokscaleBar/Subscription.swift`（新） | 模型、周期数学、ROI 计算、`SubscriptionStore` |
| `Sources/TokscaleBar/Tokscale.swift` | 公开 `fetchReport(since:until:)` |
| `Sources/TokscaleBar/main.swift` | AppModel 接入 Store + 周期报表并发拉取（`cycleReports`） |
| `Sources/TokscaleBar/PopoverView.swift` | 订阅回本 section、行展开交互、tooltip 接线、`card()` → `glassCard()` |
| `Sources/TokscaleBar/Charts.swift` | BarChart hover 高亮 + tooltip |
| `Sources/TokscaleBar/L10n.swift` | 新增中英字符串（订阅/回本/配额/编辑表单） |
| `Sources/TokscaleBar/Mock.swift` | 订阅 mock 数据 |
| `Tests/TokscaleBarTests/` | 周期 clamp/跨月/跨年、关键词匹配、倍数换算、Store 读写 round-trip |

## 5. 验证

- `swift build && swift test`
- `--mock --render-png <path>` 渲染各 period 截图检查视觉
- `--preview-window --mock` 手动验证 hover/点击/编辑交互

## 风险与对策

1. macOS 26 玻璃 API 确切形态未验证 → 先写最小编译探针确认 `glassEffect` 可用性，再铺开；回退路径始终存在。
2. 每订阅多一次 tokscale 子进程查询（~3s）→ 并发执行 + 窗口去重；跟随现有 refreshInterval，不加额外定时器。
3. Popover 内 tooltip 定位 → 用 overlay + 固定坐标系，不做跨窗口浮层。
