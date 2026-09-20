import AppKit
import SwiftUI

/// Tallest popover height that still fits the screen: visibleFrame already
/// excludes the menu bar; the rest is the popover arrow plus breathing room.
/// Anything shorter shows in full — a hardcoded cap clipped real content.
private func maxPopoverHeight() -> CGFloat {
    maxPopoverHeight(screen: statusBarScreen())
}

/// An accessory app has no key window, so NSScreen.main can name the wrong
/// display. PopoverView doesn't own the status item, so find the status bar
/// button's window through NSApp and use the screen it lives on.
private func statusBarScreen() -> NSScreen? {
    NSApp.windows.first { NSStringFromClass(type(of: $0)) == "NSStatusBarWindow" }?.screen
}

private func maxPopoverHeight(screen: NSScreen?) -> CGFloat {
    let height = (screen ?? NSScreen.main)?.visibleFrame.height ?? 740
    return height - 44
}

enum Period: String, CaseIterable, Identifiable {
    case today, week, last30, all
    var id: String { rawValue }
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @State private var period: Period
    @State private var expandedEntry: String?
    @State private var expandedSubscription: UUID?

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
        // Content grows with period/model counts; it scrolls only when it
        // would overflow the screen, never at a hardcoded height.
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
                    roiSection
                    subscriptionsCard
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
        .frame(maxHeight: maxPopoverHeight())
        .scrollIndicators(.automatic)
    }

    private var report: Report {
        guard let snapshot = model.snapshot else { return .empty }
        switch period {
        case .today: return snapshot.today
        case .week: return snapshot.week
        case .last30: return snapshot.last30
        case .all: return snapshot.all
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
            .accessibilityLabel(l10n.settingsTitle)
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
        let metric = settings.heroMetric
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l10n.heroTitle(period, metric: metric))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(periodDateLabel(snapshot))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heroHeadline(report, metric: metric))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if period == .today, let delta = TokscaleService.dayOverDay(snapshot.weekDays, metric: metric) {
                    deltaBadge(delta)
                }
            }
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1)
            HStack {
                switch metric {
                case .cost:
                    miniStat(icon: "number",
                             text: l10n.tokensPill(Format.tokens(report.totalTokens, settings.unitStyle)))
                case .tokens:
                    miniStat(icon: settings.currency == .cny ? "yensign" : "dollarsign",
                             text: cost(report.totalCost))
                }
                Spacer()
                miniStat(icon: "bubble.left.and.bubble.right",
                         text: l10n.messagesPill(report.totalMessages))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggleHeroMetric() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(l10n.heroTitle(period, metric: metric))
        .card()
    }

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
        let formatted = sub.price.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", sub.price)
            : String(format: "%.2f", sub.price)
        return "\(sub.currency.symbol)\(formatted)\(l10n.perMonth)"
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
                    .onChange(of: binding.wrappedValue.billingDay) { _ in model.refresh() }
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

    // MARK: Subscriptions

    @ViewBuilder
    private var subscriptionsCard: some View {
        if !model.usage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(l10n.quotas)
                VStack(spacing: 8) {
                    ForEach(model.usage) { account in
                        usageRow(account)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 12)
        } else if model.usageError != nil, model.snapshot != nil {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                Text(l10n.subscriptionsUnavailable)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usageRow(_ account: UsageAccount) -> some View {
        let primary = account.primaryMetric
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(account.provider)
                    .font(.system(size: 11, weight: .semibold))
                if let plan = account.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                if let primary {
                    Text(primary.remainingLabel ?? String(format: "%.0f%%", primary.remainingPercent))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let reset = l10n.usageReset(primary) {
                        Text(reset)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let primary {
                usageBar(primary)
            }
            if !account.secondaryMetrics.isEmpty {
                Text(account.secondaryMetrics.map { secondaryCaption($0) }.joined(separator: "  ·  "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func usageBar(_ metric: UsageMetric) -> some View {
        let remaining = min(max(metric.remainingPercent / 100, 0), 1)
        let tint: Color = remaining <= 0.001 ? .red : (remaining < 0.2 ? .orange : .brand)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * remaining))
            }
        }
        .frame(height: 4)
    }

    private func secondaryCaption(_ metric: UsageMetric) -> String {
        let amount = metric.remainingLabel ?? String(format: "%.0f%%", metric.remainingPercent)
        return "\(metric.label) \(amount)"
    }

    private func heroHeadline(_ report: Report, metric: HeroMetric) -> String {
        switch metric {
        case .cost: return cost(report.totalCost)
        case .tokens: return Format.tokens(report.totalTokens, settings.unitStyle)
        }
    }

    private func toggleHeroMetric() {
        settings.heroMetric = settings.heroMetric == .cost ? .tokens : .cost
    }

    /// Spending trend semantics: less than yesterday is green, more is orange.
    private func deltaBadge(_ delta: Double) -> some View {
        // A sub-1% wobble rounds to 0 — arrowing and tinting it would claim a
        // trend that isn't there, so it renders as a neutral zero instead.
        let neutral = (delta * 100).rounded() == 0
        let tint: Color = neutral ? .secondary : (delta >= 0 ? .orange : .green)
        return Label(neutral ? "0%" : deltaText(delta),
                     systemImage: neutral ? "arrow.right" : (delta >= 0 ? "arrow.up.right" : "arrow.down.right"))
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .help(l10n.vsYesterday)
    }

    private func miniStat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Date range the current period covers, shown next to the hero and as the
    /// chart caption — one function so the two can never drift apart.
    private func periodDateLabel(_ snapshot: Snapshot) -> String {
        func range(_ first: String?, _ last: String?, _ format: (String?) -> String) -> String {
            // Empty history has no endpoints; a lone dash reads better than
            // two blanks or sentinel dates.
            guard let first, let last else { return "—" }
            return "\(format(first)) – \(format(last))"
        }
        switch period {
        case .today:
            return Date.now.formatted(.dateTime.month(.abbreviated).day().locale(l10n.locale))
        case .week:
            return range(snapshot.weekDays.first?.date, snapshot.weekDays.last?.date, shortDate)
        case .last30:
            return range(snapshot.last30Days.first?.date, snapshot.last30Days.last?.date, shortDate)
        case .all:
            return range(snapshot.allDays.first?.date, snapshot.allDays.last?.date, fullDate)
        }
    }

    private func shortDate(_ date: String?) -> String {
        guard let date, date.count >= 10 else { return "" }
        let md = String(date.suffix(5))
        return settings.language.resolved == .zh ? md.replacingOccurrences(of: "-", with: "/") : md
    }

    /// All-time ranges can span years, so keep the year: 2026/07/05.
    private func fullDate(_ date: String?) -> String {
        guard let date, date.count >= 10 else { return "" }
        let ymd = String(date.prefix(10))
        return settings.language.resolved == .zh ? ymd.replacingOccurrences(of: "-", with: "/") : ymd
    }

    // MARK: Chart

    private func chartSection(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let chartTitle = switch period {
                case .today: l10n.hourlyChart
                case .all: l10n.monthlyChart
                default: l10n.dailyChart
                }
                sectionTitle(chartTitle)
                Spacer()
                Text(periodDateLabel(snapshot))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            // All-time is aggregated per calendar month — daily bars for
            // years of history would be an unreadable comb.
            let months = TokscaleService.monthlyCosts(snapshot.allDays)
            let values: [Double] = switch period {
            case .today: snapshot.hours.map(\.cost)
            case .week: snapshot.weekDays.map(\.totals.cost)
            case .last30: snapshot.last30Days.map(\.totals.cost)
            case .all: months.map(\.cost)
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
                }
            }
        }
        .padding(12)
        .card(radius: 12)
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

    /// Month label under each all-time bar; past a year of bars the labels
    /// would crowd into each other, so they thin out — never denser than
    /// every second bar.
    private func allAxis(_ months: [String]) -> some View {
        let strideBy = months.count > 12 ? max(months.count / 12, 2) : 1
        return HStack(spacing: 0) {
            ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                Text(index % strideBy == 0 ? l10n.monthLabel(month) : "")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
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
            }
        }
    }

    // MARK: Clients

    @ViewBuilder
    private func clientShare(_ report: Report) -> some View {
        let shares = Self.clientShares(report, l10n: l10n)
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(l10n.byClient)
                ClientShareView(shares: shares, currency: settings.currency, rate: settings.usdToCnyRate)
            }
        }
    }

    /// Per-client cost shares, ranked descending; everything past TOP 5
    /// buckets into "Other".
    private static func clientShares(_ report: Report, l10n: L10n) -> [(client: String, cost: Double)] {
        var byClient: [String: Double] = [:]
        for entry in report.entries {
            byClient[entry.client, default: 0] += entry.cost
        }
        // Cache-only traffic can price at 0 and still yield a client entry; a
        // zero share would render as an empty legend row, so drop it.
        let ranked = byClient.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let top = ranked.prefix(5).map { (client: $0.key, cost: $0.value) }
        let rest = ranked.dropFirst(5).reduce(0.0) { $0 + $1.value }
        return rest > 0 ? top + [(client: l10n.other, cost: rest)] : top
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
                RefreshGlyph(isRefreshing: model.isRefreshing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.isRefreshing)
            .help(l10n.refreshNow)
            .accessibilityLabel(l10n.refreshNow)
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(l10n.quit)
            .accessibilityLabel(l10n.quit)
        }
    }

    private func errorCard(_ error: TokscaleError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            // Localize at render time so the banner follows a language
            // switch; lineLimit keeps unbounded CLI messages in check.
            Text(l10n.errorText(error))
                .font(.system(size: 11))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
    }

    private func deltaText(_ delta: Double) -> String {
        String(format: "%+.0f%%", delta * 100)
    }

    private func isToday(_ date: String) -> Bool {
        date == Dates.dayString(Date())
    }

    private func weekdayLetter(_ date: String) -> String {
        guard let d = Dates.dayDate(date) else { return "" }
        // Use the shared Gregorian calendar, not Calendar.current, so a
        // non-Gregorian system calendar can't skew the weekday.
        return l10n.weekdayLetters[Dates.calendar.component(.weekday, from: d) - 1]
    }
}


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

