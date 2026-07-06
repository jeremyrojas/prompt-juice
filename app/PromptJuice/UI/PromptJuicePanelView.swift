import SwiftUI

enum PromptJuicePanelMetrics {
    static let width: CGFloat = 384
    static let plainRowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 7
    static let settingsHitSize: CGFloat = 22
    static let settingsHeightIncrement: CGFloat = 30
    static let settingsBottomInset: CGFloat = 8
    static let settingsTrailingInset: CGFloat = 14

    static func height(rowCount: Int) -> CGFloat {
        let rows = max(rowCount, 1)
        let rowBlockHeight = CGFloat(rows) * plainRowHeight
            + CGFloat(max(rows - 1, 0)) * rowSpacing
        return 63 + rowBlockHeight + settingsHeightIncrement
    }
}

struct PromptJuicePanelView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let onClose: () -> Void

    private var panelHeight: CGFloat {
        PromptJuicePanelMetrics.height(
            rowCount: viewModel.visibleSnapshots.count
        )
    }
    private let panelCornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            header
            usageRows
        }
        .padding(14)
        .frame(width: PromptJuicePanelMetrics.width, height: panelHeight, alignment: .top)
        .glassPanel(cornerRadius: panelCornerRadius)
        .overlay(alignment: .bottomTrailing) {
            settingsGear
                .padding(.trailing, PromptJuicePanelMetrics.settingsTrailingInset)
                .padding(.bottom, PromptJuicePanelMetrics.settingsBottomInset)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().fill(headerTint.opacity(0.16)))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: headerTint.opacity(0.16), radius: 10, x: 0, y: 0)

                headerGlyph
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.actionMessage ?? viewModel.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.055)))
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .contentShape(Circle())
            .accessibilityLabel("Close Juicebar")
            .accessibilityHint("Dismisses this usage window.")
        }
    }

    private var usageRows: some View {
        VStack(spacing: 7) {
            ForEach(viewModel.visibleSnapshots) { snapshot in
                ProviderUsageRow(snapshot: snapshot, viewModel: viewModel)
            }
        }
    }

    private var settingsGear: some View {
        let isHovered = viewModel.hoveredPanelTarget == .settings

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 1 : 0)
                .overlay(Circle().fill(Color.white.opacity(isHovered ? 0.065 : 0)))

            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.40))
        }
            .frame(
                width: PromptJuicePanelMetrics.settingsHitSize,
                height: PromptJuicePanelMetrics.settingsHitSize
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.12 : 0), lineWidth: 1))
            .contentShape(Circle())
            .accessibilityLabel("Settings")
    }

    private var headerTint: Color {
        return viewModel.headerSeverity.tint
    }

    private var headerGlyph: some View {
        DropletGauge(
            remaining: viewModel.headerRemainingPercent / 100,
            tint: headerTint,
            lineWidth: 1.6
        )
        .frame(width: 17, height: 19)
    }
}

private struct ProviderUsageRow: View {
    let snapshot: UsageSnapshot
    @ObservedObject var viewModel: PromptJuiceViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                providerDot

                Text(snapshot.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(snapshot.isAvailable ? 0.88 : 0.6))

                statusChip

                Spacer()

                trailing
            }

            if snapshot.isAvailable {
                CapacityBar(remainingPercent: snapshot.sessionRemainingPercent, color: severityColor)
            } else {
                ghostBar
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: PromptJuicePanelMetrics.plainRowHeight)
        .glassInset(
            cornerRadius: 14,
            accentColor: isSelected ? providerColor : nil,
            isSelected: isSelected
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(snapshot.displayName) juice")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var trailing: some View {
        if snapshot.isFreshSessionWindow {
            Text("Fresh window")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        } else if snapshot.isAvailable {
            resetCluster
        } else {
            Text(unavailableLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            if snapshot.provider == .claude,
               viewModel.claudeRowOffersSetup {
                setUpCue
            }
        }
    }

    private var isRefreshing: Bool {
        viewModel.isRefreshing(snapshot.provider)
    }

    private var unavailableLabel: String {
        if isRefreshing {
            return "Checking…"
        }

        if snapshot.provider == .claude,
           viewModel.claudeLiveUpgrade == .awaitingSession {
            return "Waiting for terminal"
        }

        return "Not measured yet"
    }

    private var setUpCue: some View {
        Text("Set up")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(
                Capsule(style: .continuous).fill(Color.white.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    private var ghostBar: some View {
        Capsule()
            .fill(Color.white.opacity(0.06))
            .frame(height: 6)
            .accessibilityHidden(true)
    }

    private var providerDot: some View {
        Circle()
            .fill(providerColor)
            .frame(width: 7, height: 7)
            .opacity(snapshot.isAvailable ? 1 : 0.4)
            .shadow(color: providerColor.opacity(snapshot.isAvailable ? 0.55 : 0), radius: 5)
    }

    private var providerColor: Color {
        snapshot.provider == .claude ? .orange : .cyan
    }

    private var isSelected: Bool {
        viewModel.selectedProvider == snapshot.provider
    }

    private var severity: UsageSeverity {
        viewModel.severity(for: snapshot)
    }

    private var severityColor: Color {
        severity.tint
    }

    /// Estimates get a leading `~`; the only visible tell that a reading is a guess.
    private var percentLabel: String {
        viewModel.sessionRemainingPercentDisplayValueText(for: snapshot)
    }

    @ViewBuilder
    private var resetCluster: some View {
        HStack(spacing: 5) {
            Text(percentLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .monospacedDigit()

            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))

            Text(viewModel.fullResetText(for: snapshot))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(severity.isAlerting ? severityColor : Color.white.opacity(0.86))
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// One-alert model: only the amber use-soon nudge gets a chip.
    @ViewBuilder
    private var statusChip: some View {
        if let label = severity.chipText {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(severityColor)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule(style: .continuous).fill(severityColor.opacity(0.14)))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(severityColor.opacity(0.20), lineWidth: 1)
                )
        }
    }

    private var accessibilityValue: String {
        snapshot.isAvailable
            ? "\(viewModel.sessionRemainingPercentText(for: snapshot)), \(viewModel.fullResetText(for: snapshot))"
            : unavailableLabel
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        background(PanelMaterial(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.045),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 210
                    )
                )
                .blendMode(.screen)
        }
        .shadow(color: .black.opacity(0.52), radius: 26, x: 0, y: 18)
    }

    func glassInset(cornerRadius: CGFloat, accentColor: Color?, isSelected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.075 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    accentColor?.opacity(0.40) ?? Color.white.opacity(0.075),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.18 : 0.10), lineWidth: 1)
                .blendMode(.screen)
        }
        .shadow(
            color: (accentColor ?? Color.black).opacity(isSelected ? 0.15 : 0.04),
            radius: isSelected ? 10 : 3,
            x: 0,
            y: 0
        )
    }
}

private struct CapacityBar: View {
    let remainingPercent: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let fillWidth = geometry.size.width * min(1, max(0, remainingPercent / 100))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(0.92),
                                color.opacity(0.46)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, fillWidth))

                Capsule()
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
