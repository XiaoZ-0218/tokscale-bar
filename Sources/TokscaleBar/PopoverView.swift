import SwiftUI

enum Period: String, CaseIterable, Identifiable {
    case today, week, last30
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
        .background(PopoverBackground())
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
                    // It sits above the hero so it's visible without scrolling.
                    periodPicker
                    if let error = model.lastError {
                        errorCard(error)
                    }
                    heroCard(report, snapshot: snapshot)
                    chartSection(snapshot)
                    if !report.entries.isEmpty {
                        modelBreakdown(report)
                        clientShare(report)
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
        case .last30: return snapshot.last30
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l10n.heroTitle(period))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text(heroDateLabel(snapshot))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cost(report.totalCost))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if period == .today, let delta = dayOverDay(snapshot.weekDays) {
                    Label(deltaText(delta), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                        .help(l10n.vsYesterday)
                }
            }
            HStack(spacing: 8) {
                heroStat(icon: "number", text: l10n.tokensPill(Format.tokens(report.totalTokens, settings.unitStyle)))
                heroStat(icon: "bubble.left.and.bubble.right", text: l10n.messagesPill(report.totalMessages))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(heroGradient)
                // Soft light bleeding in from the top edge gives the flat
                // gradient a light source — the cheapest "depth" there is.
                RadialGradient(colors: [.white.opacity(0.22), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 96, weight: .black))
                    .foregroundStyle(.white.opacity(0.05))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 10, y: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: Color.brandInk.opacity(0.45), radius: 10, y: 5)
    }

    private func heroDateLabel(_ snapshot: Snapshot) -> String {
        let locale = l10n.locale
        switch period {
        case .today:
            return Date.now.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        case .week:
            return "\(shortDate(snapshot.weekDays.first?.date)) – \(shortDate(snapshot.weekDays.last?.date))"
        case .last30:
            return "\(shortDate(snapshot.last30Days.first?.date)) – \(shortDate(snapshot.last30Days.last?.date))"
        }
    }

    private func shortDate(_ date: String?) -> String {
        guard let date, date.count >= 10 else { return "" }
        let md = String(date.suffix(5))
        return settings.language == .zh ? md.replacingOccurrences(of: "-", with: "/") : md
    }

    private func heroStat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.13), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
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
            let values: [Double] = switch period {
            case .today: snapshot.hours.map(\.cost)
            case .week: snapshot.weekDays.map(\.totals.cost)
            case .last30: snapshot.last30Days.map(\.totals.cost)
            }
            if values.allSatisfy({ $0 <= 0 }) {
                // Flat zero bars read as a rendering bug; say it's empty instead.
                Label(l10n.noUsageYet, systemImage: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                switch period {
                case .today:
                    BarChart(values: values,
                             highlight: Calendar.current.component(.hour, from: Date()),
                             maxBarHeight: 52)
                    hourAxis
                case .week:
                    BarChart(values: values,
                             highlight: values.count - 1,
                             maxBarHeight: 52)
                    weekAxis(snapshot.weekDays)
                case .last30:
                    BarChart(values: values,
                             highlight: values.count - 1,
                             maxBarHeight: 52)
                    last30Axis(snapshot.last30Days)
                }
            }
        }
        .padding(12)
        .card(radius: 12)
    }

    private func chartCaption(_ snapshot: Snapshot) -> String {
        let locale = l10n.locale
        switch period {
        case .today:
            return Date.now.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        case .week:
            return "\(shortDate(snapshot.weekDays.first?.date)) – \(shortDate(snapshot.weekDays.last?.date))"
        case .last30:
            return "\(shortDate(snapshot.last30Days.first?.date)) – \(shortDate(snapshot.last30Days.last?.date))"
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

    /// Sparse M/d ticks under the 30-day bars; empty texts keep spacing even.
    private func last30Axis(_ days: [DayUsage]) -> some View {
        let ticks: Set<Int> = [0, 14, 29]
        return HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Text(ticks.contains(index) ? shortDate(day.date) : "")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    // Ticks are sparse, so let labels overflow their narrow
                    // slot instead of wrapping onto two lines.
                    .fixedSize()
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
                ForEach(Array(top.enumerated()), id: \.offset) { index, entry in
                    ModelRow(rank: index + 1, entry: entry, maxCost: maxCost,
                             tokensText: Format.tokens(entry.tokens, settings.unitStyle),
                             costText: cost(entry.cost))
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
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(
                        model.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: model.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            .help(l10n.refreshNow)
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
            Spacer(minLength: 4)
            Button(l10n.retry, action: model.refresh)
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.15), in: Capsule())
                .disabled(model.isRefreshing)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(radius: 10)
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
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func isToday(_ date: String) -> Bool {
        date == Self.dayFormatter.string(from: Date())
    }

    private func weekdayLetter(_ date: String) -> String {
        guard let d = Self.dayFormatter.date(from: date) else { return "" }
        // Use the formatter's Gregorian calendar, not Calendar.current, so a
        // non-Gregorian system calendar can't skew the weekday.
        return l10n.weekdayLetters[Self.dayFormatter.calendar.component(.weekday, from: d) - 1]
    }
}


/// One ranked model row: proportional cost bar underneath, lifts on hover.
private struct ModelRow: View {
    let rank: Int
    let entry: Report.Entry
    let maxCost: Double
    let tokensText: String
    let costText: String
    @State private var hovering = false

    var body: some View {
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
                .background(Color.brandDeep.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.brandDeep)
            Spacer(minLength: 4)
            Text(tokensText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text(costText)
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
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.05 : 0))
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
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

            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("TokscaleBar v\(version)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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

/// Native popover vibrancy: lets the desktop bleed through like Spotlight
/// panels do, instead of a flat opaque slab.
private struct PopoverBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
