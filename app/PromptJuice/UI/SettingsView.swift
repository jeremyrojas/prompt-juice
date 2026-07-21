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
        .sheet(isPresented: $state.isLegacyBridgeRemovalPresented) {
            ClaudeLegacyBridgeRemovalSheet(
                viewModel: viewModel,
                remover: viewModel.claudeLegacyBridgeRemoval,
                onDone: {
                    state.isLegacyBridgeRemovalPresented = false
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

            if viewModel.usesClaudeUsagePresentation,
               viewModel.legacyBridgeStatus == .removable {
                ClaudeLegacyBridgeCard {
                    state.isLegacyBridgeRemovalPresented = true
                }
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

private struct ClaudeLegacyBridgeCard: View {
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Legacy bridge detected")
                .font(.callout.weight(.semibold))

            Text("PromptJuice's old status-line bridge is still in ~/.claude/settings.json. It's no longer needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Remove…", action: onRemove)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ClaudeLegacyBridgeRemovalSheet: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let remover: ClaudeLegacyBridgeRemoval
    let onDone: () -> Void

    @State private var plan: ClaudeLegacyBridgeRemoval.Plan?
    @State private var errorMessage: String?
    @State private var isRemoving = false
    @State private var didRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if didRemove {
                Label("Bridge removed", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)

                Text("Your Claude settings are back to normal. Usage now comes from Claude Code's /usage.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Remove the legacy bridge")
                    .font(.title3.weight(.semibold))

                Text("PromptJuice no longer needs this. Your previous status line comes back exactly as it was.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let plan {
                    Text("PromptJuice restores statusLine.command in ~/.claude/settings.json to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(plan.restoredCommand ?? "No status line")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.10))
                        )

                    Text("▪︎ Your command, restored   ▫︎ PromptJuice bridge, removed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if errorMessage == nil {
                    ProgressView()
                        .controlSize(.small)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onDone)
                    Button("Remove Bridge", action: applyRemoval)
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan == nil || isRemoving)
                }
            }
        }
        .padding(22)
        .frame(width: 430)
        .onAppear(perform: loadPlan)
    }

    private func loadPlan() {
        guard plan == nil, errorMessage == nil else {
            return
        }
        guard let removalPlan = remover.makePlan() else {
            errorMessage = "PromptJuice couldn't verify ownership of this bridge, so it left your Claude settings untouched."
            return
        }
        plan = removalPlan
    }

    private func applyRemoval() {
        guard let plan else {
            return
        }
        isRemoving = true
        do {
            try remover.apply(plan)
            viewModel.refreshClaudeBridgeState()
            didRemove = true
        } catch {
            errorMessage = error.localizedDescription
            isRemoving = false
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
                   let action = viewModel.claudePresentation.settingsAction,
                   viewModel.usesClaudeUsagePresentation {
                    Button(action.title) {
                        onClaudeAction(action)
                    }
                    .controlSize(.small)
                } else if isProviderEnabled,
                          provider == .claude,
                          let title = viewModel.claudeSetupButtonTitle {
                    Button(title) {
                        onClaudeAction(.journey(.install))
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
               viewModel.usesClaudeUsagePresentation,
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

                if viewModel.usesClaudeUsagePresentation,
                   let action = viewModel.claudePresentation.popoverAction {
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

private struct ClaudeSetupConsentView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    @Binding var isPresented: Bool

    private let installer = ClaudeBridgeInstaller()
    @State private var plan: ClaudeBridgeInstaller.Plan?
    @State private var errorMessage: String?
    @State private var isApplying = false
    @State private var showsCommand = false
    @State private var didInstall = false

    var body: some View {
        if didInstall {
            ClaudeSetupSuccessView {
                isPresented = false
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up live Claude readings")
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
                    Button("Enable Live Readings") {
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
    }

    private func planDetails(_ plan: ClaudeBridgeInstaller.Plan) -> some View {
        ClaudeSetupPlanBody(
            plan: plan,
            errorMessage: errorMessage,
            showsCommand: $showsCommand
        )
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
            viewModel.refreshClaudeBridgeState()
            viewModel.refreshUsage()
            didInstall = true
        } catch {
            errorMessage = error.localizedDescription
            isApplying = false
        }
    }
}

private struct ClaudeSetupSuccessView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                Text("You're almost set")
                    .font(.title3.weight(.semibold))
            }

            Text("PromptJuice is ready to read exact usage from Claude Code statusline updates.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

private struct ClaudeSetupPlanBody: View {
    let plan: ClaudeBridgeInstaller.Plan
    let errorMessage: String?
    @Binding var showsCommand: Bool

    private var introText: String {
        if plan.isWrappingExisting {
            return "PromptJuice adds a small bridge to Claude Code so it can read your exact usage. Your current status line keeps working — the bridge runs it right after."
        }

        return "PromptJuice adds a small bridge to Claude Code so it can read your exact usage."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(introText)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ClaudeSetupTrustRow(
                systemImage: "lock",
                text: "Reads only your usage percentage and reset time — never your prompts, code, or files."
            )
            ClaudeSetupTrustRow(
                systemImage: "terminal",
                text: "Live readings need Claude Code in the terminal — the desktop app isn't supported yet."
            )

            ClaudeSetupUpdatesRow(settingsPath: plan.settingsPath.path)

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsCommand.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsCommand ? 90 : 0))
                        Text("The exact change")
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("The exact change")
                .accessibilityValue(showsCommand ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows the exact line PromptJuice adds to your Claude settings.")

                if showsCommand {
                    ClaudeSetupCommandDisclosureBody(plan: plan)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }

            if let errorMessage {
                ClaudeSetupErrorRow(text: errorMessage)
            }
        }
    }
}

private struct ClaudeSetupTrustRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 16)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct ClaudeSetupUpdatesRow: View {
    let settingsPath: String

    private var abbreviatedPath: String {
        (settingsPath as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            Text("Updates")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(abbreviatedPath)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.10))
        )
    }
}

private struct ClaudeSetupCommandDisclosureBody: View {
    let plan: ClaudeBridgeInstaller.Plan

    private static let userCommandHighlight = Color.accentColor.opacity(0.28)
    private static let bridgeHighlight = Color.green.opacity(0.22)

    private var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private var displayCommand: String {
        plan.newCommand.replacingOccurrences(of: homePath, with: "~")
    }

    private var displayBridgePath: String {
        plan.installedScriptPath.path.replacingOccurrences(of: homePath, with: "~")
    }

    private var displayPreviousCommand: String? {
        plan.previousCommand?.replacingOccurrences(of: homePath, with: "~")
    }

    private var highlightedCommand: AttributedString {
        var command = AttributedString(displayCommand)

        if let range = command.range(of: displayBridgePath) {
            command[range].backgroundColor = Self.bridgeHighlight
        }

        if plan.isWrappingExisting,
           let displayPreviousCommand,
           let range = command.range(of: displayPreviousCommand) {
            command[range].backgroundColor = Self.userCommandHighlight
        }

        return command
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            commandCaption
            codeBox(highlightedCommand)
            legend
        }
    }

    private var commandCaption: some View {
        (
            Text("PromptJuice sets ")
            + Text("statusLine.command").font(.system(.footnote, design: .monospaced))
            + Text(" in ")
            + Text("~/.claude/settings.json").font(.system(.footnote, design: .monospaced))
            + Text(" to:")
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            if plan.isWrappingExisting {
                legendRow(
                    color: Self.userCommandHighlight,
                    text: "Your command — kept, runs unchanged"
                )
            }
            legendRow(
                color: Self.bridgeHighlight,
                text: "PromptJuice bridge — installed in ~/Library/Application Support/PromptJuice"
            )
        }
    }

    private func codeBox(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
            )
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)

            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }
}

