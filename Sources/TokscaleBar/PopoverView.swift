import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let brand = Color(hex: 0x30D158)
    static let brandDeep = Color(hex: 0x0E9F6E)
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @State private var showSettings = false

    private let brandGradient = LinearGradient(
        colors: [Color.brand, Color.brandDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(settings: settings, showSettings: $showSettings)
            } else {
                dashboard
            }
        }
        .frame(width: 312)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = model.lastError {
                errorCard(error)
            } else if let snapshot = model.snapshot {
                heroCard(snapshot.today, week: snapshot.week)
                weekChart(snapshot.week)
                totalsRow(snapshot)
                modelBreakdown(snapshot.today)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(brandGradient)
            Text("Tokscale")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = true } }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: Hero

    private func heroCard(_ today: Report, week: [DayUsage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日花费")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(Date.now, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.cost(today.totalCost))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let delta = dayOverDay(week) {
                    Label(deltaText(delta), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.16), in: Capsule())
                        .help("较昨日")
                }
            }
            HStack(spacing: 8) {
                heroStat(icon: "number", text: "\(Format.tokens(today.totalTokens)) tokens")
                heroStat(icon: "bubble.left.and.bubble.right", text: "\(today.totalMessages) 条消息")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.brandDeep.opacity(0.35), radius: 8, y: 4)
    }

    private func heroStat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: Week chart

    private func weekChart(_ week: [DayUsage]) -> some View {
        let maxCost = max(week.map(\.totals.cost).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("近 7 天")
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week, id: \.date) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barStyle(for: day))
                            .frame(height: 6 + 54 * max(day.totals.cost / maxCost, 0))
                            .padding(.horizontal, 3)
                        Text(weekdayLetter(day.date))
                            .font(.system(size: 8, weight: isToday(day.date) ? .bold : .regular))
                            .foregroundStyle(isToday(day.date) ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.date)  \(Format.cost(day.totals.cost))")
                }
            }
        }
    }

    private func barStyle(for day: DayUsage) -> AnyShapeStyle {
        if isToday(day.date) {
            return AnyShapeStyle(brandGradient)
        }
        return AnyShapeStyle(LinearGradient(
            colors: [Color.brandDeep.opacity(0.34), Color.brandDeep.opacity(0.18)],
            startPoint: .top, endPoint: .bottom
        ))
    }

    /// Percent change of today vs. yesterday, nil when yesterday had no spend.
    private func dayOverDay(_ week: [DayUsage]) -> Double? {
        guard week.count >= 2 else { return nil }
        let yesterday = week[week.count - 2].totals.cost
        let today = week[week.count - 1].totals.cost
        guard yesterday > 0.005 else { return nil }
        return (today - yesterday) / yesterday
    }

    private func deltaText(_ delta: Double) -> String {
        String(format: "%+.0f%%", delta * 100)
    }

    // MARK: Totals

    private func totalsRow(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 0) {
            totalItem(title: "7 天花费", value: Format.cost(snapshot.week.reduce(0) { $0 + $1.totals.cost }))
            totalDivider
            totalItem(title: "本月花费", value: Format.cost(snapshot.month.totalCost))
            totalDivider
            totalItem(title: "本月 Tokens", value: Format.tokens(snapshot.month.totalTokens))
        }
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private func totalItem(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1, height: 26)
    }

    // MARK: Models

    private func modelBreakdown(_ today: Report) -> some View {
        let top = today.entries.sorted { $0.cost > $1.cost }.prefix(4)
        let maxCost = max(top.map(\.cost).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("今日模型")
            VStack(spacing: 2) {
                ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        Text(entry.model)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(entry.client)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.brandDeep.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.brandDeep)
                        Spacer(minLength: 4)
                        Text(Format.tokens(entry.tokens))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(Format.cost(entry.cost))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.brandDeep.opacity(0.07))
                                .frame(width: geo.size.width * entry.cost / maxCost)
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer & misc

    private var footer: some View {
        HStack {
            if let updated = model.lastUpdated {
                Label(updated.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func errorCard(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var cardBackground: Color {
        .primary.opacity(0.04)
    }

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = false } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text("设置")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            VStack(spacing: 0) {
                settingRow("菜单栏显示") {
                    Picker("", selection: $settings.menuMetric) {
                        ForEach(MenuMetric.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow("刷新间隔") {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow("登录时启动") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("TOKSCALE 路径")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                TextField("留空自动检测", text: $settings.tokscalePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            Spacer(minLength: 0)

            Text("数据来自本机 tokscale CLI，全部留在本地。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(minHeight: 280)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 11))
            Spacer()
            content()
        }
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
    }
}
