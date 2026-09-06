import SwiftUI

enum Period: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @State private var period: Period

    init(model: AppModel, settings: Settings, initialPeriod: Period = .today) {
        self.model = model
        self.settings = settings
        _period = State(initialValue: initialPeriod)
    }

    private var l10n: L10n { settings.l10n }

    private func cost(_ value: Double) -> String {
        Format.cost(value, currency: settings.currency, rate: settings.usdToCnyRate)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showSettings {
                SettingsView(settings: settings, showSettings: $model.showSettings)
            } else {
                dashboard
            }
        }
        .frame(width: 324)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        // Content grows with period/model counts; scroll past 620pt instead of
        // letting the popover overflow the screen.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let snapshot = model.snapshot {
                    // A failed refresh keeps the last good frame; the error
                    // degrades to a banner instead of replacing the dashboard.
                    periodPicker
                    heroCard(report, snapshot: snapshot)
                    chartSection(snapshot)
                    modelBreakdown(report)
                    clientShare(report)
                    if let error = model.lastError {
                        errorCard(error)
                    }
                } else if let error = model.lastError {
                    errorCard(error)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                footer
            }
            .padding(14)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 620)
        .scrollIndicators(.automatic)
    }

    private var report: Report {
        guard let snapshot = model.snapshot else { return .empty }
        switch period {
        case .today: return snapshot.today
        case .week: return snapshot.week
        case .month: return snapshot.month
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(brandGradient)
            Text("Tokscale")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { model.showSettings = true } }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
    }

    private var periodPicker: some View {
        Picker("", selection: $period) {
            ForEach(Period.allCases) { Text(l10n.periodLabel($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    // MARK: Hero

    private func heroCard(_ report: Report, snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.heroTitle(period))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(heroDateLabel(snapshot))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cost(report.totalCost))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if period == .today, let delta = dayOverDay(snapshot.weekDays) {
                    Label(deltaText(delta), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.16), in: Capsule())
                        .help(l10n.vsYesterday)
                }
            }
            HStack(spacing: 8) {
                heroStat(icon: "number", text: l10n.tokensPill(Format.tokens(report.totalTokens, settings.unitStyle)))
                heroStat(icon: "bubble.left.and.bubble.right", text: l10n.messagesPill(report.totalMessages))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.brandDeep.opacity(0.35), radius: 8, y: 4)
    }

    private func heroDateLabel(_ snapshot: Snapshot) -> String {
        let locale = l10n.locale
        switch period {
        case .today:
            return Date.now.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        case .week:
            return "\(shortDate(snapshot.weekDays.first?.date)) – \(shortDate(snapshot.weekDays.last?.date))"
        case .month:
            return Date.now.formatted(.dateTime.year().month(.abbreviated).locale(locale))
        }
    }

    private func shortDate(_ date: String?) -> String {
        guard let date, date.count >= 10 else { return "" }
        let md = String(date.suffix(5))
        return settings.language == .zh ? md.replacingOccurrences(of: "-", with: "/") : md
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

    // MARK: Chart

    private func chartSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(period == .today ? l10n.hourlyChart : l10n.dailyChart)
                Spacer()
                Text(chartCaption(snapshot))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            switch period {
            case .today:
                BarChart(values: snapshot.hours.map(\.cost),
                         highlight: Calendar.current.component(.hour, from: Date()),
                         maxBarHeight: 52)
                hourAxis
            case .week:
                BarChart(values: snapshot.weekDays.map(\.totals.cost),
                         highlight: snapshot.weekDays.count - 1,
                         maxBarHeight: 52)
                weekAxis(snapshot.weekDays)
            case .month:
                let values = snapshot.monthDays.map(\.totals.cost)
                if values.count <= 1 {
                    // AreaChart needs at least two points; on the 1st of the
                    // month show a single bar instead of a blank canvas.
                    BarChart(values: values, highlight: 0, maxBarHeight: 52)
                } else {
                    AreaChart(values: values)
                        .frame(height: 64)
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chartCaption(_ snapshot: Snapshot) -> String {
        let locale = l10n.locale
        switch period {
        case .today:
            return Date.now.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        case .week:
            return "\(shortDate(snapshot.weekDays.first?.date)) – \(shortDate(snapshot.weekDays.last?.date))"
        case .month:
            return Date.now.formatted(.dateTime.month(.abbreviated).locale(locale))
        }
    }

    private var hourAxis: some View {
        HStack {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(l10n.hourLabel(hour))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                if hour != 18 { Spacer() }
            }
        }
    }

    private func weekAxis(_ week: [DayUsage]) -> some View {
        HStack(spacing: 8) {
            ForEach(week, id: \.date) { day in
                Text(weekdayLetter(day.date))
                    .font(.system(size: 8, weight: isToday(day.date) ? .bold : .regular))
                    .foregroundStyle(isToday(day.date) ? .primary : .tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Models

    private func modelBreakdown(_ report: Report) -> some View {
        let top = report.entries.sorted { $0.cost > $1.cost }.prefix(5)
        let maxCost = max(top.map(\.cost).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.topModels(top.count))
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
                        Text(Format.tokens(entry.tokens, settings.unitStyle))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(cost(entry.cost))
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

    // MARK: Clients

    private func clientShare(_ report: Report) -> some View {
        var byClient: [String: Double] = [:]
        for entry in report.entries {
            byClient[entry.client, default: 0] += entry.cost
        }
        let ranked = byClient.sorted { $0.value > $1.value }
        let top = ranked.prefix(5).map { (client: $0.key, cost: $0.value) }
        let rest = ranked.dropFirst(5).reduce(0.0) { $0 + $1.value }
        let shares = rest > 0 ? top + [(client: l10n.other, cost: rest)] : top

        return Group {
            if !shares.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(l10n.byClient)
                    ClientShareView(shares: shares, currency: settings.currency, rate: settings.usdToCnyRate)
                }
            }
        }
    }

    // MARK: Footer & misc

    private var footer: some View {
        HStack {
            if let updated = model.lastUpdated {
                Label(updated.formatted(.dateTime.hour().minute().locale(l10n.locale)), systemImage: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
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
            .help(l10n.quit)
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
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func isToday(_ date: String) -> Bool {
        date == Self.dayFormatter.string(from: Date())
    }

    private func weekdayLetter(_ date: String) -> String {
        guard let d = Self.dayFormatter.date(from: date) else { return "" }
        return l10n.weekdayLetters[Calendar.current.component(.weekday, from: d) - 1]
    }
}

extension Report {
    static let empty = Report(
        entries: [], totalInput: 0, totalOutput: 0,
        totalCacheRead: 0, totalCacheWrite: 0, totalMessages: 0, totalCost: 0
    )
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Binding var showSettings: Bool

    private var l10n: L10n { settings.l10n }

    var body: some View {
        ScrollView {
            content
                .padding(14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 620)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = false } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text(l10n.settingsTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            VStack(spacing: 0) {
                settingRow(l10n.languageLabel) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                rowDivider
                settingRow(l10n.numberUnits) {
                    Picker("", selection: $settings.unitStyle) {
                        ForEach(UnitStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                rowDivider
                settingRow(l10n.currencyLabel) {
                    Picker("", selection: $settings.currency) {
                        ForEach(AppCurrency.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                if settings.currency == .cny {
                    rowDivider
                    settingRow(l10n.rateLabel) {
                        TextField("7.2", value: $settings.usdToCnyRate, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }
                rowDivider
                settingRow(l10n.menuBarShows) {
                    Picker("", selection: $settings.menuMetric) {
                        ForEach(MenuMetric.allCases) { Text(l10n.metricLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow(l10n.refreshEvery) {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text(l10n.intervalLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow(l10n.launchAtLogin) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.tokscalePath)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                TextField(l10n.autoDetect, text: $settings.tokscalePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            Spacer(minLength: 0)

            Text(l10n.privacyNote)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
