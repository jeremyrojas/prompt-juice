import SwiftUI

struct ProviderSetupWindowView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Connect Providers")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Text("PromptJuice shows how much Claude and Codex juice is left before reset.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }

            VStack(spacing: 12) {
                ForEach(viewModel.providerSetupSummaries) { summary in
                    ProviderSetupRow(
                        summary: summary,
                        lastCheckedText: viewModel.lastCheckedText(for: summary),
                        primaryAction: {
                            viewModel.performProviderSetupAction(for: summary.provider)
                        },
                        secondaryAction: {
                            onOpenSettings()
                        }
                    )
                }
            }

            HStack(spacing: 12) {
                Label("Local data only. No account changes.", systemImage: "lock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                Button("Provider Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .glassButton()

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))
                .padding(.horizontal, 24)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
            }
        }
        .padding(34)
        .frame(width: 760, height: 500)
        .promptJuiceWindowGlass(cornerRadius: 28)
    }
}

struct ProviderSettingsWindowView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let onOpenSetup: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Providers")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Choose which local sources PromptJuice uses for reset and usage readings.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                VStack(spacing: 12) {
                    ForEach(viewModel.providerSetupSummaries) { summary in
                        ProviderSettingsCard(
                            summary: summary,
                            lastCheckedText: viewModel.lastCheckedText(for: summary),
                            refreshAction: {
                                viewModel.performProviderSetupAction(for: summary.provider)
                            },
                            setupAction: onOpenSetup
                        )
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock")
                    Text("PromptJuice reads local provider data and stores normalized usage snapshots.")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 780, height: 520)
        .promptJuiceWindowGlass(cornerRadius: 24)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("PromptJuice", systemImage: "drop.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.bottom, 8)

            SidebarItem(title: "Providers", systemImage: "bolt.horizontal.fill", isSelected: true)
            SidebarItem(title: "Alerts", systemImage: "bell.badge", isSelected: false)
            SidebarItem(title: "Privacy", systemImage: "lock", isSelected: false)

            Spacer()
        }
        .padding(18)
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
    }
}

private struct ProviderSetupRow: View {
    let summary: ProviderSetupSummary
    let lastCheckedText: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ProviderGlyph(provider: summary.provider)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.identity.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    ProviderStatusPill(state: summary.state)
                }

                Text(summary.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))

                Text(summary.helper)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                Text(lastCheckedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))

                HStack(spacing: 8) {
                    if let secondaryActionTitle = summary.secondaryActionTitle {
                        Button(secondaryActionTitle) {
                            secondaryAction()
                        }
                        .providerSecondaryButton()
                    }

                    Button(summary.primaryActionTitle) {
                        primaryAction()
                    }
                    .providerPrimaryButton()
                }
            }
        }
        .padding(16)
        .frame(minHeight: 116)
        .providerGlassCard(accentColor: providerAccent)
    }

    private var providerAccent: Color {
        summary.provider == .codex ? .cyan : .orange
    }
}

private struct ProviderSettingsCard: View {
    let summary: ProviderSetupSummary
    let lastCheckedText: String
    let refreshAction: () -> Void
    let setupAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProviderGlyph(provider: summary.provider, size: 34, iconSize: 15)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(summary.identity.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)

                        ProviderStatusPill(state: summary.state)
                    }

                    Text(summary.headline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Toggle("", isOn: .constant(summary.isUsable))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(true)
            }

            HStack(spacing: 16) {
                ProviderMetadata(title: "Source", value: summary.sourceTitle)
                ProviderMetadata(title: "Updated", value: lastCheckedText.replacingOccurrences(of: "Last checked ", with: ""))

                Spacer()

                Button("Refresh") {
                    refreshAction()
                }
                .providerSecondaryButton()

                Button(summary.secondaryActionTitle ?? "Details") {
                    setupAction()
                }
                .providerSecondaryButton()
            }
        }
        .padding(15)
        .providerGlassCard(accentColor: summary.provider == .codex ? .cyan : .orange)
    }
}

private struct ProviderMetadata: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.38))
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
    }
}

struct ProviderStatusPill: View {
    let state: ProviderSetupState

    var body: some View {
        Text(state.rawValue)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(color.opacity(0.15)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.24), lineWidth: 1)
            )
    }

    private var color: Color {
        switch state {
        case .exact:
            return .green
        case .estimated:
            return .orange
        case .stale:
            return .gray
        case .unavailable:
            return .red
        }
    }
}

private struct ProviderGlyph: View {
    let provider: UsageProvider
    var size: CGFloat = 52
    var iconSize: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(accent.opacity(0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.22), radius: 14)

            Image(systemName: provider == .codex ? "cube" : "sparkles")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }

    private var accent: Color {
        provider == .codex ? .cyan : .orange
    }
}

private extension Button {
    @MainActor
    func providerPrimaryButton() -> some View {
        buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
    }

    @MainActor
    func providerSecondaryButton() -> some View {
        buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassButton()
    }
}

private extension View {
    @MainActor
    func promptJuiceWindowGlass(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.black.opacity(0.50),
                            Color.black.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: 360
                    )
                )
                .blendMode(.screen)
        }
    }

    @MainActor
    func providerGlassCard(accentColor: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.20), lineWidth: 1)
                .blendMode(.screen)
        }
    }

    @MainActor
    func glassButton() -> some View {
        background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.055)))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
