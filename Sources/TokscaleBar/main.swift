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
                    self.lastError = error.localizedDescription
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
        case .tokens: return Format.tokens(snapshot.today.totalTokens)
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
        cancellable = snapshotChanged.merge(with: metricChanged).sink { [weak self] in
            self?.updateTitle()
        }
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
