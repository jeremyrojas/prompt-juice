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
    static func rowRects(
        in bounds: NSRect,
        mode: PanelMode,
        providers: [UsageProvider]
    ) -> [(provider: UsageProvider, rect: NSRect)] {
        let rowHeight = PromptJuicePanelMetrics.rowHeight
        let rowSpacing = PromptJuicePanelMetrics.rowSpacing
        let bottomY: CGFloat = mode == .alert ? 47 : 14

        return providers.indices.map { index in
            let bottomUpIndex = providers.count - 1 - index
            let rowY = bottomY + CGFloat(bottomUpIndex) * (rowHeight + rowSpacing)
            let rowRect = NSRect(x: 12, y: rowY, width: bounds.width - 24, height: rowHeight)
            return (provider: providers[index], rect: rowRect)
        }
    }

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

        for (provider, rowRect) in rowRects(in: bounds, mode: mode, providers: providers) {
            if rowRect.contains(point) {
                return .provider(provider)
            }
        }

        return nil
    }
}

@MainActor
private protocol PanelToolTipRefreshing: AnyObject {
    func refreshToolTips()
    func hidePanelToolTip()
}

private final class ClickReadyHostingView<Content: View>: NSHostingView<Content>, NSViewToolTipOwner, PanelToolTipRefreshing {
    private let modeProvider: () -> PanelMode
    private let providers: () -> [UsageProvider]
    private let toolTipProvider: (UsageProvider) -> String?
    private let onPanelClick: (PanelClickTarget) -> Void
    private let onCancel: () -> Void
    private var toolTipTags: [NSView.ToolTipTag] = []
    private var toolTipTextByTag: [NSView.ToolTipTag: String] = [:]
    private var trackingArea: NSTrackingArea?
    private var pendingToolTipTask: Task<Void, Never>?
    private var pendingToolTipText: String?
    private var visibleToolTipText: String?
    private var visibleToolTipWindow: NSWindow?

    required init(rootView: Content) {
        self.modeProvider = { .manual }
        self.providers = { [] }
        self.toolTipProvider = { _ in nil }
        self.onPanelClick = { _ in }
        self.onCancel = {}
        super.init(rootView: rootView)
    }

    init(
        rootView: Content,
        modeProvider: @escaping () -> PanelMode,
        providers: @escaping () -> [UsageProvider],
        toolTipProvider: @escaping (UsageProvider) -> String?,
        onPanelClick: @escaping (PanelClickTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.modeProvider = modeProvider
        self.providers = providers
        self.toolTipProvider = toolTipProvider
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

    override func layout() {
        super.layout()
        refreshToolTips()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        hidePanelToolTip()
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
        hidePanelToolTip()
        interpretKeyEvents([event])
    }

    override func cancelOperation(_ sender: Any?) {
        hidePanelToolTip()
        onCancel()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        guard let text = rowToolTipText(at: point) else {
            hidePanelToolTip()
            return
        }

        schedulePanelToolTip(text)
    }

    override func mouseExited(with event: NSEvent) {
        hidePanelToolTip()
    }

    func refreshToolTips() {
        toolTipTags.forEach(removeToolTip)
        toolTipTags = []
        toolTipTextByTag = [:]

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let rows = PanelClickRouter.rowRects(
            in: bounds,
            mode: modeProvider(),
            providers: providers()
        )

        for row in rows {
            guard let text = toolTipProvider(row.provider), !text.isEmpty else {
                continue
            }

            let tag = addToolTip(row.rect, owner: self, userData: nil)
            toolTipTags.append(tag)
            toolTipTextByTag[tag] = text
        }
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        toolTipTextByTag[tag] ?? ""
    }

    func hidePanelToolTip() {
        pendingToolTipTask?.cancel()
        pendingToolTipTask = nil
        pendingToolTipText = nil
        visibleToolTipText = nil
        visibleToolTipWindow?.orderOut(nil)
        visibleToolTipWindow = nil
    }

    private func clickTarget(at point: NSPoint) -> PanelClickTarget? {
        PanelClickRouter.target(
            at: point,
            in: bounds,
            mode: modeProvider(),
            providers: providers()
        )
    }

    private func rowToolTipText(at point: NSPoint) -> String? {
        for row in PanelClickRouter.rowRects(in: bounds, mode: modeProvider(), providers: providers()) {
            guard row.rect.contains(point) else {
                continue
            }

            return toolTipProvider(row.provider)
        }

        return nil
    }

    private func schedulePanelToolTip(_ text: String) {
        guard visibleToolTipText != text, pendingToolTipText != text else {
            return
        }

        pendingToolTipTask?.cancel()
        pendingToolTipText = text
        pendingToolTipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled, self.pendingToolTipText == text else {
                return
            }

            self.showPanelToolTip(text)
        }
    }

    private func showPanelToolTip(_ text: String) {
        visibleToolTipWindow?.orderOut(nil)

        let tooltipView = PanelToolTipView(text: text)
        let fittingSize = tooltipView.fittingSize
        let mouseLocation = NSEvent.mouseLocation
        let frame = NSRect(
            x: mouseLocation.x + 12,
            y: mouseLocation.y - fittingSize.height - 12,
            width: fittingSize.width,
            height: fittingSize.height
        )
        let tooltipWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.level = .floating
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.isOpaque = false
        tooltipWindow.hasShadow = true
        tooltipWindow.ignoresMouseEvents = true
        tooltipWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tooltipWindow.contentView = tooltipView
        tooltipWindow.orderFront(nil)

        visibleToolTipText = text
        visibleToolTipWindow = tooltipWindow
    }
}

private final class PanelToolTipView: NSView {
    private let label: NSTextField
    private let contentInsets = NSEdgeInsets(top: 5, left: 8, bottom: 6, right: 8)

