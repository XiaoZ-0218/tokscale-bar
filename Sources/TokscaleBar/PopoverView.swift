import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(settings: settings, showSettings: $showSettings)
            } else {
                dashboard
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = model.lastError {
                errorCard(error)
            } else if let snapshot = model.snapshot {
                todayCard(snapshot.today)
                weekChart(snapshot.week)
                totalsRow(snapshot)
                modelBreakdown(snapshot.today)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            Label("Tokscale", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: { withAnimation { showSettings = true } }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func todayCard(_ today: Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日花费")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.cost(today.totalCost))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 12) {
                Label(Format.tokens(today.totalTokens), systemImage: "number")
                Label("\(today.totalMessages)", systemImage: "bubble.left.and.bubble.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func weekChart(_ week: [DayUsage]) -> some View {
        let maxCost = max(week.map(\.totals.cost).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week, id: \.date) { day in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isToday(day.date) ? Color.accentColor : Color.accentColor.opacity(0.35))
                            .frame(height: 4 + 56 * max(day.totals.cost / maxCost, 0))
                        Text(weekdayLetter(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.date)  \(Format.cost(day.totals.cost))")
                }
            }
        }
    }

    private func totalsRow(_ snapshot: Snapshot) -> some View {
        HStack {
            totalItem(title: "近 7 天", value: Format.cost(snapshot.week.reduce(0) { $0 + $1.totals.cost }))
            Divider().frame(height: 24)
            totalItem(title: "本月", value: Format.cost(snapshot.month.totalCost))
            Divider().frame(height: 24)
            totalItem(title: "本月 Tokens", value: Format.tokens(snapshot.month.totalTokens))
        }
    }

    private func totalItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.medium).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func modelBreakdown(_ today: Report) -> some View {
        let top = today.entries.sorted { $0.cost > $1.cost }.prefix(4)
        return VStack(alignment: .leading, spacing: 6) {
            Text("今日模型")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(entry.model)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.client)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.tokens(entry.tokens))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text(Format.cost(entry.cost))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = model.lastUpdated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorCard(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func isToday(_ date: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return date == formatter.string(from: Date())
    }

    private func weekdayLetter(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return "" }
        let letters = ["日", "一", "二", "三", "四", "五", "六"]
        return letters[Calendar.current.component(.weekday, from: d) - 1]
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: { withAnimation { showSettings = false } }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("设置").font(.headline)
                Spacer()
            }

            settingRow("菜单栏显示") {
                Picker("", selection: $settings.menuMetric) {
                    ForEach(MenuMetric.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            settingRow("刷新间隔") {
                Picker("", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            settingRow("登录时启动") {
                Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("tokscale 路径")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("留空自动检测", text: $settings.tokscalePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Text("修改立即生效。菜单栏数据来自 tokscale CLI 的本地统计。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }
}
