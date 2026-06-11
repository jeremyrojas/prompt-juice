import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = PromptJuiceViewModel()
    private let notificationService = PromptJuiceNotificationService()
    private lazy var panelController = JuicebarPanelController(viewModel: viewModel)
    private var statusItem: NSStatusItem?
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = PromptJuiceIcon.appIconImage()
        configureStatusItem()
        startTicker()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showLaunchDemoAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.image = PromptJuiceIcon.statusBarImage()
        button.imagePosition = .imageOnly
        button.toolTip = "PromptJuice"
        button.setAccessibilityLabel("PromptJuice menu")
        button.setAccessibilityHelp("Left click to show usage. Right click for PromptJuice controls.")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.tick()
            }
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
        guard let button = statusItem?.button else {
            return
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Show Usage",
            action: #selector(showUsage),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Check Demo Alert",
            action: #selector(checkDemoAlert),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Cycle Demo State",
            action: #selector(cycleDemoState),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        addThresholdMenus(to: menu)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Request Notifications",
            action: #selector(requestNotifications),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Send Demo Notification",
            action: #selector(sendDemoNotification),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit PromptJuice",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func showUsage() {
        viewModel.showManualCheck()
        panelController.show()
    }

    private func showLaunchDemoAlert() {
        viewModel.checkDemoAlert(force: true)
        panelController.show()
    }

    @objc private func checkDemoAlert() {
        if viewModel.checkDemoAlert() {
            panelController.show()
        } else {
            panelController.hide()
        }
    }

    @objc private func cycleDemoState() {
        viewModel.cycleDemoState()
        panelController.show()
    }

    @objc private func setRemainingMinutesThreshold(_ sender: NSMenuItem) {
        viewModel.setRemainingMinutesThreshold(sender.tag)
        panelController.show()
    }

    @objc private func setRemainingPercentThreshold(_ sender: NSMenuItem) {
        viewModel.setRemainingPercentThreshold(sender.tag)
        panelController.show()
    }

    @objc private func requestNotifications() {
        notificationService.requestAuthorization()
    }

    @objc private func sendDemoNotification() {
        viewModel.checkDemoAlert(force: true)
        panelController.show()
        notificationService.sendUseSoonNotification(
            title: viewModel.headline,
            body: viewModel.detail
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func addThresholdMenus(to menu: NSMenu) {
        let minutesMenuItem = NSMenuItem(title: "Remaining Time Threshold", action: nil, keyEquivalent: "")
        let minutesMenu = NSMenu(title: "Remaining Time Threshold")

        for minutes in [30, 45, 60, 90] {
            let item = NSMenuItem(
                title: "\(minutes)m remaining",
                action: #selector(setRemainingMinutesThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            item.state = viewModel.thresholds.remainingMinutes == minutes ? .on : .off
            minutesMenu.addItem(item)
        }

        menu.setSubmenu(minutesMenu, for: minutesMenuItem)
        menu.addItem(minutesMenuItem)

        let percentMenuItem = NSMenuItem(title: "Remaining Juice Threshold", action: nil, keyEquivalent: "")
        let percentMenu = NSMenu(title: "Remaining Juice Threshold")

        for percent in [25, 40, 50, 60] {
            let item = NSMenuItem(
                title: "\(percent)% left",
                action: #selector(setRemainingPercentThreshold(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = percent
            item.state = viewModel.thresholds.remainingPercent == percent ? .on : .off
            percentMenu.addItem(item)
        }

        menu.setSubmenu(percentMenu, for: percentMenuItem)
        menu.addItem(percentMenuItem)
    }
}
