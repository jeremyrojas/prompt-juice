import AppKit
import SwiftUI

enum SettingsWindowMetrics {
    static let width: CGFloat = 430
    static let height: CGFloat = 494
}

struct SettingsView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    @ObservedObject var state: SettingsWindowState
    let onFirstRunContinue: () -> Void

    var body: some View {
        Group {
            switch state.mode {
            case .settings:
                settingsForm
            case .firstRun:
                firstRunView
            }
        }
        .frame(width: SettingsWindowMetrics.width, height: SettingsWindowMetrics.height)
        .sheet(item: $state.claudeGuidanceJourney) { journey in
            ClaudeGuidanceSheetView(
                viewModel: viewModel,
                initialJourney: journey,
                onDone: {
                    state.claudeGuidanceJourney = nil
                }
            )
        }
    }

    private var settingsForm: some View {
        Form {
            providersSection
            useJuiceSection
        }
        .formStyle(.grouped)
    }

    private var firstRunView: some View {
        VStack(spacing: 0) {
            welcomeHeader

            Form {
                firstRunProvidersSection
            }
            .formStyle(.grouped)
            .frame(height: 174)

            HStack {
                Spacer()

                Button("Continue", action: onFirstRunContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.firstRunEnabledProviders.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private var welcomeHeader: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(JuicePalette.green.opacity(0.16))
                    .frame(width: 54, height: 54)

                DropletGauge(
                    remaining: 0.92,
                    tint: JuicePalette.green,
                    lineWidth: 2
                )
                .frame(width: 25, height: 29)
            }

            Text("Welcome to PromptJuice")
                .font(.title3.weight(.semibold))

            Text("Toggle on the AI tools that you use. Change anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private var providersSection: some View {
        Section {
            ForEach(UsageProvider.allCases) { provider in
                ProviderSettingsRow(
                    provider: provider,
                    viewModel: viewModel,
                    isEnabled: settingsProviderBinding(for: provider),
                    isToggleDisabled: isLastEnabledProvider(provider),
                    onClaudeAction: handleClaudeAction
                )
            }
        } header: {
            Text("Providers")
        }
    }

    private var firstRunProvidersSection: some View {
        Section {
            ForEach(UsageProvider.allCases) { provider in
                ProviderSettingsRow(
                    provider: provider,
                    viewModel: viewModel,
                    isEnabled: firstRunProviderBinding(for: provider),
                    isToggleDisabled: isFirstRunLastEnabledProvider(provider),
                    onClaudeAction: handleClaudeAction
                )
            }
        }
    }

    @ViewBuilder
    private var useJuiceSection: some View {
        Section {
            UseJuiceThresholdRows(viewModel: viewModel)
        } header: {
            Text("Use the juice")
        } footer: {
            Text("Turns your menu-bar droplet orange when a usage limit window is this close to resetting.")
                .font(.footnote)
        }

        Section {
            Toggle(isOn: useSoonNotificationsBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me")

                    Text("Sends a macOS notification to use your juice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if viewModel.showsNotificationAuthorizationHint {
                Text("Notifications are turned off for PromptJuice — turn them on in System Settings → Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var useSoonNotificationsBinding: Binding<Bool> {
        Binding {
            viewModel.useSoonNotificationsEnabled
        } set: { enabled in
            viewModel.setUseSoonNotificationsEnabled(enabled)
        }
    }

    private func settingsProviderBinding(for provider: UsageProvider) -> Binding<Bool> {
        Binding {
            viewModel.enabledProviders.contains(provider)
        } set: { enabled in
            viewModel.setProviderEnabled(provider, enabled)
        }
    }

    private func firstRunProviderBinding(for provider: UsageProvider) -> Binding<Bool> {
        Binding {
            state.firstRunEnabledProviders.contains(provider)
        } set: { enabled in
            var next = state.firstRunEnabledProviders
            if enabled {
                next.insert(provider)
            } else {
                next.remove(provider)
            }
            state.firstRunEnabledProviders = next
        }
    }

    private func isLastEnabledProvider(_ provider: UsageProvider) -> Bool {
        viewModel.enabledProviders.count == 1
            && viewModel.enabledProviders.contains(provider)
    }

    private func isFirstRunLastEnabledProvider(_ provider: UsageProvider) -> Bool {
        state.firstRunEnabledProviders.count == 1
            && state.firstRunEnabledProviders.contains(provider)
    }

    private func handleClaudeAction(_ action: ClaudeSettingsAction) {
        switch action {
        case .journey(let journey):
            state.claudeGuidanceJourney = journey
        case .retry:
            viewModel.refreshUsage()
        }
    }
}

private struct ProviderSettingsRow: View {
    let provider: UsageProvider
    @ObservedObject var viewModel: PromptJuiceViewModel
    let isEnabled: Binding<Bool>
    let isToggleDisabled: Bool
    let onClaudeAction: (ClaudeSettingsAction) -> Void
    var usesPreviewToggle = false
    @State private var isClaudeInfoPresented = false

    var body: some View {
        let isProviderEnabled = isEnabled.wrappedValue

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(provider == .claude ? Color.orange : Color.cyan)
                    .frame(width: 9, height: 9)
                    .opacity(isProviderEnabled ? 1 : 0.35)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(.body)
                        .foregroundStyle(isProviderEnabled ? .primary : .tertiary)
                    HStack(spacing: 4) {
                        Text(isProviderEnabled ? viewModel.settingsStatusText(for: provider) : "Off")
                            .font(.caption)
                            .foregroundStyle(isProviderEnabled ? .secondary : .tertiary)

                        if isProviderEnabled,
                           provider == .claude,
                           viewModel.shouldShowClaudeMeasurementInfo {
                            Button {
                                isClaudeInfoPresented = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("How this number is measured")
                            .popover(isPresented: $isClaudeInfoPresented, arrowEdge: .trailing) {
                                ClaudeMeasurementPopover(
                                    viewModel: viewModel,
                                    onClaudeAction: { action in
                                        isClaudeInfoPresented = false
                                        onClaudeAction(action)
                                    }
                                )
                            }
                        }
                    }
                }
                .opacity(isProviderEnabled ? 1 : 0.55)

                Spacer(minLength: 12)

                if isProviderEnabled,
                   provider == .claude,
                   let action = viewModel.claudePresentation.settingsAction {
                    Button(action.title) {
                        onClaudeAction(action)
                    }
                    .controlSize(.small)
                }

                if usesPreviewToggle {
                    PreviewSwitch(isOn: isProviderEnabled)
                } else {
                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(isToggleDisabled)
                }
            }

            if isProviderEnabled,
               provider == .claude,
               let footnote = viewModel.claudePresentation.estimateFootnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 19)
            }
        }
        .padding(.vertical, 2)
        .onChange(of: isProviderEnabled) { _, isEnabled in
            if !isEnabled {
                isClaudeInfoPresented = false
            }
        }
    }
}

private struct PreviewSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.24))
            Circle()
                .fill(Color.white.opacity(0.92))
                .padding(2)
        }
        .frame(width: 34, height: 20)
    }
}

