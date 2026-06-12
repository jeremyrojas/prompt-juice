import SwiftUI

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
        .frame(width: 430, height: 400)
        .sheet(isPresented: $state.isClaudeSetupPresented) {
            ClaudeSetupConsentView(
                viewModel: viewModel,
                isPresented: $state.isClaudeSetupPresented
            )
        }
    }

    private var settingsForm: some View {
        Form {
            providersSection
            nudgeSection
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
                Text("Keep at least one on")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 54, height: 54)

                DropletGauge(
                    remaining: 0.66,
                    tint: .orange,
                    lineWidth: 2
                )
                .frame(width: 25, height: 29)
            }

            Text("Welcome to PromptJuice")
                .font(.title3.weight(.semibold))

            Text("Pick the providers you use. The Juicebar only watches what you turn on — change it anytime in Settings.")
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
                    onSetUpClaude: {
                        state.isClaudeSetupPresented = true
                    }
                )
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("PromptJuice only watches providers that are on. Keep at least one on.")
                .font(.footnote)
        }
    }

    private var firstRunProvidersSection: some View {
        Section {
            ForEach(UsageProvider.allCases) { provider in
                ProviderSettingsRow(
                    provider: provider,
                    viewModel: viewModel,
                    isEnabled: firstRunProviderBinding(for: provider),
                    isToggleDisabled: false,
                    onSetUpClaude: {
                        state.isClaudeSetupPresented = true
                    }
                )
            }
        }
    }

    private var nudgeSection: some View {
        Section {
            NudgeSettingsRow(viewModel: viewModel)
        } header: {
            Text("Nudge")
        } footer: {
            Text("The amber Use Soon nudge is the only alert. Everything else stays calm.")
                .font(.footnote)
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
}

private struct ProviderSettingsRow: View {
    let provider: UsageProvider
    @ObservedObject var viewModel: PromptJuiceViewModel
    let isEnabled: Binding<Bool>
    let isToggleDisabled: Bool
    let onSetUpClaude: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(provider == .claude ? Color.orange : Color.cyan)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.rawValue)
                    .font(.body)
                Text(viewModel.settingsStatusText(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if provider == .claude, viewModel.isUnavailable(.claude) {
                Button("Set Up…", action: onSetUpClaude)
                    .controlSize(.small)
            }

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isToggleDisabled)
        }
        .padding(.vertical, 2)
    }
}

private struct NudgeSettingsRow: View {
    @ObservedObject var viewModel: PromptJuiceViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text("Nudge me when reset is within")
                minutesPicker
                Text("and I still have at least")
                percentPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Nudge me when reset is within")
                    minutesPicker
                }
                HStack(spacing: 6) {
                    Text("and I still have at least")
                    percentPicker
                }
            }
        }
        .font(.body)
        .padding(.vertical, 2)
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

private struct ClaudeSetupConsentView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    @Binding var isPresented: Bool

    private let installer = ClaudeBridgeInstaller()
    @State private var plan: ClaudeBridgeInstaller.Plan?
    @State private var errorMessage: String?
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Claude usage")
                .font(.title3.weight(.semibold))

            if let plan {
                planDetails(plan)
            } else if let errorMessage {
                errorRow(errorMessage)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Add to Claude Code") {
                    applyPlan()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil || isApplying)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear(perform: loadPlan)
    }

    private func planDetails(_ plan: ClaudeBridgeInstaller.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if plan.isWrappingExisting, let previousCommand = plan.previousCommand {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your existing status line keeps working. PromptJuice runs first, then hands off.")
                        .foregroundStyle(.secondary)
                    codeBox(previousCommand)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                codeBox(plan.newCommand)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                codeBox(plan.settingsPath.path)
            }

            if !plan.jqInstalled {
                warningRow("jq is required. Install it with: brew install jq")
            }

            if let errorMessage {
                errorRow(errorMessage)
            }
        }
    }

    private func codeBox(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.10))
        )
    }

    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func loadPlan() {
        guard plan == nil, errorMessage == nil else {
            return
        }

        do {
            plan = try installer.makePlan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPlan() {
        guard let plan else {
            return
        }

        isApplying = true
        do {
            try installer.apply(plan)
            viewModel.refreshUsage()
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
            isApplying = false
        }
    }
}