private struct ClaudeSetupErrorRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }
}

#if DEBUG
struct ClaudeSetupPlanPreviewShell: View {
    let plan: ClaudeBridgeInstaller.Plan
    @State private var showsCommand: Bool

    init(plan: ClaudeBridgeInstaller.Plan, showsCommand: Bool = false) {
        self.plan = plan
        _showsCommand = State(initialValue: showsCommand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up live Claude readings")
                .font(.title3.weight(.semibold))

            ClaudeSetupPlanBody(
                plan: plan,
                errorMessage: nil,
                showsCommand: $showsCommand
            )

            HStack {
                Spacer()
                Button("Cancel") {}
                Button("Enable Live Readings") {}
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ClaudeSetupSuccessPreviewShell: View {
    var body: some View {
        ClaudeSetupSuccessView {}
            .background(Color(NSColor.windowBackgroundColor))
    }
}

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

private enum ClaudeSetupPreviewPlans {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private static var settingsPath: URL {
        home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static var installedScriptPath: URL {
        home
            .appendingPathComponent("Library/Application Support/PromptJuice", isDirectory: true)
            .appendingPathComponent("claude-statusline-bridge.sh")
    }

    static func wrapping() -> ClaudeBridgeInstaller.Plan {
        let previousCommand = "bash ~/.claude/statusline-command.sh"
        let newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(previousCommand)' bash '\(installedScriptPath.path)'"

        return ClaudeBridgeInstaller.Plan(
            settingsPath: settingsPath,
            installedScriptPath: installedScriptPath,
            isWrappingExisting: true,
            previousCommand: previousCommand,
            newCommand: newCommand,
            newSettingsData: Data()
        )
    }

    static func additive() -> ClaudeBridgeInstaller.Plan {
        ClaudeBridgeInstaller.Plan(
            settingsPath: settingsPath,
            installedScriptPath: installedScriptPath,
            isWrappingExisting: false,
            previousCommand: nil,
            newCommand: "bash '\(installedScriptPath.path)'",
            newSettingsData: Data()
        )
    }
}

#endif
