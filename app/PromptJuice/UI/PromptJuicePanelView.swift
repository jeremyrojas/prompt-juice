import SwiftUI

struct PromptJuicePanelView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let onClose: () -> Void
    let onSnooze: () -> Void

    private let panelWidth: CGFloat = 384
    private var panelHeight: CGFloat {
        viewModel.mode == .alert ? 198 : 166
    }
    private let panelCornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            header
            usageRows

            if viewModel.mode == .alert {
                actions
            }
        }
        .padding(14)
        .frame(width: panelWidth, height: panelHeight)
        .glassPanel(cornerRadius: panelCornerRadius)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().fill(iconColor.opacity(0.16)))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: iconColor.opacity(0.16), radius: 10, x: 0, y: 0)

                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .contentShape(Circle())
            .onTapGesture {
                viewModel.clearSelection()
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
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.clearSelection()
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
            .contentShape(Circle())
            .accessibilityLabel("Close Juicebar")
            .accessibilityHint("Dismisses this usage window.")
        }
    }

    private var usageRows: some View {
        VStack(spacing: 7) {
            ForEach(viewModel.snapshots) { snapshot in
                ProviderUsageRow(
                    snapshot: snapshot,
                    isSelected: viewModel.selectedProvider == snapshot.provider,
                    viewModel: viewModel
                )
            }
        }
    }

    private var actions: some View {
        ActionButton(title: "Snooze", isPrimary: true) {
            onSnooze()
        }
        .accessibilityLabel("Snooze this usage window")
        .accessibilityHint("Keeps PromptJuice quiet for the current demo reset window.")
    }

    private var iconName: String {
        switch viewModel.mode {
        case .manual:
            return "drop.fill"
        case .alert:
            return "bolt.fill"
        case .snoozed:
            return "moon.fill"
        }
    }

    private var iconColor: Color {
        switch viewModel.mode {
        case .manual:
            return .cyan
        case .alert:
            return .green
        case .snoozed:
            return .indigo
        }
    }
}

private struct ActionButton: View {
    let title: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black.opacity(0.9) : Color.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isPrimary ? Color.white.opacity(0.92) : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0 : 0.12), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0 : 0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderUsageRow: View {
    let snapshot: UsageSnapshot
    let isSelected: Bool
    @ObservedObject var viewModel: PromptJuiceViewModel

    var body: some View {
        Button {
            viewModel.selectProvider(snapshot.provider)
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    providerDot

                    Text(snapshot.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    statusChip

                    Spacer()

                    Text(viewModel.percentText(for: snapshot))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .monospacedDigit()

                    Text(viewModel.resetText(for: snapshot))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.shouldUseSoon(for: snapshot) ? Color.red : Color.white.opacity(0.86))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }

                CapacityBar(remainingPercent: snapshot.remainingPercent, color: capacityColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassInset(
                cornerRadius: 14,
                accentColor: isSelected ? capacityColor : nil,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(snapshot.displayName) usage")
        .accessibilityValue("\(viewModel.percentText(for: snapshot)), \(viewModel.resetText(for: snapshot)) before reset")
        .accessibilityHint("Shows details for \(snapshot.displayName).")
    }

    private var providerDot: some View {
        Circle()
            .fill(providerColor)
            .frame(width: 7, height: 7)
            .shadow(color: providerColor.opacity(0.55), radius: 5)
    }

    private var providerColor: Color {
        snapshot.provider == .claude ? .orange : .cyan
    }

    private var capacityColor: Color {
        if viewModel.shouldUseSoon(for: snapshot) {
            return .red
        }

        switch snapshot.remainingPercent {
        case 40...:
            return .green
        case 15..<40:
            return .orange
        default:
            return .red
        }
    }

    private var statusText: String {
        viewModel.statusText(for: snapshot)
    }

    private var statusChip: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(capacityColor)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(capacityColor.opacity(0.14)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(capacityColor.opacity(0.20), lineWidth: 1)
            )
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.black.opacity(0.68),
                            Color.black.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
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
