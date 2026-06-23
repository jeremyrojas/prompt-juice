import AppKit
import SwiftUI

enum SettingsWindowMode {
    case settings
    case firstRun
}

@MainActor
final class SettingsWindowState: ObservableObject {
    @Published var mode: SettingsWindowMode = .settings
    @Published var isClaudeSetupPresented = false
    @Published var firstRunEnabledProviders: Set<UsageProvider> = Set(UsageProvider.allCases)
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: PromptJuiceViewModel
    private let onFirstRunFinished: () -> Void
    private let state = SettingsWindowState()
    private var didCenter = false

    init(
        viewModel: PromptJuiceViewModel,
        onFirstRunFinished: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onFirstRunFinished = onFirstRunFinished
        super.init(window: nil)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }

    func show(presentingClaudeSetup: Bool = false) {
        viewModel.refreshClaudeBridgeState()
        viewModel.refreshUsageQuietly()

        let window = ensureWindow()
        state.mode = .settings
        window.title = "PromptJuice Settings"
        NSApp.activate(ignoringOtherApps: true)

        if !didCenter {
            window.center()
            didCenter = true
        }

        window.makeKeyAndOrderFront(nil)

        if presentingClaudeSetup {
            state.isClaudeSetupPresented = false
            DispatchQueue.main.async { [weak self] in
                self?.state.isClaudeSetupPresented = true
            }
        }
    }

    func showFirstRun() {
        viewModel.refreshClaudeBridgeState()
        viewModel.refreshUsageQuietly()

        let window = ensureWindow()
        state.mode = .firstRun
        state.firstRunEnabledProviders = viewModel.enabledProviders
        window.title = "PromptJuice"
        NSApp.activate(ignoringOtherApps: true)

        if !didCenter {
            window.center()
            didCenter = true
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PromptJuice Settings"
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.contentMinSize = NSSize(width: 430, height: 400)
        window.contentMaxSize = NSSize(width: 430, height: 400)
        window.setAccessibilityElement(true)
        window.setAccessibilityRole(.window)
        window.setAccessibilityLabel("PromptJuice Settings")
        window.contentView = NSHostingView(
            rootView: SettingsView(
                viewModel: viewModel,
                state: state,
                onFirstRunContinue: { [weak self] in
                    self?.finishFirstRun()
                }
            )
        )
        self.window = window
        return window
    }

    func finishFirstRun() {
        viewModel.completeFirstRun(enabledProviders: state.firstRunEnabledProviders)
        window?.close()
        state.mode = .settings
        DispatchQueue.main.async { [onFirstRunFinished] in
            onFirstRunFinished()
        }
    }
}
