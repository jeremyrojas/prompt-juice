import AppKit
import SwiftUI

struct ClaudeGuidanceSheetView: View {
    @ObservedObject var viewModel: PromptJuiceViewModel
    let initialJourney: ClaudeGuidanceJourney
    let onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var journey: ClaudeGuidanceJourney
    @State private var isChecking = false
    @State private var activationDebouncer = ClaudeGuidanceRecheckDebouncer(lastCheckAt: Date())

    init(
        viewModel: PromptJuiceViewModel,
        initialJourney: ClaudeGuidanceJourney,
        onDone: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.initialJourney = initialJourney
        self.onDone = onDone
        _journey = State(initialValue: initialJourney)
    }

    private var content: ClaudeGuidanceContent {
        viewModel.claudeGuidanceContent(for: journey)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                guidanceBody
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            actionRow
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.bar)
        }
        .frame(width: 368, height: preferredHeight)
        .accessibilityIdentifier("claude-guidance-sheet")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let now = Date()
            guard activationDebouncer.shouldCheck(at: now) else {
                return
            }
            checkAgain()
        }
    }

    private var preferredHeight: CGFloat {
        dynamicTypeSize >= .xxxLarge ? 739 : 550
    }

    private var guidanceBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.title)
                .font(.title3.weight(.semibold))

            Text(content.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let executablePath = content.executablePath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code is at:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CommandBlock(command: executablePath, showsCopyButton: false)
                }
            }

            if let stepOne = content.stepOne {
                GuidanceStep(number: 1, text: stepOne)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(content.commands) { command in
                    if let label = command.label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    CommandBlock(command: command.value, showsCopyButton: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let stepTwo = content.stepTwo {
                GuidanceStep(number: 2, text: stepTwo)
            }

            Text(content.explainer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let versionStatus = content.versionStatus {
                Label(versionStatus, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Check Again") {
                checkAgain()
            }
            .lineLimit(1)
            .disabled(isChecking)
            .accessibilityIdentifier("claude-guidance-check-again")

            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking Claude Code")
            }

            Spacer(minLength: 4)

            Button("Done", action: onDone)
                .lineLimit(1)

            Button {
                ClaudeTerminalLauncher.open(
                    command: content.primaryCommand,
                    workspaceURL: content.terminalWorkspaceURL
                )
            } label: {
                Text(content.primaryButtonTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .keyboardShortcut(.defaultAction)
            .layoutPriority(1)
            .accessibilityIdentifier("claude-guidance-open-terminal")
        }
        .controlSize(.small)
    }

    private func checkAgain() {
        guard !isChecking else {
            return
        }
        isChecking = true
        let currentJourney = journey
        Task { @MainActor in
            let result = await viewModel.recheckClaudeGuidance(currentJourney)
            isChecking = false
            if result.completesJourney {
                onDone()
                return
            }
            journey = result.journey(after: currentJourney)
        }
    }
}

private struct GuidanceStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.16)))

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CommandBlock: View {
    let command: String
    let showsCopyButton: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsCopyButton {
                Button {
                    ClaudeTerminalLauncher.copy(command)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy command")
                .accessibilityValue(command)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

#if DEBUG
struct ClaudeGuidancePreviewShell: View {
    @StateObject private var viewModel: PromptJuiceViewModel
    let journey: ClaudeGuidanceJourney

    init(viewModel: PromptJuiceViewModel, journey: ClaudeGuidanceJourney) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.journey = journey
    }

    var body: some View {
        ClaudeGuidanceSheetView(
            viewModel: viewModel,
            initialJourney: journey,
            onDone: {}
        )
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
