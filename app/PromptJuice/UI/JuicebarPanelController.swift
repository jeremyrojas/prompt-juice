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

enum PanelClickTarget: Equatable {
    case close
    case settings
    case provider(UsageProvider)
    /// A click on empty panel chrome (header, gaps) — clears any selection
    /// without dismissing the panel.
    case background
}

enum PanelClickRouter {
    private static let horizontalInset: CGFloat = 12
    private static let manualRowsBottomInset: CGFloat = 20
    private static let closeTopInset: CGFloat = 10
    private static let closeTrailingInset: CGFloat = 10
    private static let closeSize: CGFloat = 44

    static func rowRects(
        in bounds: NSRect,
        providers: [UsageProvider]
    ) -> [(provider: UsageProvider, rect: NSRect)] {
        let rowSpacing = PromptJuicePanelMetrics.rowSpacing
        let rowHeight = PromptJuicePanelMetrics.plainRowHeight
        let rowsHeight = CGFloat(providers.count) * rowHeight
            + CGFloat(max(providers.count - 1, 0)) * rowSpacing
        let firstRowTopY = bounds.height - manualRowsBottomInset - rowsHeight
        var rowY = firstRowTopY

        return providers.indices.map { index in
            let rowRect = NSRect(
                x: horizontalInset,
                y: rowY,
                width: bounds.width - horizontalInset * 2,
                height: rowHeight
            )
            rowY += rowHeight + rowSpacing
            return (provider: providers[index], rect: rowRect)
        }
    }

    static func settingsRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.width
                - PromptJuicePanelMetrics.settingsTrailingInset
                - PromptJuicePanelMetrics.settingsHitSize,
            y: bounds.height
                - PromptJuicePanelMetrics.settingsBottomInset
                - PromptJuicePanelMetrics.settingsHitSize,
            width: PromptJuicePanelMetrics.settingsHitSize,
            height: PromptJuicePanelMetrics.settingsHitSize
        )
    }

    static func target(
        at point: NSPoint,
        in bounds: NSRect,
        providers: [UsageProvider]
    ) -> PanelClickTarget? {
        let width = bounds.width

        let closeRect = NSRect(
            x: width - closeTrailingInset - closeSize,
            y: closeTopInset,
            width: closeSize,
            height: closeSize
        )
        if contains(point, in: closeRect) {
            return .close
        }

        if contains(point, in: settingsRect(in: bounds)) {
            return .settings
        }

        for (provider, rowRect) in rowRects(
            in: bounds,
            providers: providers
        ) {
            if contains(point, in: rowRect) {
                return .provider(provider)
            }
        }

        return nil
    }

    private static func contains(_ point: NSPoint, in rect: NSRect) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }
}

@MainActor
private protocol PanelToolTipRefreshing: AnyObject {
    func hidePanelToolTip()
}

private final class ClickReadyHostingView<Content: View>: NSHostingView<Content>, PanelToolTipRefreshing {
    private let providers: () -> [UsageProvider]
    private let toolTipProvider: (UsageProvider) -> String?
    private let onPanelClick: (PanelClickTarget) -> Void
    private let onHoverTargetChanged: (PanelClickTarget?) -> Void
    private let onCancel: () -> Void
    private var trackingArea: NSTrackingArea?
    private var hoveredTarget: PanelClickTarget?
    private var pendingToolTipTask: Task<Void, Never>?
    private var pendingToolTipText: String?
    private var visibleToolTipText: String?
    private var visibleToolTipWindow: NSWindow?

    required init(rootView: Content) {
        self.providers = { [] }
        self.toolTipProvider = { _ in nil }
        self.onPanelClick = { _ in }
        self.onHoverTargetChanged = { _ in }
        self.onCancel = {}
        super.init(rootView: rootView)
        pinCoordinateSpace()
    }

    init(
        rootView: Content,
        providers: @escaping () -> [UsageProvider],
        toolTipProvider: @escaping (UsageProvider) -> String?,
        onPanelClick: @escaping (PanelClickTarget) -> Void,
        onHoverTargetChanged: @escaping (PanelClickTarget?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.toolTipProvider = toolTipProvider
        self.onPanelClick = onPanelClick
        self.onHoverTargetChanged = onHoverTargetChanged
        self.onCancel = onCancel
        super.init(rootView: rootView)
        pinCoordinateSpace()
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
        // Single authority for in-panel clicks. A point that hits no element is
        // the panel background, which clears the current selection.
        onPanelClick(clickTarget(at: point) ?? .background)
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
        let target = clickTarget(at: point)
        setHoveredTarget(target)

        guard let text = panelToolTipText(for: target) else {
            hidePanelToolTip()
            return
        }

        schedulePanelToolTip(text)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredTarget(nil)
        hidePanelToolTip()
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
            providers: providers()
        )
    }

