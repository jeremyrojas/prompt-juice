import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let viewModel = PromptJuiceViewModel()
    private let claudeBridgeInstaller = ClaudeBridgeInstaller()
    private let claudeStatusCachePoller = ClaudeStatusCachePoller()
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
        onClaudeSettingsRequested: { [weak self] presentingSetup in
            self?.settingsWindowController.show(presentingClaudeSetup: presentingSetup)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = PromptJuiceIcon.appIconImage()
        configureStatusItem()
        configureNotifications()
        observeViewModel()
        observeHostLifecycle()
        syncClaudeBridgeScript(reason: "launch")
        startTicker()
        startClaudeStatusCacheMonitor()
        preparePanelAfterLaunch()

        if viewModel.isFirstRun {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController.showFirstRun()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
        claudeStatusCachePoller.stop()
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

    private func startClaudeStatusCacheMonitor() {
        claudeStatusCachePoller.start { [weak self] in
            self?.viewModel.refreshClaudeAfterStatusCacheChange(reason: "cache watcher")
        }
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
        syncClaudeBridgeScript(reason: "wake")
        refreshAfterHostLifecycleChange()
    }

    @objc private func refreshAfterHostLifecycleChange() {
        let refreshDate = Date()

        if let lastLifecycleRefreshAt,
           refreshDate.timeIntervalSince(lastLifecycleRefreshAt) < 2 {
            return
        }

        lastLifecycleRefreshAt = refreshDate
        startClaudeStatusCacheMonitor()
        viewModel.refreshClaudeStatusCacheNow(reason: "host lifecycle")
        viewModel.refreshUsageQuietly()
        updateStatusItemGlyph(force: true)
        processUseSoonNotifications()
    }

    private func syncClaudeBridgeScript(reason: String) {
        claudeBridgeInstaller.ensureInstalledBridgeCurrent(reason: reason)
        viewModel.refreshClaudeBridgeState()
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
        button.setAccessibilityLabel("PromptJuice: \(percent)% left")
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

        let menu = Self.makeContextMenu(target: self)
        menu.delegate = self
        statusItem.menu = menu
        button.performClick(nil)
    }

    static func makeContextMenu(target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show Usage",
            action: #selector(showUsage),
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

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func processUseSoonNotifications() {
        let notificationDate = Date()

        for withdrawal in viewModel.staleUseSoonNotificationWithdrawals(now: notificationDate) {
            notificationService.removeUseSoonNotifications(identifiers: [withdrawal.notificationIdentifier])
            viewModel.clearUseSoonNotificationLatch(for: withdrawal)
        }

        for notice in viewModel.pendingUseSoonNotifications(now: notificationDate) {
            viewModel.markUseSoonNoticeDispatched(notice)
            notificationService.sendUseSoonNotification(notice)
        }
    }
}
