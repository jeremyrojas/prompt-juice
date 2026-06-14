import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = PromptJuiceViewModel()
    private lazy var settingsWindowController = SettingsWindowController(viewModel: viewModel)
    private lazy var panelController = JuicebarPanelController(
        viewModel: viewModel,
        onClaudeSettingsRequested: { [weak self] presentingSetup in
            self?.settingsWindowController.show(presentingClaudeSetup: presentingSetup)
        }
    )
    private var statusItem: NSStatusItem?
    private var ticker: Timer?
    private var lastGlyphKey: String?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = PromptJuiceIcon.appIconImage()
        configureStatusItem()
        observeViewModel()
        startTicker()
        preparePanelAfterLaunch()

        if viewModel.isFirstRun {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController.showFirstRun()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showLaunchAlertIfNeeded()
            }
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

    private func observeViewModel() {
        viewModel.$enabledProviders
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemGlyph(force: true)
            }
            .store(in: &cancellables)
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
            withTitle: "Refresh Usage",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit PromptJuice",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: 0),
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

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func refreshUsage() {
        viewModel.refreshUsage()
        panelController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