    private func setHoveredTarget(_ target: PanelClickTarget?) {
        guard hoveredTarget != target else {
            return
        }

        hoveredTarget = target
        onHoverTargetChanged(target)
    }

    private func pinCoordinateSpace() {
        // NSHostingView exposes top-down hit-test coordinates. Make that
        // contract explicit so mouseUp, mouseMoved, and PanelClickRouter share
        // the visual layout coordinate space.
        isFlipped = true
    }

    private func panelToolTipText(for target: PanelClickTarget?) -> String? {
        guard let target else {
            return nil
        }

        switch target {
        case .provider(let provider):
            return toolTipProvider(provider)
        case .settings:
            return "Settings"
        case .close, .background:
            return nil
        }
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

final class PanelToolTipView: NSView {
    private let text: String
    private let font = NSFont.systemFont(ofSize: 12)
    private let contentInsets = NSEdgeInsets(top: 5, left: 8, bottom: 6, right: 8)
    private static let maxTextWidth: CGFloat = 280

    override var isFlipped: Bool {
        true
    }

    override var fittingSize: NSSize {
        frame.size
    }

    init(text: String) {
        self.text = text
        let textSize = Self.textSize(for: text, font: font)
        let size = NSSize(
            width: textSize.width + contentInsets.left + contentInsets.right,
            height: textSize.height + contentInsets.top + contentInsets.bottom
        )

        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        effectiveAppearance.performAsCurrentDrawingAppearance {
            (text as NSString).draw(
                with: textDrawingRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: Self.textAttributes(font: font, color: .labelColor)
            )
        }
    }

    private var textDrawingRect: NSRect {
        NSRect(
            x: contentInsets.left,
            y: contentInsets.top,
            width: bounds.width - contentInsets.left - contentInsets.right,
            height: bounds.height - contentInsets.top - contentInsets.bottom
        )
    }

    private static func textSize(for text: String, font: NSFont) -> NSSize {
        let textRect = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes(font: font, color: .labelColor)
        )
        return NSSize(
            width: min(maxTextWidth, ceil(textRect.width) + 4),
            height: ceil(textRect.height)
        )
    }

    private static func textAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class JuicebarPanelController {
    private let viewModel: PromptJuiceViewModel
    private let onClaudeSettingsRequested: (Bool) -> Void
    private let onSettingsRequested: () -> Void
    private var panel: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    private var panelSize: NSSize {
        NSSize(
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(
                rowCount: viewModel.visibleSnapshots.count
            )
        )
    }

    var panelFrameForTesting: NSRect? {
        panel?.frame
    }

    func clickTargetForTesting(_ target: PanelClickTarget) {
        handleClick(target)
    }

    init(
        viewModel: PromptJuiceViewModel,
        onClaudeSettingsRequested: @escaping (Bool) -> Void = { _ in },
        onSettingsRequested: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onClaudeSettingsRequested = onClaudeSettingsRequested
        self.onSettingsRequested = onSettingsRequested

        viewModel.$enabledProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPanelFrameIfVisible(force: true)
            }
            .store(in: &cancellables)

        viewModel.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPanelFrameIfVisible(force: false)
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
        viewModel.refreshClaudeStatusCacheNow(reason: "panel open")
        let panel = ensurePanel()
        applyPanelFrame(panel, force: true)
        installEventMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func hide() {
        (panel?.contentView as? PanelToolTipRefreshing)?.hidePanelToolTip()
        viewModel.setHoveredPanelTarget(nil)
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
            }
        )

        panel.contentView = ClickReadyHostingView(
            rootView: rootView,
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
            onHoverTargetChanged: { [weak viewModel] target in
                viewModel?.setHoveredPanelTarget(target)
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
        case .settings:
            dismissSurface()
            onSettingsRequested()
        case .provider(let provider):
            if provider == .claude, viewModel.claudeRowOffersSetup {
                dismissSurface()
                onClaudeSettingsRequested(true)
                return
            }
        case .background:
            viewModel.clearSelection()
        }
    }

    private func dismissSurface() {
        viewModel.dismissCurrentWindow()
        hide()
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

        // Inside the panel: let the content view's mouseUp handle it, so a single
        // press toggles selection exactly once instead of firing on both the
        // mouseDown monitor and the mouseUp responder.
        return false
    }

    private func applyPanelFrameIfVisible(force: Bool) {
        guard let panel, panel.isVisible else {
            return
        }

        applyPanelFrame(panel, force: force)
    }

    private func applyPanelFrame(_ panel: NSWindow, force: Bool) {
        let size = panelSize
        if !force, panel.frame.size == size {
            return
        }

        position(panel, size: size)
    }

    private func position(_ panel: NSWindow, size: NSSize) {
        let screen = targetScreen()
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 10
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let screenUnderCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderCursor
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
