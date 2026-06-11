import AppKit
import Combine
import SwiftUI

private final class JuicebarPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private enum PanelClickTarget {
    case close
    case snooze
    case provider(UsageProvider)
}

private enum PanelClickRouter {
    static func target(
        at point: NSPoint,
        in bounds: NSRect,
        mode: PanelMode,
        providers: [UsageProvider]
    ) -> PanelClickTarget? {
        let width = bounds.width
        let height = bounds.height

        let closeRect = NSRect(x: width - 54, y: height - 54, width: 44, height: 44)
        if closeRect.contains(point) {
            return .close
        }

        if mode == .alert {
            let snoozeRect = NSRect(x: 12, y: 8, width: width - 24, height: 38)
            if snoozeRect.contains(point) {
                return .snooze
            }
        }

        let rowHeight: CGFloat = 48
        let rowSpacing: CGFloat = 7
        let bottomY: CGFloat = mode == .alert ? 47 : 14

        for index in providers.indices {
            let bottomUpIndex = providers.count - 1 - index
            let rowY = bottomY + CGFloat(bottomUpIndex) * (rowHeight + rowSpacing)
            let rowRect = NSRect(x: 12, y: rowY, width: width - 24, height: rowHeight)

            if rowRect.contains(point) {
                return .provider(providers[index])
            }
        }

        return nil
    }
}

private final class ClickReadyHostingView<Content: View>: NSHostingView<Content> {
    private let modeProvider: () -> PanelMode
    private let providers: () -> [UsageProvider]
    private let onPanelClick: (PanelClickTarget) -> Void
    private let onCancel: () -> Void

    required init(rootView: Content) {
        self.modeProvider = { .manual }
        self.providers = { [] }
        self.onPanelClick = { _ in }
        self.onCancel = {}
        super.init(rootView: rootView)
    }

    init(
        rootView: Content,
        modeProvider: @escaping () -> PanelMode,
        providers: @escaping () -> [UsageProvider],
        onPanelClick: @escaping (PanelClickTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.modeProvider = modeProvider
        self.providers = providers
        self.onPanelClick = onPanelClick
        self.onCancel = onCancel
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let target = clickTarget(at: point) {
            onPanelClick(target)
            return
        }

        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    private func clickTarget(at point: NSPoint) -> PanelClickTarget? {
        PanelClickRouter.target(
            at: point,
            in: bounds,
            mode: modeProvider(),
            providers: providers()
        )
    }
}

@MainActor
final class JuicebarPanelController {
    private let viewModel: PromptJuiceViewModel
    private var panel: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var snoozeAutoHideTask: Task<Void, Never>?

    private var panelSize: NSSize {
        NSSize(width: 384, height: viewModel.mode == .alert ? 198 : 166)
    }

    init(viewModel: PromptJuiceViewModel) {
        self.viewModel = viewModel

        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, panel.isVisible else {
                    return
                }

                self.position(panel)
            }
            .store(in: &cancellables)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func prepare() {
        _ = ensurePanel()
    }

    func show() {
        let panel = ensurePanel()
        snoozeAutoHideTask?.cancel()
        position(panel)
        installEventMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func hide() {
        snoozeAutoHideTask?.cancel()
        removeEventMonitors()
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSWindow {
        if let panel {
            return panel
        }

        let panel = JuicebarPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.onCancel = { [weak self] in
            self?.dismissSurface()
        }
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.title = "PromptJuice Juicebar"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityElement(true)
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityLabel("PromptJuice Juicebar")

        let rootView = PromptJuicePanelView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.handleClick(.close)
            },
            onSnooze: { [weak self] in
                self?.handleClick(.snooze)
            }
        )

        panel.contentView = ClickReadyHostingView(
            rootView: rootView,
            modeProvider: { [weak viewModel] in
                viewModel?.mode ?? .manual
            },
            providers: { [weak viewModel] in
                viewModel?.snapshots.map(\.provider) ?? []
            },
            onPanelClick: { [weak self] target in
                self?.handleClick(target)
            },
            onCancel: { [weak self] in
                self?.dismissSurface()
            }
        )
        self.panel = panel
        return panel
    }

    private func handleClick(_ target: PanelClickTarget) {
        switch target {
        case .close:
            dismissSurface()
        case .snooze:
            viewModel.snooze()
            scheduleSnoozeAutoHide()
        case .provider(let provider):
            viewModel.selectProvider(provider)
        }
    }

    private func dismissSurface() {
        viewModel.dismissCurrentWindow()
        hide()
    }

    private func scheduleSnoozeAutoHide() {
        snoozeAutoHideTask?.cancel()
        snoozeAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.hide()
        }
    }

    private func installEventMonitors() {
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else {
                    return event
                }

                return self.handleMouseEvent(event, allowsOutsideDismissal: false) ? nil : event
            }
        }

        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else {
                    return event
                }

                return self.handleKeyEvent(event) ? nil : event
            }
        }

        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                _ = self?.handleMouseEvent(event, allowsOutsideDismissal: true)
            }
        }
    }

    private func removeEventMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else {
            return false
        }

        if event.keyCode == 53 {
            dismissSurface()
            return true
        }

        return false
    }

    private func handleMouseEvent(
        _ event: NSEvent,
        allowsOutsideDismissal: Bool
    ) -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }

        let screenPoint: NSPoint
        if event.window == panel {
            screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = NSEvent.mouseLocation
        }

        guard panel.frame.contains(screenPoint) else {
            if allowsOutsideDismissal {
                dismissSurface()
            }

            return false
        }

        let localPoint = NSPoint(
            x: screenPoint.x - panel.frame.minX,
            y: screenPoint.y - panel.frame.minY
        )

        guard let target = PanelClickRouter.target(
            at: localPoint,
            in: NSRect(origin: .zero, size: panel.frame.size),
            mode: viewModel.mode,
            providers: viewModel.snapshots.map(\.provider)
        ) else {
            return false
        }

        handleClick(target)
        return true
    }

    private func position(_ panel: NSWindow) {
        let screen = targetScreen()
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = frame.midX - panelSize.width / 2
        let y = frame.maxY - panelSize.height - 10
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let screenUnderCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderCursor
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
