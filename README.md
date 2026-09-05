# TokscaleBar

一个住在 macOS 菜单栏里的 tokscale 用量监视器。

![platform](https://img.shields.io/badge/macOS-13%2B-blue)

## 功能

- **菜单栏实时数字**：显示今日花费（可切换为 Tokens / 消息数）
- **点击弹出仪表盘**，三个时段页签（今天 / 近 7 天 / 本月）：
  - 渐变花费大卡片（Tokens、消息数胶囊，今日附「较昨日」涨跌）
  - 今天 → 24 小时分时段柱状图（当前小时高亮）
  - 近 7 天 → 每日柱状图（今天高亮）
  - 本月 → 每日花费平滑面积图
  - 模型 TOP 5 明细（模型、客户端、Tokens、费用、占比底条）
  - 客户端占比堆叠条 + 图例
- **中英双语**：设置里一键切换 中文 / English（默认跟随系统）
- **数字单位**：英制 K/M/B 或 中制 千/万/亿
- **自定义设置**（齿轮进入）：
  - 菜单栏显示内容：费用 / Tokens / 消息数
  - 刷新间隔：1 / 5 / 15 分钟
  - 登录时启动
  - tokscale 二进制路径（默认自动检测 `/opt/homebrew/bin` 和 `/usr/local/bin`）

## 构建与运行

需要 Xcode 命令行工具和已安装的 [tokscale](https://github.com/tokscale/tokscale) CLI。

```sh
./build-app.sh       # 编译并打包 TokscaleBar.app
open TokscaleBar.app # 启动（无 Dock 图标，只看菜单栏）
```

开发时也可以直接 `swift run` 前台运行调试。

## 原理

纯 AppKit + SwiftUI，零第三方依赖。通过 `Process` 调用本机
`tokscale --json --today`、`--json --month` 和 `tokscale graph --week`，
解析 JSON 后刷新界面；数据完全留在本地。

## 文件结构

```
Package.swift                     SPM 包定义
Info.plist                        App 配置（LSUIElement = 无 Dock 图标）
build-app.sh                      一键打包脚本
Sources/TokscaleBar/
├── main.swift                    入口、AppDelegate、状态栏与定时刷新
├── Tokscale.swift                tokscale 并发抓取、JSON 模型、数字格式化
├── Settings.swift                用户设置（UserDefaults + 登录项）
├── L10n.swift                    中英双语文案与语言/单位枚举
├── Charts.swift                  柱状图、面积图、客户端占比组件
└── PopoverView.swift             仪表盘（时段页签）与设置界面
```

调试参数：`--preview-window` 窗口预览；`--render-png 路径 [--period today|week|month] [--lang zh|en] [--units western|chinese]` 无界面渲染截图。
