import AppKit
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
    var usesPreviewToggle = false
    @State private var isClaudeInfoPresented = false
    @State private var isClaudeInfoHovering = false
    @State private var closeClaudeInfoTask: Task<Void, Never>?

    private var claudeInfoPresentation: Binding<Bool> {
        Binding {
            isClaudeInfoPresented
        } set: { isPresented in
            if !isPresented {
                closeClaudeInfoTask?.cancel()
                closeClaudeInfoTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if !isClaudeInfoHovering {
                        isClaudeInfoPresented = false
                    }
                }
                return
            }

            isClaudeInfoPresented = isPresented
        }
    }

    var body: some View {
        let isProviderEnabled = isEnabled.wrappedValue

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
                        ZStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HoverTrackingView { isHovering in
                                handleClaudeInfoHover(isHovering)
                            }
                        }
                            .frame(width: 18, height: 18)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("How this number is measured")
                            .popover(isPresented: claudeInfoPresentation, arrowEdge: .trailing) {
                                ClaudeMeasurementPopover(
                                    viewModel: viewModel,
                                    onSetUpClaude: {
                                        isClaudeInfoPresented = false
                                        onSetUpClaude()
                                    }
                                )
                                .onHover { isHovering in
                                    handleClaudeInfoHover(isHovering)
                                }
                                .interactiveDismissDisabled(true)
                            }
                    }
                }
            }
            .opacity(isProviderEnabled ? 1 : 0.55)

            Spacer(minLength: 12)

            if isProviderEnabled,
               provider == .claude,
               let title = viewModel.claudeSetupButtonTitle {
                Button(title, action: onSetUpClaude)
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
        .padding(.vertical, 2)
        .onDisappear {
            closeClaudeInfoTask?.cancel()
        }
        .onChange(of: isProviderEnabled) { _, isEnabled in
            if !isEnabled {
                closeClaudeInfoTask?.cancel()
                isClaudeInfoPresented = false
            }
        }
    }

    private func handleClaudeInfoHover(_ isHovering: Bool) {
        isClaudeInfoHovering = isHovering
        closeClaudeInfoTask?.cancel()

        if isHovering {
            isClaudeInfoPresented = true
            return
        }

        closeClaudeInfoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            isClaudeInfoPresented = false
        }
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }

        override func mouseDown(with event: NSEvent) {}

        override func mouseUp(with event: NSEvent) {}
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
    let onSetUpClaude: () -> Void

    private static let learnMoreURL = URL(
        string: "https://github.com/jtrojas24/prompt-juice#how-promptjuice-reads-usage"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How this number is measured")
                .font(.headline)

            Text("PromptJuice reads Claude's exact usage from Claude Code's status line, which runs only in the terminal — not the desktop app yet. Otherwise it estimates from your local activity.")
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

                if let title = viewModel.claudeSetupButtonTitle {
                    Button(title, action: onSetUpClaude)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 340)
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
        ClaudeMeasurementPopover(viewModel: viewModel, onSetUpClaude: {})
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
            onSetUpClaude: {},
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

#Preview("Claude setup — wrapping") {
    ClaudeSetupPlanPreviewShell(
        plan: ClaudeSetupPreviewPlans.wrapping()
    )
}

#Preview("Claude setup — no status line") {
    ClaudeSetupPlanPreviewShell(
        plan: ClaudeSetupPreviewPlans.additive()
    )
}

#Preview("Claude setup — wrapping expanded") {
    ClaudeSetupPlanPreviewShell(
        plan: ClaudeSetupPreviewPlans.wrapping(),
        showsCommand: true
    )
}

#Preview("Claude setup — no status line expanded") {
    ClaudeSetupPlanPreviewShell(
        plan: ClaudeSetupPreviewPlans.additive(),
        showsCommand: true
    )
}

#Preview("Claude setup — success") {
    ClaudeSetupSuccessPreviewShell()
}
#endif
