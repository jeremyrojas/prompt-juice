import Foundation

/// Installs the Claude statusline bridge with the user's consent: computes the
/// exact change to `~/.claude/settings.json` (additive when there's no existing
/// status line, a non-destructive wrap when there is), then — only when applied —
/// copies the bundled script to Application Support and writes the settings.
struct ClaudeBridgeInstaller {
    enum InstallError: Error, LocalizedError, Equatable {
        case bundledScriptMissing
        case settingsNotAnObject

        var errorDescription: String? {
            switch self {
            case .bundledScriptMissing:
                return "The bridge script is missing from the app bundle."
            case .settingsNotAnObject:
                return "~/.claude/settings.json isn't a JSON object PromptJuice can edit."
            }
        }
    }

    /// A previewable, approvable change. Computing it has no side effects.
    struct Plan: Equatable {
        let settingsPath: URL
        let installedScriptPath: URL
        let isWrappingExisting: Bool
        let previousCommand: String?
        let newCommand: String
        let newSettingsData: Data
        let jqInstalled: Bool

        /// Plain-language summary for the consent dialog.
        var summary: String {
            var lines: [String] = []
            if isWrappingExisting {
                lines.append("You already have a status line — it keeps working. PromptJuice runs first, then hands off to yours.")
            } else {
                lines.append("Adds one entry to ~/.claude/settings.json so PromptJuice can read your Claude usage.")
            }
            lines.append("")
            lines.append("This will set statusLine.command to:")
            lines.append(newCommand)
            if !jqInstalled {
                lines.append("")
                lines.append("⚠︎ jq isn't installed — the bridge needs it. Install it first with:  brew install jq")
            }
            return lines.joined(separator: "\n")
        }
    }

    let homeDirectory: URL
    let bundledScriptURL: URL?
    let fileManager: FileManager
    private let jqProbe: () -> Bool

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledScriptURL: URL? = Bundle.main.url(forResource: "claude-statusline-bridge", withExtension: "sh"),
        fileManager: FileManager = .default,
        jqProbe: @escaping () -> Bool = ClaudeBridgeInstaller.systemHasJQ
    ) {
        self.homeDirectory = homeDirectory
        self.bundledScriptURL = bundledScriptURL
        self.fileManager = fileManager
        self.jqProbe = jqProbe
    }

    var settingsURL: URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    var installDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/PromptJuice", isDirectory: true)
    }

    var installedScriptURL: URL {
        installDirectory.appendingPathComponent("claude-statusline-bridge.sh")
    }

    /// Compute the planned settings change. No files are written.
    func makePlan() throws -> Plan {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else {
                throw InstallError.settingsNotAnObject
            }
            root = dict
        }

        let bridgeInvocation = "bash '\(installedScriptURL.path)'"
        var isWrap = false
        var previous: String?
        var newCommand = bridgeInvocation

        if let statusLine = root["statusLine"] as? [String: Any],
           let existing = (statusLine["command"] as? String),
           !existing.isEmpty {
            if existing.contains(installedScriptURL.path) {
                // The installed Application Support bridge is current; keep the plan idempotent.
                newCommand = existing
            } else if let wrapped = wrappedStatusLineCommand(from: existing) {
                isWrap = true
                previous = wrapped
                newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(wrapped)' \(bridgeInvocation)"
            } else if existing.contains("claude-statusline-bridge.sh") {
                newCommand = bridgeInvocation
            } else {
                isWrap = true
                previous = existing
                newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(existing)' \(bridgeInvocation)"
            }
        }

        root["statusLine"] = ["type": "command", "command": newCommand]

        let newData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        return Plan(
            settingsPath: settingsURL,
            installedScriptPath: installedScriptURL,
            isWrappingExisting: isWrap,
            previousCommand: previous,
            newCommand: newCommand,
            newSettingsData: newData,
            jqInstalled: jqProbe()
        )
    }

    /// Apply an approved plan: copy the script to Application Support, then write
    /// the merged settings atomically.
    func apply(_ plan: Plan) throws {
        guard let bundledScriptURL else {
            throw InstallError.bundledScriptMissing
        }

        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: installedScriptURL.path) {
            try fileManager.removeItem(at: installedScriptURL)
        }
        try fileManager.copyItem(at: bundledScriptURL, to: installedScriptURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedScriptURL.path)

        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plan.newSettingsData.write(to: settingsURL, options: .atomic)
    }

    func isBridgeCurrent() -> Bool {
        guard fileManager.fileExists(atPath: installedScriptURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }

        return command.contains(installedScriptURL.path)
    }

    /// Probe for `jq` on the user's PATH (a login shell, matching how Claude Code
    /// invokes the bridge).
    static func systemHasJQ() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "command -v jq"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func wrappedStatusLineCommand(from command: String) -> String? {
        let prefix = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='"
        guard command.hasPrefix(prefix),
              let closingQuote = command.dropFirst(prefix.count).firstIndex(of: "'") else {
            return nil
        }

        let remainder = command[closingQuote...]
        guard remainder.contains("claude-statusline-bridge.sh") else {
            return nil
        }

        let valueStart = command.index(command.startIndex, offsetBy: prefix.count)
        return String(command[valueStart..<closingQuote])
    }
}
