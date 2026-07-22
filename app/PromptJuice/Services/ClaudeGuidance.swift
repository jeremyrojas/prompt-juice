import AppKit
import Foundation

struct ClaudeGuidanceCheckResult: Sendable, Equatable {
    let access: ClaudeAccessState
    let location: ClaudeExecutableLocation?

    var nextJourney: ClaudeGuidanceJourney? {
        switch access {
        case .cliMissing:
            .install
        case .updateRequired:
            .update
        case .signedOut:
            .signIn
        case .workspaceTrustRequired:
            .trustWorkspace
        case .checking, .subscription, .apiBilling,
             .externalProvider, .unsupportedAuth, .authCheckFailed:
            nil
        }
    }

    var completesJourney: Bool {
        switch access {
        case .subscription, .apiBilling, .externalProvider, .unsupportedAuth:
            true
        case .checking, .cliMissing, .updateRequired, .workspaceTrustRequired,
             .signedOut, .authCheckFailed:
            false
        }
    }

    func journey(after current: ClaudeGuidanceJourney) -> ClaudeGuidanceJourney {
        nextJourney ?? current
    }
}

protocol ClaudeGuidanceChecking: Sendable {
    func check(journey: ClaudeGuidanceJourney) -> ClaudeGuidanceCheckResult
}

protocol ClaudeWorkspaceTrustChecking: Sendable {
    func checkWorkspaceTrust(
        executableURL: URL,
        workspaceURL: URL,
        environment: [String: String]
    ) -> ClaudeWorkspaceTrustOutcome
}

extension ClaudePTYSession: ClaudeWorkspaceTrustChecking {}

struct SystemClaudeGuidanceChecker: ClaudeGuidanceChecking, @unchecked Sendable {
    let locate: @Sendable () -> ClaudeExecutableLocation?
    let versionProbe: ClaudeVersionProbe
    let authProbe: ClaudeAuthProbe
    let trustProbe: any ClaudeWorkspaceTrustChecking
    let workspace: ClaudeProbeWorkspace
    let environment: [String: String]

    init(
        locate: @escaping @Sendable () -> ClaudeExecutableLocation? = {
            ClaudeExecutableLocator.locate()
        },
        versionProbe: ClaudeVersionProbe = ClaudeVersionProbe(),
        authProbe: ClaudeAuthProbe = ClaudeAuthProbe(),
        trustProbe: any ClaudeWorkspaceTrustChecking = ClaudePTYSession(),
        workspace: ClaudeProbeWorkspace = ClaudeProbeWorkspace(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.locate = locate
        self.versionProbe = versionProbe
        self.authProbe = authProbe
        self.trustProbe = trustProbe
        self.workspace = workspace
        self.environment = environment
    }

    func check(journey: ClaudeGuidanceJourney) -> ClaudeGuidanceCheckResult {
        guard let location = locate() else {
            return ClaudeGuidanceCheckResult(access: .cliMissing, location: nil)
        }

        if journey != .signIn {
            let version = versionProbe.probe(
                executableURL: location.resolvedURL,
                environment: environment
            )
            switch version {
            case .updateRequired(let installed, let minimum):
                return ClaudeGuidanceCheckResult(
                    access: .updateRequired(installed: installed, minimum: minimum),
                    location: location
                )
            case .unreadable:
                return ClaudeGuidanceCheckResult(access: .authCheckFailed, location: location)
            case .supported:
                break
            }
        }

        let authentication = authProbe.probe(
            executableURL: location.resolvedURL,
            environment: environment
        )
        let access = Self.accessState(for: authentication)
        guard journey == .trustWorkspace,
              case .subscription = access else {
            return ClaudeGuidanceCheckResult(access: access, location: location)
        }

        guard let workspaceURL = try? workspace.prepare() else {
            return ClaudeGuidanceCheckResult(access: .authCheckFailed, location: location)
        }
        let trust = trustProbe.checkWorkspaceTrust(
            executableURL: location.resolvedURL,
            workspaceURL: workspaceURL,
            environment: environment
        )
        return ClaudeGuidanceCheckResult(
            access: trust == .ready ? access : .workspaceTrustRequired,
            location: location
        )
    }

    private static func accessState(for authentication: ClaudeAuthentication) -> ClaudeAccessState {
        switch authentication {
        case .subscription(let plan): .subscription(plan: plan)
        case .apiBilling: .apiBilling
        case .externalProvider(let provider): .externalProvider(provider)
        case .signedOut(let reason): .signedOut(reason: reason)
        case .unsupported: .unsupportedAuth
        case .checkFailed: .authCheckFailed
        }
    }
}

struct ClaudeGuidanceCommand: Sendable, Equatable, Identifiable {
    let label: String?
    let value: String

    var id: String {
        "\(label ?? "command"):\(value)"
    }
}

struct ClaudeGuidanceRecheckDebouncer: Sendable, Equatable {
    private(set) var lastCheckAt: Date
    let minimumInterval: TimeInterval

    init(lastCheckAt: Date, minimumInterval: TimeInterval = 30) {
        self.lastCheckAt = lastCheckAt
        self.minimumInterval = minimumInterval
    }

    mutating func shouldCheck(at date: Date) -> Bool {
        guard date.timeIntervalSince(lastCheckAt) >= minimumInterval else {
            return false
        }
        lastCheckAt = date
        return true
    }
}

struct ClaudeGuidanceContent: Sendable, Equatable {
    let journey: ClaudeGuidanceJourney
    let title: String
    let subtitle: String
    let stepOne: String?
    let commands: [ClaudeGuidanceCommand]
    let stepTwo: String?
    let explainer: String
    let versionStatus: String?
    let executablePath: String?
    let primaryCommand: String?
    let terminalWorkspaceURL: URL?

