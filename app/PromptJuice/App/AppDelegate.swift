import AppKit
import Combine
import Network
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let viewModel = PromptJuiceViewModel.makeAppViewModel()
    private let notificationService = PromptJuiceNotificationService()
    private lazy var settingsWindowController = SettingsWindowController(
        viewModel: viewModel,
        onFirstRunFinished: { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showUsage()
        }
    )
    private lazy var panelController = JuicebarPanelController(
        viewModel: viewModel,
        onClaudeGuidanceRequested: { [weak self] journey in
            self?.settingsWindowController.show(claudeJourney: journey)
        },
        onSettingsRequested: { [weak self] in
            self?.settingsWindowController.show()
        }
    )
    private var statusItem: NSStatusItem?
    private var ticker: Timer?
    private var lastGlyphKey: String?
    private var lastLifecycleRefreshAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "app.promptjuice.network-monitor")
#if DEBUG
    private var debugPanelWindow: NSWindow?
    private var debugToolTipWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = PromptJuiceIcon.appIconImage() {
            NSApp.applicationIconImage = appIcon
        }
        configureStatusItem()
        configureNotifications()
        observeViewModel()
        observeHostLifecycle()
        startNetworkMonitor()
        viewModel.refreshUsageQuietly(reason: .launch)
        startTicker()
        preparePanelAfterLaunch()

#if DEBUG
        showDebugPreviewSurfaceIfRequested()
#endif

        if viewModel.isFirstRun {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController.showFirstRun()
            }
        }
    }

#if DEBUG
    private func showDebugPreviewSurfaceIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        let dogfoodSurface = environment["PROMPTJUICE_DOGFOOD_SURFACE"]
        guard environment["PROMPTJUICE_CLAUDE_UI_SCENARIO"] != nil || dogfoodSurface != nil else {
            return
        }
        let surface = dogfoodSurface ?? environment["PROMPTJUICE_UI_SURFACE"] ?? "panel"
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            switch surface {
            case "settings":
                self.settingsWindowController.show()
            case "guidance":
                self.settingsWindowController.show(
                    claudeJourney: self.viewModel.claudePresentation.guidanceJourney
                )
            case "tooltip":
                self.showDebugToolTipPreview()
            default:
                self.showDebugPanelPreview()
            }
        }
    }

    private func showDebugPanelPreview() {
        let height = PromptJuicePanelMetrics.height(
            rowCount: viewModel.visibleSnapshots.count,
            showsNotificationPrime: viewModel.shouldOfferUseSoonNotificationPrime
        )
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: PromptJuicePanelMetrics.width, height: height)
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PromptJuice Juicebar Preview"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PromptJuicePanelView(
                viewModel: viewModel,
                onClose: { [weak window] in
                    window?.close()
                },
                onClaudeJourney: { [weak self, weak window] journey in
                    window?.close()
                    self?.settingsWindowController.show(claudeJourney: journey)
                }
            )
        )
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        debugPanelWindow = window
    }

    private func showDebugToolTipPreview() {
        guard let snapshot = viewModel.visibleSnapshots.first(where: { $0.provider == .claude }) else {
            return
        }

        let tooltipView = PanelToolTipView(text: viewModel.sourceTooltip(for: snapshot))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: tooltipView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "PromptJuice Tooltip Preview"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = tooltipView
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        debugToolTipWindow = window
    }
