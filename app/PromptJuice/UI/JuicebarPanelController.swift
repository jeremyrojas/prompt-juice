import AppKit
import Combine
import SwiftUI

private let panelDragThreshold: CGFloat = 3

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
    case provider(UsageProvider)
    /// The "Turn on notifications" CTA in the just-in-time prime banner.
    case enableNotifications
    /// The "Not now" label in the just-in-time prime banner.
    case dismissNotificationPrime
    /// A click on empty panel chrome (header, gaps) — clears any selection
    /// without dismissing the panel.
    case background
}

enum JuicebarPanelMode: Equatable {
    case anchored
    case pinned
}

enum PanelClickRouter {
    private static let horizontalInset: CGFloat = 12
    private static let manualRowsTopInset: CGFloat = 54
    private static let closeTopInset: CGFloat = 10
    private static let closeTrailingInset: CGFloat = 10
    private static let closeSize: CGFloat = 44

    static func rowRects(
        in bounds: NSRect,
        providers: [UsageProvider]
    ) -> [(provider: UsageProvider, rect: NSRect)] {
        let rowSpacing = PromptJuicePanelMetrics.rowSpacing
        let rowHeight = PromptJuicePanelMetrics.plainRowHeight
        var rowY = manualRowsTopInset

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

    /// Hit-rects for the two prime-banner labels, derived from the same metrics
    /// the SwiftUI banner lays out with so the tap targets track the pixels.
    static func notificationPrimeButtonRects(
        in bounds: NSRect,
        rowCount: Int
    ) -> (enable: NSRect, dismiss: NSRect) {
        let rows = max(rowCount, 1)
        let rowBlock = CGFloat(rows) * PromptJuicePanelMetrics.plainRowHeight
            + CGFloat(max(rows - 1, 0)) * PromptJuicePanelMetrics.rowSpacing
        let bannerTop = manualRowsTopInset + rowBlock + PromptJuicePanelMetrics.contentSpacing
        let buttonsTop = bannerTop
            + PromptJuicePanelMetrics.primeBannerHeight
            - PromptJuicePanelMetrics.primeCardPadding
            - PromptJuicePanelMetrics.primeButtonHeight
        let innerRight = bounds.width
            - PromptJuicePanelMetrics.contentPadding
            - PromptJuicePanelMetrics.primeCardPadding

        let enable = NSRect(
            x: innerRight - PromptJuicePanelMetrics.primeEnableButtonWidth,
            y: buttonsTop,
            width: PromptJuicePanelMetrics.primeEnableButtonWidth,
            height: PromptJuicePanelMetrics.primeButtonHeight
        )
        let dismiss = NSRect(
            x: enable.minX
                - PromptJuicePanelMetrics.primeButtonSpacing
                - PromptJuicePanelMetrics.primeDismissButtonWidth,
            y: buttonsTop,
            width: PromptJuicePanelMetrics.primeDismissButtonWidth,
            height: PromptJuicePanelMetrics.primeButtonHeight
        )
        return (enable, dismiss)
    }

    static func target(
        at point: NSPoint,
        in bounds: NSRect,
        providers: [UsageProvider],
        showsNotificationPrime: Bool = false
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

        if showsNotificationPrime {
            let rects = notificationPrimeButtonRects(in: bounds, rowCount: providers.count)
            if contains(point, in: rects.enable.insetBy(dx: -4, dy: -8)) {
                return .enableNotifications
            }
            if contains(point, in: rects.dismiss.insetBy(dx: -4, dy: -8)) {
                return .dismissNotificationPrime
            }
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

@MainActor
private protocol PanelContentRootView: PanelToolTipRefreshing {
    var interactiveContentView: NSView { get }
}

private final class ClickReadyHostingView<Content: View>: NSHostingView<Content>, PanelToolTipRefreshing {
    private let providers: () -> [UsageProvider]
    private let showsNotificationPrime: () -> Bool
    private let toolTipProvider: (UsageProvider) -> String?
    private let onPanelClick: (PanelClickTarget) -> Void
    private let onHoverTargetChanged: (PanelClickTarget?) -> Void
    private let onCancel: () -> Void
    private let onPanelDragStarted: () -> Void
    private let onPanelDragged: (NSPoint) -> Void
    private var trackingArea: NSTrackingArea?
    private var hoveredTarget: PanelClickTarget?
    private var pendingToolTipTask: Task<Void, Never>?
    private var pendingToolTipText: String?
    private var visibleToolTipText: String?
    private var visibleToolTipWindow: NSWindow?
    private var mouseDownTarget: PanelClickTarget?
    private var dragStartScreenPoint: NSPoint?
    private var dragStartFrameOrigin: NSPoint?
    private var isDraggingPanel = false

    required init(rootView: Content) {
        self.providers = { [] }
        self.showsNotificationPrime = { false }
        self.toolTipProvider = { _ in nil }
        self.onPanelClick = { _ in }
        self.onHoverTargetChanged = { _ in }
        self.onCancel = {}
        self.onPanelDragStarted = {}
        self.onPanelDragged = { _ in }
        super.init(rootView: rootView)
        pinCoordinateSpace()
    }

    init(
        rootView: Content,
        providers: @escaping () -> [UsageProvider],
        showsNotificationPrime: @escaping () -> Bool,
        toolTipProvider: @escaping (UsageProvider) -> String?,
        onPanelClick: @escaping (PanelClickTarget) -> Void,
        onHoverTargetChanged: @escaping (PanelClickTarget?) -> Void,
        onCancel: @escaping () -> Void,
        onPanelDragStarted: @escaping () -> Void,
        onPanelDragged: @escaping (NSPoint) -> Void
    ) {
        self.providers = providers
        self.showsNotificationPrime = showsNotificationPrime
        self.toolTipProvider = toolTipProvider
        self.onPanelClick = onPanelClick
        self.onHoverTargetChanged = onHoverTargetChanged
        self.onCancel = onCancel
        self.onPanelDragStarted = onPanelDragStarted
        self.onPanelDragged = onPanelDragged
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
        let point = convert(event.locationInWindow, from: nil)
        mouseDownTarget = clickTarget(at: point)
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartFrameOrigin = window?.frame.origin
        isDraggingPanel = false
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDownTarget == nil,
              let dragStartScreenPoint,
              let dragStartFrameOrigin,
              let window else {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let delta = NSPoint(
            x: screenPoint.x - dragStartScreenPoint.x,
            y: screenPoint.y - dragStartScreenPoint.y
        )

        if !isDraggingPanel {
            let distance = hypot(delta.x, delta.y)
            guard distance >= panelDragThreshold else {
                return
            }

            isDraggingPanel = true
            onPanelDragStarted()
        }

        let origin = NSPoint(
            x: dragStartFrameOrigin.x + delta.x,
            y: dragStartFrameOrigin.y + delta.y
        )
        window.setFrameOrigin(origin)
        onPanelDragged(origin)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownTarget = nil
            dragStartScreenPoint = nil
            dragStartFrameOrigin = nil
            isDraggingPanel = false
        }

        guard !isDraggingPanel else {
            return
        }

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
        hideVisiblePanelToolTip()
    }

    private func hideVisiblePanelToolTip() {
        visibleToolTipText = nil
        visibleToolTipWindow?.orderOut(nil)
        visibleToolTipWindow = nil
    }

    private func clickTarget(at point: NSPoint) -> PanelClickTarget? {
        PanelClickRouter.target(
            at: point,
            in: bounds,
            providers: providers(),
            showsNotificationPrime: showsNotificationPrime()
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
        case .close, .background, .enableNotifications, .dismissNotificationPrime:
            return nil
        }
    }

    private func schedulePanelToolTip(_ text: String) {
        guard visibleToolTipText != text, pendingToolTipText != text else {
            return
        }

        hideVisiblePanelToolTip()
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
        tooltipWindow.setContentSize(fittingSize)
        tooltipWindow.orderFront(nil)

        visibleToolTipText = text
        visibleToolTipWindow = tooltipWindow
    }
}

private final class MaterialPanelRootView: NSVisualEffectView, PanelContentRootView {
    let interactiveContentView: NSView
    private let toolTipRefreshing: PanelToolTipRefreshing
    private static let roundedRectMaskImage: NSImage = {
        let cornerRadius = PromptJuicePanelMetrics.panelCornerRadius
        let diameter = ceil(cornerRadius * 2 + 1)
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
            return true
        }

        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }()

    init(
        contentView: NSView & PanelToolTipRefreshing,
        cornerRadius: CGFloat
    ) {
        self.interactiveContentView = contentView
        self.toolTipRefreshing = contentView
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
        maskImage = Self.roundedRectMaskImage
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        if #available(macOS 26.0, *) {
            installLiquidGlass(cornerRadius: cornerRadius)
        }
        installInteractiveContent(contentView)
    }

    func hidePanelToolTip() {
        toolTipRefreshing.hidePanelToolTip()
    }

    @available(macOS 26.0, *)
    private func installLiquidGlass(cornerRadius: CGFloat) {
        let glassView = NSGlassEffectView()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.style = .regular
        glassView.cornerRadius = cornerRadius
        glassView.clipsToBounds = true
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = cornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        addSubview(glassView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func installInteractiveContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder: NSCoder) {
        nil
    }
}

final class PanelToolTipView: NSView {
    private let text: String
    private let font = NSFont.systemFont(ofSize: 12)
    private let contentInsets = NSEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
    private let measuredSize: NSSize
    private static let maxTextWidth: CGFloat = 280

    override var isFlipped: Bool {
        true
    }

    override var fittingSize: NSSize {
        measuredSize
    }

    override var intrinsicContentSize: NSSize {
        measuredSize
    }

    init(text: String) {
        self.text = text
        let textSize = Self.textSize(for: text, font: font)
        self.measuredSize = NSSize(
            width: textSize.width + contentInsets.left + contentInsets.right,
            height: textSize.height + contentInsets.top + contentInsets.bottom
        )

        super.init(frame: NSRect(origin: .zero, size: measuredSize))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
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
final class JuicebarPanelController: NSObject {
    private let viewModel: PromptJuiceViewModel
    private let settingsStore: PromptJuiceSettingsStore
    private let onClaudeSettingsRequested: (Bool) -> Void
    private let onSettingsRequested: () -> Void
    private var panel: NSWindow?
    private var panelMode: JuicebarPanelMode = .anchored
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var programmaticFrameUpdateDepth = 0

    private var panelSize: NSSize {
        NSSize(
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(
                rowCount: viewModel.visibleSnapshots.count,
                showsNotificationPrime: viewModel.shouldOfferUseSoonNotificationPrime
            )
        )
    }

    var panelFrameForTesting: NSRect? {
        panel?.frame
    }

    var panelIsVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    var panelContentForwardsToolTipsForTesting: Bool {
        panel?.contentView is PanelToolTipRefreshing
    }

    var panelFirstResponderIsInteractiveContentForTesting: Bool {
        guard let panel,
              let contentView = panel.contentView as? PanelContentRootView else {
            return false
        }

        return panel.firstResponder === contentView.interactiveContentView
    }

    var panelHasShadowForTesting: Bool {
        panel?.hasShadow == true
    }

    var panelAnimationBehaviorForTesting: NSWindow.AnimationBehavior? {
        panel?.animationBehavior
    }

    var panelModeForTesting: JuicebarPanelMode {
        panelMode
    }

    var panelIsMovableForTesting: Bool {
        panel?.isMovable == true
    }

    var panelAllowsBackgroundDraggingForTesting: Bool {
        panel?.isMovableByWindowBackground == true
    }

    var panelContextMenuTitlesForTesting: [String] {
        panel?.contentView?.menu?.items
            .filter { !$0.isSeparatorItem }
            .map(\.title) ?? []
    }

    var isPinned: Bool {
        panelMode == .pinned
    }

    func clickTargetForTesting(_ target: PanelClickTarget) {
        handleClick(target)
    }

    func movePanelOriginForTesting(to origin: NSPoint) {
        guard let panel else {
            return
        }

        panel.setFrameOrigin(origin)
        panelDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
    }

    init(
        viewModel: PromptJuiceViewModel,
        settingsStore: PromptJuiceSettingsStore = .shared,
        onClaudeSettingsRequested: @escaping (Bool) -> Void = { _ in },
        onSettingsRequested: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.settingsStore = settingsStore
        self.onClaudeSettingsRequested = onClaudeSettingsRequested
        self.onSettingsRequested = onSettingsRequested
        super.init()

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

        // The just-in-time prime banner grows the panel; resize when any of its
        // inputs flip (auth status resolving, notifications enabling, or the ask
        // being answered) so the window and the SwiftUI content stay in sync.
        Publishers.Merge3(
            viewModel.$notificationAuthorization.map { _ in () },
            viewModel.$useSoonNotificationsEnabled.map { _ in () },
            viewModel.$didOfferUseSoonNotification.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.applyPanelFrameIfVisible(force: true)
        }
        .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        setPanelMode(.anchored)
        applyPanelFrame(panel, force: true)
        orderFront(panel)
    }

    func pin() {
        viewModel.refreshClaudeStatusCacheNow(reason: "panel pin")
        let panel = ensurePanel()
        let size = panelSize
        let origin = pinnedOrigin(for: panel, size: size)

        setPanelMode(.pinned)
        applyPinnedPanelFrame(panel, origin: origin, size: size, force: true, persist: true)
        orderFront(panel)
    }

    func unpin() {
        let panel = ensurePanel()
        setPanelMode(.anchored)
        applyPanelFrame(panel, force: true)

        if panel.isVisible {
            orderFront(panel)
        }
    }

    func togglePin() {
        if panelMode == .pinned {
            unpin()
        } else {
            pin()
        }
    }

    func hide() {
        (panel?.contentView as? PanelToolTipRefreshing)?.hidePanelToolTip()
        viewModel.setHoveredPanelTarget(nil)
        removeEventMonitors()
        panel?.orderOut(nil)
        setPanelMode(.anchored)
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
        panel.animationBehavior = .none
        panel.title = "PromptJuice Juicebar"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The AppKit material root gives the window server a rounded shape for
        // the native panel shadow.
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = true
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

        let contentView = ClickReadyHostingView(
            rootView: rootView,
            providers: { [weak viewModel] in
                viewModel?.visibleSnapshots.map(\.provider) ?? []
            },
            showsNotificationPrime: { [weak viewModel] in
                viewModel?.shouldOfferUseSoonNotificationPrime ?? false
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
            },
            onPanelDragStarted: { [weak self] in
                self?.handlePanelDragStarted()
            },
            onPanelDragged: { [weak self] origin in
                self?.handlePanelDragged(to: origin)
            }
        )
        panel.contentView = makePanelContentRoot(contentView)
        self.panel = panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        refreshPanelContextMenu()
        return panel
    }

    private func makePanelContentRoot(
        _ contentView: NSView & PanelToolTipRefreshing
    ) -> NSView & PanelContentRootView {
        return MaterialPanelRootView(
            contentView: contentView,
            cornerRadius: PromptJuicePanelMetrics.panelCornerRadius
        )
    }

    private func handleClick(_ target: PanelClickTarget) {
        switch target {
        case .close:
            dismissSurface()
        case .provider(let provider):
            if provider == .claude, viewModel.claudeRowOffersSetup {
                dismissSurface()
                onClaudeSettingsRequested(true)
                return
            }
        case .enableNotifications:
            (panel?.contentView as? PanelToolTipRefreshing)?.hidePanelToolTip()
            viewModel.enableUseSoonNotificationsFromPrime()
            applyPanelFrameIfVisible(force: true)
        case .dismissNotificationPrime:
            viewModel.dismissUseSoonNotificationPrime()
            applyPanelFrameIfVisible(force: true)
        case .background:
            viewModel.clearSelection()
        }
    }

    @objc private func showSettingsFromPanelMenu() {
        (panel?.contentView as? PanelToolTipRefreshing)?.hidePanelToolTip()
        viewModel.setHoveredPanelTarget(nil)
        onSettingsRequested()
    }

    @objc private func togglePinFromPanelMenu() {
        togglePin()
    }

    @objc private func quitFromPanelMenu() {
        NSApp.terminate(nil)
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard programmaticFrameUpdateDepth == 0,
              let movedPanel = notification.object as? NSWindow,
              movedPanel === panel else {
            return
        }

        if panelMode == .anchored {
            setPanelMode(.pinned)
        }

        savePinnedOrigin(movedPanel.frame.origin)
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
            if allowsOutsideDismissal, panelMode == .anchored {
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

        switch panelMode {
        case .anchored:
            position(panel, size: size)
        case .pinned:
            applyPinnedPanelFrame(
                panel,
                origin: panel.frame.origin,
                size: size,
                force: force,
                persist: true
            )
        }
    }

    private func position(_ panel: NSWindow, size: NSSize) {
        setPanelFrame(panel, anchoredFrame(size: size))
    }

    private func applyPinnedPanelFrame(
        _ panel: NSWindow,
        origin: NSPoint,
        size: NSSize,
        force: Bool,
        persist: Bool
    ) {
        let screen = targetScreen(containing: NSRect(origin: origin, size: size))
        let clampedOrigin = clamped(origin: origin, size: size, screen: screen)
        let frame = NSRect(origin: clampedOrigin, size: size)

        if !force, panel.frame == frame {
            return
        }

        setPanelFrame(panel, frame)

        if persist {
            savePinnedOrigin(panel.frame.origin)
        }
    }

    private func setPanelFrame(_ panel: NSWindow, _ frame: NSRect) {
        programmaticFrameUpdateDepth += 1
        panel.setFrame(frame, display: true)
        programmaticFrameUpdateDepth = max(0, programmaticFrameUpdateDepth - 1)
        panel.invalidateShadow()
    }

    private func anchoredFrame(size: NSSize) -> NSRect {
        let frame = targetScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 10
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func pinnedOrigin(for panel: NSWindow, size: NSSize) -> NSPoint {
        if panel.isVisible {
            return panel.frame.origin
        }

        if let savedOrigin = settingsStore.pinnedJuicebarOrigin {
            return NSPoint(x: savedOrigin.x, y: savedOrigin.y)
        }

        return anchoredFrame(size: size).origin
    }

    private func clamped(origin: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let minX = frame.minX
        let maxX = max(frame.minX, frame.maxX - size.width)
        let minY = frame.minY
        let maxY = max(frame.minY, frame.maxY - size.height)

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func targetScreen(containing rect: NSRect? = nil) -> NSScreen? {
        if let rect {
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) {
                return screen
            }

            if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) }) {
                return screen
            }
        }

        let mouseLocation = NSEvent.mouseLocation

        if let screenUnderCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderCursor
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func setPanelMode(_ mode: JuicebarPanelMode) {
        panelMode = mode

        if let panel {
            panel.isMovable = mode == .pinned
            panel.isMovableByWindowBackground = true
        }

        refreshPanelContextMenu()
    }

    private func orderFront(_ panel: NSWindow) {
        installEventMonitors()
        panel.makeKeyAndOrderFront(nil)
        let firstResponder = (panel.contentView as? PanelContentRootView)?.interactiveContentView
            ?? panel.contentView
        panel.makeFirstResponder(firstResponder)
    }

    private func handlePanelDragStarted() {
        guard let panel else {
            return
        }

        if panelMode == .anchored {
            setPanelMode(.pinned)
        }

        savePinnedOrigin(panel.frame.origin)
    }

    private func handlePanelDragged(to origin: NSPoint) {
        guard panelMode == .pinned else {
            return
        }

        savePinnedOrigin(origin)
    }

    private func savePinnedOrigin(_ origin: NSPoint) {
        settingsStore.pinnedJuicebarOrigin = CGPoint(x: origin.x, y: origin.y)
    }

    private var pinMenuItemTitle: String {
        panelMode == .pinned ? "Unpin Juicebar" : "Pin Juicebar"
    }

    private func refreshPanelContextMenu() {
        guard let panel else {
            return
        }

        panel.contentView?.menu = makePanelContextMenu()

        if let contentView = panel.contentView as? PanelContentRootView {
            contentView.interactiveContentView.menu = makePanelContextMenu()
        }
    }

    private func makePanelContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettingsFromPanelMenu),
            keyEquivalent: ","
        ).target = self
        menu.addItem(
            withTitle: pinMenuItemTitle,
            action: #selector(togglePinFromPanelMenu),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit PromptJuice",
            action: #selector(quitFromPanelMenu),
            keyEquivalent: "q"
        ).target = self

        return menu
    }
}