    var primaryButtonTitle: String {
        primaryCommand == nil ? "Open Terminal" : "Copy and Open Terminal"
    }

    static func make(
        journey: ClaudeGuidanceJourney,
        access: ClaudeAccessState,
        location: ClaudeExecutableLocation?
    ) -> ClaudeGuidanceContent {
        switch journey {
        case .install:
            return ClaudeGuidanceContent(
                journey: .install,
                title: "Install Claude Code",
                subtitle: "One-time setup. Claude Desktop, Claude.ai, and Claude Code share the same plan allowance.",
                stepOne: "Get Claude Code at claude.com/claude-code, or run:",
                commands: [ClaudeGuidanceCommand(
                    label: nil,
                    value: "curl -fsSL https://claude.ai/install.sh | bash"
                )],
                stepTwo: "Once installed, sign in with your Claude account",
                explainer: "PromptJuice will copy the command and open Terminal. Paste it, press Return, then come back here. PromptJuice will check again automatically.",
                versionStatus: nil,
                executablePath: nil,
                primaryCommand: "curl -fsSL https://claude.ai/install.sh | bash",
                terminalWorkspaceURL: nil
            )
        case .signIn:
            return ClaudeGuidanceContent(
                journey: .signIn,
                title: "Sign in to Claude Code",
                subtitle: "Use the same Claude account you use in Claude Desktop or Claude.ai.",
                stepOne: "Run the sign-in command:",
                commands: [ClaudeGuidanceCommand(label: nil, value: "claude auth login")],
                stepTwo: "Complete the browser prompts, then return to PromptJuice. Already inside Claude Code? Type /login instead.",
                explainer: "PromptJuice will copy the command and open Terminal. Paste it, press Return, then follow the browser prompts. PromptJuice will check again automatically.",
                versionStatus: nil,
                executablePath: nil,
                primaryCommand: "claude auth login",
                terminalWorkspaceURL: nil
            )
        case .update:
            let installedVersion: String? = if case .updateRequired(let installed, _) = access {
                installed.description
            } else {
                nil
            }
            let minimumVersion: String = if case .updateRequired(_, let minimum) = access {
                minimum.description
            } else {
                ClaudeCodeVersion.minimumUsageVersion.description
            }
            let versionStatus = installedVersion.map {
                "Current version \($0) · required \(minimumVersion)"
            }
            if let command = location?.provenance.updateCommand {
                return ClaudeGuidanceContent(
                    journey: .update,
                    title: "Update Claude Code",
                    subtitle: "PromptJuice needs Claude Code \(minimumVersion) or newer to read plan usage.",
                    stepOne: "Run the update command:",
                    commands: [ClaudeGuidanceCommand(label: nil, value: command)],
                    stepTwo: "PromptJuice picks up the new version automatically.",
                    explainer: "PromptJuice will copy the command and open Terminal. Paste it, press Return, then come back here. PromptJuice will check again automatically.",
                    versionStatus: versionStatus,
                    executablePath: nil,
                    primaryCommand: command,
                    terminalWorkspaceURL: nil
                )
            }
            return ClaudeGuidanceContent(
                journey: .update,
                title: "Update Claude Code",
                subtitle: "PromptJuice found Claude Code at a path it doesn't recognize, so it won't guess your update command.",
                stepOne: "Run the command that matches how you installed it:",
                commands: [
                    ClaudeGuidanceCommand(label: "Native install", value: "claude update"),
                    ClaudeGuidanceCommand(label: "Homebrew", value: "brew upgrade claude-code"),
                    ClaudeGuidanceCommand(label: "npm", value: "npm install -g @anthropic-ai/claude-code@latest"),
                ],
                stepTwo: nil,
                explainer: "PromptJuice will open Terminal. Copy the command that matches your install, paste it, press Return, then come back here. PromptJuice will check again automatically.",
                versionStatus: versionStatus,
                executablePath: location?.resolvedURL.path,
                primaryCommand: nil,
                terminalWorkspaceURL: nil
            )
        case .trustWorkspace:
            return ClaudeGuidanceContent(
                journey: .trustWorkspace,
                title: "Trust PromptJuice's Claude workspace",
                subtitle: "Claude Code asks you to trust this dedicated empty workspace once before PromptJuice can read plan usage.",
                stepOne: "Open Terminal in PromptJuice's Claude workspace, then run:",
                commands: [ClaudeGuidanceCommand(
                    label: nil,
                    value: "claude --safe-mode --ax-screen-reader --allowed-tools \"\""
                )],
                stepTwo: "Choose Yes, I trust this folder in Claude Code, then return to PromptJuice.",
                explainer: "PromptJuice will open Terminal in its dedicated empty workspace. Run the command shown above, accept Claude Code's trust prompt, then come back here. PromptJuice will check again automatically.",
                versionStatus: nil,
                executablePath: ClaudeProbeWorkspace().url.path,
                primaryCommand: nil,
                terminalWorkspaceURL: ClaudeProbeWorkspace().url
            )
        }
    }
}

@MainActor
struct ClaudeTerminalLauncher {
    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    static func open(command: String?, workspaceURL: URL? = nil) {
        if let command {
            copy(command)
        }

        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        if let workspaceURL {
            NSWorkspace.shared.open(
                [workspaceURL],
                withApplicationAt: terminalURL,
                configuration: configuration
            )
        } else {
            NSWorkspace.shared.openApplication(
                at: terminalURL,
                configuration: configuration
            )
        }
    }
}
