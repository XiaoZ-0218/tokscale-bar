import AppKit
import SwiftUI

/// Holds the fetched snapshot and drives refreshes on a timer.
final class AppModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    let settings = Settings()
    private let service = TokscaleService()
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
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.service.fetchSnapshot()
                DispatchQueue.main.async {
                    self.snapshot = snapshot
                    self.lastError = nil
                    self.lastUpdated = Date()
                    self.isRefreshing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = self.settings.l10n.errorText(error)
                    self.isRefreshing = false
                }
            }
        }
    }

    /// Title shown next to the menu bar icon.
    var menuTitle: String {
        guard let snapshot else { return lastError != nil ? "!" : "…" }
        switch settings.menuMetric {
        case .cost: return Format.cost(snapshot.today.totalCost)
        case .tokens: return Format.tokens(snapshot.today.totalTokens, settings.unitStyle)
        case .messages: return "\(snapshot.today.totalMessages)"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = AppModel()
    private var cancellable: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug: `--render-png <path> [--period today|week|month] [--lang zh|en]
        // [--units western|chinese]` renders the dashboard offscreen and exits.
        if let idx = CommandLine.arguments.firstIndex(of: "--render-png"),
           CommandLine.arguments.indices.contains(idx + 1) {
            let path = CommandLine.arguments[idx + 1]
            let args = CommandLine.arguments
            func argValue(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
                return args[i + 1]
            }
            model.settings.persists = false
            if let lang = argValue("--lang"), let language = AppLanguage(rawValue: lang) {
                model.settings.language = language
            }
            if let units = argValue("--units"), let style = UnitStyle(rawValue: units) {
                model.settings.unitStyle = style
            }
            let period = argValue("--period").flatMap(Period.init(rawValue:)) ?? .today

            var observer: Any?
            observer = self.model.$snapshot.compactMap { $0 }.first().sink { [self] _ in
                _ = observer
                // Give SwiftUI a runloop turn to lay out before rasterizing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Self.renderPNG(model: self.model, period: period, to: path)
                    NSApplication.shared.terminate(nil)
                }
            }
        }

        // Debug: `--preview-window` shows the popover content in a regular window.
        if CommandLine.arguments.contains("--preview-window") {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "TokscaleBar Preview"
            window.contentViewController = NSHostingController(
                rootView: PopoverView(model: model, settings: model.settings)
            )
            window.setFrameOrigin(NSPoint(x: 260, y: 300))
            window.makeKeyAndOrderFront(nil)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Tokscale")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model, settings: model.settings)
        )

        let snapshotChanged = model.$snapshot.combineLatest(model.$lastError).map { _ in () }
        let metricChanged = model.settings.$menuMetric.map { _ in () }
        let unitChanged = model.settings.$unitStyle.map { _ in () }
        cancellable = snapshotChanged
            .merge(with: metricChanged, unitChanged)
            .sink { [weak self] in self?.updateTitle() }
        updateTitle()
    }

    private func updateTitle() {
        statusItem.button?.title = model.menuTitle
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    static func renderPNG(model: AppModel, period: Period = .today, to path: String) {
        let hosting = NSHostingView(rootView: PopoverView(model: model, settings: model.settings, initialPeriod: period))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--preview-window") ? .regular : .accessory)
app.run()