#endif

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
        networkMonitor.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.toolTip = "PromptJuice"
        button.setAccessibilityHelp("Left click to show usage. Right click for PromptJuice controls.")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateStatusItemGlyph(force: true)
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.tick()
                self?.updateStatusItemGlyph()
                self?.processUseSoonNotifications()
            }
        }
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.viewModel.setNetworkOnline(path.status == .satisfied)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func observeViewModel() {
        viewModel.$enabledProviders
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemGlyph(force: true)
            }
            .store(in: &cancellables)

        viewModel.$snapshots
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemGlyph()
                self?.processUseSoonNotifications()
            }
            .store(in: &cancellables)

        viewModel.$useSoonNotificationsEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard enabled else {
                    return
                }

                self?.requestUseSoonNotificationAuthorization()
            }
            .store(in: &cancellables)
    }

    private func configureNotifications() {
        notificationService.onUseSoonNotificationActivated = { [weak self] in
            guard let self else {
                return
            }

            self.viewModel.showManualCheck()
            self.panelController.show()
        }

        refreshUseSoonNotificationAuthorization()

        if viewModel.useSoonNotificationsEnabled {
            requestUseSoonNotificationAuthorization()
        }
    }

    private func refreshUseSoonNotificationAuthorization() {
        notificationService.refreshAuthorizationStatus { [weak self] authorization in
            self?.viewModel.setNotificationAuthorization(authorization)
        }
    }

    private func requestUseSoonNotificationAuthorization() {
        notificationService.requestAuthorization { [weak self] authorization in
            self?.viewModel.setNotificationAuthorization(authorization)
        }
    }

    private func observeHostLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshAfterHostLifecycleChange),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshAfterWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func refreshAfterWake() {
        performHostLifecycleRefresh(reason: .wake)
    }

    @objc private func refreshAfterHostLifecycleChange() {
        performHostLifecycleRefresh(reason: .foreground)
    }

    private func performHostLifecycleRefresh(reason: ClaudeRefreshReason) {
#if DEBUG
        if ProcessInfo.processInfo.environment["PROMPTJUICE_DOGFOOD_SURFACE"] != nil,
           reason == .foreground {
            return
        }
#endif
        let refreshDate = Date()

        if let lastLifecycleRefreshAt,
           refreshDate.timeIntervalSince(lastLifecycleRefreshAt) < 2 {
            return
        }

        lastLifecycleRefreshAt = refreshDate
        viewModel.refreshUsageQuietly(reason: reason)
        updateStatusItemGlyph(force: true)
        processUseSoonNotifications()
    }

    /// Redraws the menu-bar droplet from the current aggregate. The fill is the
    /// binding constraint (lowest provider); the tint is the worst severity.
    /// Skips redundant redraws so it's cheap to call every tick.
    private func updateStatusItemGlyph(force: Bool = false) {
        guard let button = statusItem?.button else {
            return
        }

        let remaining = viewModel.menuBarRemainingPercent
        let severity = viewModel.menuBarSeverity
        let percent = Int(remaining.rounded())
        let key = "\(percent)-\(severity)"

        guard force || key != lastGlyphKey else {
            return
        }

        lastGlyphKey = key

        let image = PromptJuiceIcon.statusBarImage(
            remaining: remaining / 100,
            severity: severity
        )
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
        button.setAccessibilityLabel(viewModel.menuBarAccessibilityLabel)
    }

    private func preparePanelAfterLaunch() {
        DispatchQueue.main.async { [weak self] in
            self?.panelController.prepare()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if shouldShowContextMenu {
            showContextMenu()
            return
        }

        viewModel.showManualCheck()
        panelController.toggle()
    }

    private var shouldShowContextMenu: Bool {
        guard let event = NSApp.currentEvent else {
            return false
        }

        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func showContextMenu() {
        guard let statusItem,
              let button = statusItem.button else {
            return
        }

        let menu = Self.makeContextMenu(target: self, isJuicebarPinned: panelController.isPinned)
        menu.delegate = self
        statusItem.menu = menu
        button.performClick(nil)
    }

    static func makeContextMenu(target: AnyObject, isJuicebarPinned: Bool = false) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show Usage",
            action: #selector(showUsage),
            keyEquivalent: ""
        ).target = target
        menu.addItem(
            withTitle: isJuicebarPinned ? "Unpin Juicebar" : "Pin Juicebar",
            action: #selector(togglePinJuicebar),
            keyEquivalent: ""
        ).target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        ).target = target
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit PromptJuice",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = target

        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func showUsage() {
        viewModel.showManualCheck()
        panelController.show()
    }

    @objc private func togglePinJuicebar() {
        viewModel.showManualCheck()
        panelController.togglePin()
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func processUseSoonNotifications() {
        let notificationDate = Date()

        let withdrawals = viewModel.staleUseSoonNotificationWithdrawals(now: notificationDate)
        if !withdrawals.isEmpty {
            // Providers merge into one banner, so also drop the merged id — not
            // just the per-provider ones — then clear each stale latch.
            var identifiers = withdrawals.map(\.notificationIdentifier)
            if let merged = viewModel.lastDispatchedUseSoonNotificationIdentifier {
                identifiers.append(merged)
            }
            notificationService.removeUseSoonNotifications(identifiers: identifiers)
            withdrawals.forEach(viewModel.clearUseSoonNotificationLatch)
            viewModel.forgetDispatchedUseSoonNotificationIfCleared()
        }

        let pending = viewModel.pendingUseSoonNotifications(now: notificationDate)
        guard !pending.isEmpty,
              let merged = MergedUseSoonNotification(notices: pending) else {
            return
        }

        pending.forEach(viewModel.markUseSoonNoticeDispatched)
        viewModel.rememberDispatchedUseSoonNotification(merged)
        notificationService.sendUseSoonNotification(merged)
    }
}
