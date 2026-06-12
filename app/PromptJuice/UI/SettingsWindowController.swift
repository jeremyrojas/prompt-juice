import AppKit
import SwiftUI

enum SettingsWindowMode {
    case settings
}

@MainActor
final class SettingsWindowState: ObservableObject {
    @Published var mode: SettingsWindowMode = .settings
    @Published var isClaudeSetupPresented = false
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: PromptJuiceViewModel
    private let state = SettingsWindowState()
    private var didCenter = false

    init(viewModel: PromptJuiceViewModel) {
        self.viewModel = viewModel
        super.init(window: nil)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }

    func show(presentingClaudeSetup: Bool = false) {
        let window = ensureWindow()
        state.mode = .settings
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

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PromptJuice Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 430, height: 340)
        window.contentMaxSize = NSSize(width: 430, height: 340)
        window.setAccessibilityElement(true)
        window.setAccessibilityRole(.window)
        window.setAccessibilityLabel("PromptJuice Settings")
        window.contentView = NSHostingView(
            rootView: SettingsView(viewModel: viewModel, state: state)
        )
        self.window = window
        return window
    }
}