private struct ClaudeMeasurementPopover: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let onClaudeAction: (ClaudeSettingsAction) -> Void

    private static let learnMoreURL = URL(
        string: "https://github.com/jeremyrojas/prompt-juice#how-promptjuice-reads-usage"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How this number is measured")
                .font(.headline)

            Text("PromptJuice reads your Claude plan usage with Claude Code's built-in /usage command. These are the same numbers Claude shows you. Claude Desktop, Claude.ai, and Claude Code share one plan allowance, so this covers all of them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PromptJuice asks Claude Code for your plan usage about every 15 minutes and sends no model prompt. When an estimate is needed, it scans local Claude Code activity records and extracts usage totals and timestamps. It does not store, display, or transmit conversation text.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.claudeMeasurementPopoverDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Learn more") {
                    NSWorkspace.shared.open(Self.learnMoreURL)
                }

                Spacer()

                if let action = viewModel.claudePresentation.popoverAction {
                    Button("Sign In") {
                        onClaudeAction(action)
                    }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 340)
    }
}

private struct UseJuiceThresholdRows: View {
    @ObservedObject var viewModel: PromptJuiceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("When reset is within")
                Spacer()
                minutesPicker
            }
            .frame(minHeight: 38)

            Divider()

            HStack(spacing: 10) {
                Text("and I still have at least")
                Spacer()
                percentPicker
            }
            .frame(minHeight: 38)
        }
        .font(.body)
    }

    private var minutesSelection: Binding<Int> {
        Binding {
            viewModel.thresholds.remainingMinutes
        } set: { minutes in
            viewModel.setRemainingMinutesThreshold(minutes)
        }
    }

    private var percentSelection: Binding<Int> {
        Binding {
            viewModel.thresholds.remainingPercent
        } set: { percent in
            viewModel.setRemainingPercentThreshold(percent)
        }
    }

    private var minutesPicker: some View {
        Picker("Reset window", selection: minutesSelection) {
            ForEach([30, 45, 60, 90], id: \.self) { minutes in
                Text("\(minutes) minutes").tag(minutes)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var percentPicker: some View {
        Picker("Remaining juice", selection: percentSelection) {
            ForEach([25, 40, 50, 60], id: \.self) { percent in
                Text("\(percent)%").tag(percent)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

#if DEBUG
struct ClaudeMeasurementPopoverPreviewShell: View {
    @StateObject private var viewModel: PromptJuiceViewModel

    init(viewModel: PromptJuiceViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ClaudeMeasurementPopover(viewModel: viewModel, onClaudeAction: { _ in })
            .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SettingsProviderRowPreviewShell: View {
    @StateObject private var viewModel: PromptJuiceViewModel
    @State private var isEnabled: Bool

    init(viewModel: PromptJuiceViewModel, isEnabled: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isEnabled = State(initialValue: isEnabled)
    }

    var body: some View {
        ProviderSettingsRow(
            provider: .claude,
            viewModel: viewModel,
            isEnabled: $isEnabled,
            isToggleDisabled: false,
            onClaudeAction: { _ in },
            usesPreviewToggle: true
        )
        .padding(12)
        .frame(width: 390)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#endif
