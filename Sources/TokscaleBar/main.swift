import AppKit
import Combine
import SwiftUI

/// Holds the fetched snapshot and drives refreshes on a timer.
final class AppModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    /// Whether the popover shows the settings page. Reset when the popover closes.
    @Published var showSettings = false

    let settings = Settings()
    private let service = TokscaleService()

    /// Debug (`--mock` / `--state empty`): fixed data that freezes fetching.
    var pinnedSnapshot: Snapshot? {
        didSet {
            fetchesLiveData = pinnedSnapshot == nil
            snapshot = pinnedSnapshot
            lastUpdated = Date()
        }
    }
    /// Debug (`--state error`): when false, refresh() is a no-op and any
    /// in-flight fetch is dropped on completion.
    var fetchesLiveData = true
    private var timer: Timer?
    private var currentInterval: TimeInterval = 0

    init() {
        service.binaryPath = settings.tokscalePath
        refresh()
        startTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
    }

    @objc private func settingsChanged() {
        service.binaryPath = settings.tokscalePath
        startTimer()
    }

    private func startTimer() {
        let interval = settings.refreshInterval.rawValue
        guard interval != currentInterval else { return }
        currentInterval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard fetchesLiveData, !isRefreshing else { return }
        isRefreshing = true
        lastError = nil // a new attempt starts; don't show the stale failure
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Whatever happens below, the refresh button and timer must recover.
            defer {
                DispatchQueue.main.async { self.isRefreshing = false }
            }
            do {
                let snapshot = try self.service.fetchSnapshot()
                DispatchQueue.main.async {
                    guard self.fetchesLiveData else { return }
                    self.snapshot = snapshot
                    self.lastError = nil
                    self.lastUpdated = Date()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.fetchesLiveData else { return }
                    self.lastError = self.settings.l10n.errorText(error)
                }
            }
        }
    }

    /// Title shown next to the menu bar icon.
    var menuTitle: String {
        guard let snapshot else { return lastError != nil ? "!" : "…" }
        switch settings.menuMetric {
        case .cost: return Format.cost(snapshot.today.totalCost, currency: settings.currency, rate: settings.usdToCnyRate)
        case .tokens: return Format.tokens(snapshot.today.totalTokens, settings.unitStyle)
        case .messages: return "\(snapshot.today.totalMessages)"
        }
    }
}

/// Shared parsing for the debug appearance flags honored by both
/// `--preview-window` and `--render-png`.
struct DebugFlags {
    enum State: String { case live, empty, error, settings }
    var period: Period = .today
    var language: AppLanguage?
    var units: UnitStyle?
    var currency: AppCurrency?
    var mock = false
    var state: State = .live

