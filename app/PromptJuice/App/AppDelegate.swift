import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = PromptJuiceSettingsStore.shared
    private lazy var viewModel = PromptJuiceViewModel(settingsStore: settingsStore)
    private lazy var panelController = JuicebarPanelController(viewModel: viewModel)
    private var statusItem: NSStatusItem?
    private var providerSetupWindow: NSWindow?
    private var providerSettingsWindow: NSWindow?
    private var ticker: Timer?
    private var lastGlyphKey: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = PromptJuiceIcon.appIconImage()
        configureStatusItem()
        startTicker()
        preparePanelAfterLaunch()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showLaunchExperience()
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
            }
        }
    }

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

    private func showLaunchExperience() {
        if settingsStore.didCompleteProviderSetup {
            showLaunchAlertIfNeeded()
        } else {
            showProviderSetup()
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
            withTitle: "Show Juicebar",
            action: #selector(showUsage),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Refresh Usage",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        ).target = self
        addProviderMenu(to: menu)
        menu.addItem(.separator())
        addAlertMenu(to: menu)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings...",
            action: #selector(showProviderSettings),
            keyEquivalent: ","
        ).target = self
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

    private func showLaunchAlertIfNeeded() {
        viewModel.refreshUsageAlertInBackground { [weak self] shouldShow in
            if shouldShow {
                self?.panelController.show()
            }
        }
    }

    @objc private func refreshUsage() {
        viewModel.refreshUsage()
        panelController.show()
    }

    @objc private func showProviderSetup() {
        let window = ensureProviderSetupWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showProviderSettings() {
        let window = ensureProviderSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func performProviderMenuAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let provider = UsageProvider(rawValue: rawValue) else {
            return
        }

        viewModel.performProviderSetupAction(for: provider)
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func ensureProviderSetupWindow() -> NSWindow {
        if let providerSetupWindow {
            providerSetupWindow.contentView = NSHostingView(rootView: setupRootView)
            return providerSetupWindow
        }

        let window = makeGlassWindow(
            title: "Connect Providers",
            size: NSSize(width: 760, height: 500)
        )
        window.contentView = NSHostingView(rootView: setupRootView)
        providerSetupWindow = window
        return window
    }

    private func ensureProviderSettingsWindow() -> NSWindow {
        if let providerSettingsWindow {
            providerSettingsWindow.contentView = NSHostingView(rootView: settingsRootView)
            return providerSettingsWindow
        }

        let window = makeGlassWindow(
            title: "PromptJuice Settings",
            size: NSSize(width: 780, height: 520)
        )
        window.contentView = NSHostingView(rootView: settingsRootView)
        providerSettingsWindow = window
        return window
    }

    private var setupRootView: ProviderSetupWindowView {
        ProviderSetupWindowView(
            viewModel: viewModel,
            onContinue: { [weak self] in
                guard let self else {
                    return
                }

                self.viewModel.completeProviderSetup()
                self.providerSetupWindow?.orderOut(nil)
                self.showUsage()
            },
            onOpenSettings: { [weak self] in
                self?.showProviderSettings()
            }
        )
    }

    private var settingsRootView: ProviderSettingsWindowView {
        ProviderSettingsWindowView(
            viewModel: viewModel,
            onOpenSetup: { [weak self] in
                self?.showProviderSetup()
            }
        )
    }

    private func makeGlassWindow(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        return window
    }

    private func addProviderMenu(to menu: NSMenu) {
        let providerMenuItem = NSMenuItem(title: "Providers", action: nil, keyEquivalent: "")
        let providerMenu = NSMenu(title: "Providers")

        for summary in viewModel.providerSetupSummaries {
            let item = NSMenuItem(
                title: "\(summary.identity.displayName): \(summary.state.rawValue)",
                action: #selector(performProviderMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = summary.provider.rawValue
            providerMenu.addItem(item)
        }

        providerMenu.addItem(.separator())
        providerMenu.addItem(
            withTitle: "Connect Providers...",
            action: #selector(showProviderSetup),
            keyEquivalent: ""
        ).target = self
        providerMenu.addItem(
            withTitle: "Provider Settings...",
            action: #selector(showProviderSettings),
            keyEquivalent: ""
        ).target = self

        menu.setSubmenu(providerMenu, for: providerMenuItem)
        menu.addItem(providerMenuItem)
    }

    private func addAlertMenu(to menu: NSMenu) {
        let alertMenuItem = NSMenuItem(title: "Alerts", action: nil, keyEquivalent: "")
        let alertMenu = NSMenu(title: "Alerts")

        addThresholdMenus(to: alertMenu)

        menu.setSubmenu(alertMenu, for: alertMenuItem)
        menu.addItem(alertMenuItem)
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