/// Spinning refresh glyph. The repeatForever animation must start through an
/// explicit withAnimation on local @State: attaching it via
/// .animation(_:value:) leaks the repeating transaction onto every layout
/// change that shares the isRefreshing flip (e.g. the error card
/// disappearing), and the button's position then replays forever — the glyph
/// visibly flies across the popover and the runaway animation never stops.
/// Stopping needs an animation-disabled transaction; a plain assignment
/// leaves the repeating animation running invisibly.
private struct RefreshGlyph: View {
    let isRefreshing: Bool
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .medium))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear { if isRefreshing { startSpin() } }
            .onChange(of: isRefreshing) { refreshing in
                if refreshing {
                    startSpin()
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { spinning = false }
                }
            }
    }

    private func startSpin() {
        spinning = false
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            spinning = true
        }
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
        .frame(maxHeight: maxPopoverHeight())
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
                .accessibilityLabel(l10n.back)
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
                    .frame(width: 240)
                }
                rowDivider
                settingRow(l10n.numberUnits) {
                    Picker("", selection: $settings.unitStyle) {
                        ForEach(UnitStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(l10n.numberUnits)
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                rowDivider
                settingRow(l10n.currencyLabel) {
                    Picker("", selection: $settings.currency) {
                        ForEach(AppCurrency.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(l10n.currencyLabel)
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
                    .accessibilityLabel(l10n.menuBarShows)
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow(l10n.heroShows) {
                    Picker("", selection: $settings.heroMetric) {
                        ForEach(HeroMetric.allCases) { Text(l10n.metricLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(l10n.heroShows)
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                rowDivider
                settingRow(l10n.refreshEvery) {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text(l10n.intervalLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(l10n.refreshEvery)
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                rowDivider
                settingRow(l10n.launchAtLogin) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .accessibilityLabel(l10n.launchAtLogin)
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