    init(_ args: [String] = CommandLine.arguments) {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        period = value("--period").flatMap(Period.init) ?? .today
        language = value("--lang").flatMap(AppLanguage.init)
        units = value("--units").flatMap(UnitStyle.init)
        currency = value("--currency").flatMap(AppCurrency.init)
        mock = args.contains("--mock")
        state = value("--state").flatMap(State.init) ?? .live
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = AppModel()
    private var cancellable: Any?
    private var renderObservers: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug: `--render-png` renders the dashboard offscreen and exits, so
        // it must never touch the status bar.
        if let idx = CommandLine.arguments.firstIndex(of: "--render-png") {
            guard CommandLine.arguments.indices.contains(idx + 1) else {
                FileHandle.standardError.write(Data("usage: --render-png <path> [--period today|week|last30|all] [--lang zh|en] [--units western|chinese] [--currency usd|cny] [--mock] [--state live|empty|error|settings]\n".utf8))
                exit(2)
            }
            setupRenderPNG(path: CommandLine.arguments[idx + 1])
            return
        }

        // Debug: `--preview-window` shows the popover content in a regular window.
        if CommandLine.arguments.contains("--preview-window") {
            let flags = DebugFlags()
            applyDebugFlags(flags)
            let controller = NSHostingController(
                rootView: PopoverView(model: model, settings: model.settings, initialPeriod: flags.period)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 324, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "TokscaleBar Preview"
            window.contentViewController = controller
            // Hug the content like the popover does, capped so tall states
            // (dashboard with all sections) still fit on small screens.
            let fit = controller.view.fittingSize
            window.setContentSize(NSSize(width: 324, height: min(fit.height, 720)))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Template rendering lets macOS adapt the glyph to the menu bar
            // (dark/light, wallpaper tint). The outline bolt matches the
            // single-line style of the app icon.
            let image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Tokscale")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        // sizingOptions publishes SwiftUI's ideal size as preferredContentSize,
        // which is the only channel NSPopover obeys — without it the popover
        // falls back to its 320×320 default and no frame modifier can grow it.
        let hosting = NSHostingController(
            rootView: PopoverView(model: model, settings: model.settings)
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        let snapshotChanged = model.$snapshot.combineLatest(model.$lastError).map { _ in () }
        let metricChanged = model.settings.$menuMetric.map { _ in () }
        let unitChanged = model.settings.$unitStyle.map { _ in () }
        let currencyChanged = model.settings.$currency.map { _ in () }
        let rateChanged = model.settings.$usdToCnyRate.map { _ in () }
        cancellable = snapshotChanged
            .merge(with: metricChanged, unitChanged, currencyChanged, rateChanged)
            .sink { [weak self] in self?.updateTitle() }
        updateTitle()
    }

    /// Applies debug appearance and state flags. Persistence is disabled so
    /// a debug run never dirties the user's real settings.
    private func applyDebugFlags(_ flags: DebugFlags) {
        let settings = model.settings
        settings.persists = false
        if let language = flags.language { settings.language = language }
        if let units = flags.units { settings.unitStyle = units }
        if let currency = flags.currency { settings.currency = currency }
        if flags.mock { model.pinnedSnapshot = Mock.snapshot }
        switch flags.state {
        case .live: break
        case .empty: model.pinnedSnapshot = Mock.empty
        case .error:
            model.fetchesLiveData = false
            model.lastError = settings.l10n.errorText(TokscaleError.binaryNotFound)
        case .settings: model.showSettings = true
        }
    }

    /// `--render-png <path> [--period today|week|last30|all] [--lang zh|en]
    /// [--units western|chinese] [--currency usd|cny] [--mock]
    /// [--state live|empty|error|settings]`: renders once data arrives,
    /// then exits 0. Static states (`--mock` / non-live `--state`) skip the
    /// fetch entirely. In live mode, exits non-zero on fetch error or after
    /// a 30s deadline (the 20s subprocess timeout plus slack) so callers
    /// can never hang.
    private func setupRenderPNG(path: String) {
        let flags = DebugFlags()
        applyDebugFlags(flags)

        // Static states need no fetch: give SwiftUI a runloop turn to lay
        // out, then rasterize straight away.
        if flags.mock || flags.state != .live {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                guard Self.renderPNG(model: self.model, period: flags.period, to: path) else {
                    FileHandle.standardError.write(Data("render-png: failed to write \(path)\n".utf8))
                    exit(1)
                }
                NSApplication.shared.terminate(nil)
            }
            return
        }

        let period = flags.period
        model.$snapshot.compactMap { $0 }.first().sink { [weak self] _ in
            // Give SwiftUI a runloop turn to lay out before rasterizing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                guard Self.renderPNG(model: self.model, period: period, to: path) else {
                    FileHandle.standardError.write(Data("render-png: failed to write \(path)\n".utf8))
                    exit(1)
                }
                NSApplication.shared.terminate(nil)
            }
        }.store(in: &renderObservers)

        model.$lastError.compactMap { $0 }.first().sink { [weak self] error in
            guard let self, self.model.snapshot == nil else { return }
            FileHandle.standardError.write(Data((error + "\n").utf8))
            exit(1)
        }.store(in: &renderObservers)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard self?.model.snapshot == nil else { return }
            FileHandle.standardError.write(Data("render-png: timed out waiting for tokscale data\n".utf8))
            exit(1)
        }
    }

    private func updateTitle() {
        statusItem.button?.title = model.menuTitle
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.showSettings = false
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func openSettings() {
        model.showSettings = true
        openPopover()
    }

    /// Right-click menu. `statusItem.menu` is set only for the click itself —
    /// leaving it attached would swallow the left-click popover toggle.
    private func showStatusMenu() {
        let l10n = model.settings.l10n
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ action: Selector, _ key: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        item(l10n.refreshNow, "arrow.clockwise", #selector(menuRefresh), "r")
        item(l10n.settingsTitle, "gearshape", #selector(openSettings), ",")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: l10n.quitApp,
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp // AppDelegate doesn't implement terminate:
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuRefresh() {
        model.refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        // Always land back on the dashboard for the next open.
        model.showSettings = false
    }

    /// Renders the popover offscreen. Returns false when the bitmap or the
    /// file write fails, so headless callers don't exit 0 with no image.
    @discardableResult
    static func renderPNG(model: AppModel, period: Period = .today, to path: String) -> Bool {
        let hosting = NSHostingView(rootView: PopoverView(model: model, settings: model.settings, initialPeriod: period))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--preview-window") ? .regular : .accessory)
app.run()