    override var fittingSize: NSSize {
        frame.size
    }

    init(text: String) {
        let font = NSFont.systemFont(ofSize: 12)
        let maxTextWidth: CGFloat = 280
        let textRect = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let textSize = NSSize(
            width: ceil(textRect.width),
            height: ceil(textRect.height)
        )
        let size = NSSize(
            width: textSize.width + contentInsets.left + contentInsets.right,
            height: textSize.height + contentInsets.top + contentInsets.bottom
        )

        label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false

        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        addSubview(label)
        label.frame = NSRect(
            x: contentInsets.left,
            y: contentInsets.bottom,
            width: textSize.width,
            height: textSize.height
        )
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class JuicebarPanelController {
    private let viewModel: PromptJuiceViewModel
    private let onClaudeSetupRequested: () -> Void
    private var panel: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var snoozeAutoHideTask: Task<Void, Never>?

    private var panelSize: NSSize {
        NSSize(
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(
                mode: viewModel.mode,
                rowCount: viewModel.visibleSnapshots.count
            )
        )
    }

    init(
        viewModel: PromptJuiceViewModel,
        onClaudeSetupRequested: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onClaudeSetupRequested = onClaudeSetupRequested

        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, panel.isVisible else {
                    return
                }

                self.position(panel)
                self.refreshPanelToolTips()
            }
            .store(in: &cancellables)

        viewModel.$enabledProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, panel.isVisible else {
                    return
                }

                self.position(panel)
                self.refreshPanelToolTips()
            }
            .store(in: &cancellables)

        viewModel.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanelToolTips()
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
        refreshPanelToolTips()
        installEventMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func hide() {
        snoozeAutoHideTask?.cancel()
        (panel?.contentView as? PanelToolTipRefreshing)?.hidePanelToolTip()
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
        panel.acceptsMouseMovedEvents = true
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
                viewModel?.visibleSnapshots.map(\.provider) ?? []
            },
            toolTipProvider: { [weak viewModel] provider in
                guard let snapshot = viewModel?.visibleSnapshots.first(where: { $0.provider == provider }) else {
                    return nil
                }

                return viewModel?.sourceTooltip(for: snapshot)
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
            if provider == .claude, viewModel.isUnavailable(.claude) {
                dismissSurface()
                onClaudeSetupRequested()
            }
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
            providers: viewModel.visibleSnapshots.map(\.provider)
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
        refreshPanelToolTips()
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let screenUnderCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderCursor
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func refreshPanelToolTips() {
        (panel?.contentView as? PanelToolTipRefreshing)?.refreshToolTips()
    }
}
