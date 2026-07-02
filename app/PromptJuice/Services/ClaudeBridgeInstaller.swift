import Foundation

/// Installs the Claude statusline bridge with the user's consent: computes the
/// exact change to `~/.claude/settings.json` (additive when there's no existing
/// status line, a non-destructive wrap when there is), then — only when applied —
/// copies the bundled script to Application Support and writes the settings.
struct ClaudeBridgeInstaller {
    static let statusLineRefreshIntervalSeconds = 10
    private static let defaultBundledScriptURL = Bundle.main.url(
        forResource: "claude-statusline-bridge",
        withExtension: "sh"
    )
    private static let defaultBundledScriptData = defaultBundledScriptURL.flatMap { try? Data(contentsOf: $0) }

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
            lines.append("")
            lines.append("Claude Code will refresh PromptJuice usage every \(ClaudeBridgeInstaller.statusLineRefreshIntervalSeconds) seconds while it is open.")
            return lines.joined(separator: "\n")
        }
    }

    let homeDirectory: URL
    let bundledScriptURL: URL?
    let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledScriptURL: URL? = Self.defaultBundledScriptURL,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.bundledScriptURL = bundledScriptURL
        self.fileManager = fileManager
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

        let bridgeInvocation = "bash \(shellSingleQuoted(installedScriptURL.path))"
        var isWrap = false
        var previous: String?
        var newCommand = bridgeInvocation

        if let statusLine = root["statusLine"] as? [String: Any],
           let existing = (statusLine["command"] as? String),
           !existing.isEmpty {
            if commandReferencesInstalledBridge(existing) {
                // The installed Application Support bridge is current; keep the plan idempotent.
                newCommand = existing
            } else if let wrapped = wrappedStatusLineCommand(from: existing) {
                isWrap = true
                previous = wrapped
                newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND=\(shellSingleQuoted(wrapped)) \(bridgeInvocation)"
            } else if existing.contains("claude-statusline-bridge.sh") {
                newCommand = bridgeInvocation
            } else {
                isWrap = true
                previous = existing
                newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND=\(shellSingleQuoted(existing)) \(bridgeInvocation)"
            }
        }

        var newStatusLine = root["statusLine"] as? [String: Any] ?? [:]
        newStatusLine["type"] = "command"
        newStatusLine["command"] = newCommand
        newStatusLine["refreshInterval"] = Self.statusLineRefreshIntervalSeconds
        root["statusLine"] = newStatusLine

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
            newSettingsData: newData
        )
    }

    /// Apply an approved plan: copy the script to Application Support, then write
    /// the merged settings atomically.
    func apply(_ plan: Plan) throws {
        try installBundledBridgeScriptIfNeeded()

        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plan.newSettingsData.write(to: settingsURL, options: .atomic)
    }

    func isBridgeCurrent() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }

        guard commandReferencesInstalledBridge(command),
              statusLineRefreshInterval(statusLine) == Self.statusLineRefreshIntervalSeconds else {
            return false
        }

        return fileManager.fileExists(atPath: installedScriptURL.path)
    }

    func ensureInstalledBridgeCurrent(reason: String = "lifecycle") {
        guard settingsAuthorizeInstalledBridgeSync() else {
            return
        }

        do {
            try installBundledBridgeScriptIfNeeded()
            PromptJuiceLog.usage.debug("Claude bridge script sync passed: \(reason, privacy: .public)")
        } catch {
            PromptJuiceLog.usage.notice(
                "Claude bridge script sync failed: \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func settingsAuthorizeInstalledBridgeSync() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }

        return commandReferencesInstalledBridge(command)
            && statusLineRefreshInterval(statusLine) == Self.statusLineRefreshIntervalSeconds
    }

    private func installBundledBridgeScriptIfNeeded() throws {
        let bundledData = try bundledScriptData()
        let installedData = try? Data(contentsOf: installedScriptURL)
        guard installedData != bundledData else {
            return
        }

        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let tempURL = installDirectory
            .appendingPathComponent(".claude-statusline-bridge.\(UUID().uuidString).tmp")
        try bundledData.write(to: tempURL, options: [])
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
        defer {
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        if fileManager.fileExists(atPath: installedScriptURL.path) {
            _ = try fileManager.replaceItemAt(
                installedScriptURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: tempURL, to: installedScriptURL)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedScriptURL.path)
    }

    private func bundledScriptData() throws -> Data {
        guard let bundledScriptURL else {
            throw InstallError.bundledScriptMissing
        }

        if bundledScriptURL == Self.defaultBundledScriptURL,
           let data = Self.defaultBundledScriptData {
            return data
        }

        return try Data(contentsOf: bundledScriptURL)
    }

    private func statusLineRefreshInterval(_ statusLine: [String: Any]) -> Int? {
        if let value = statusLine["refreshInterval"] as? Int {
            return value
        }

        if let value = statusLine["refreshInterval"] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func wrappedStatusLineCommand(from command: String) -> String? {
        let prefix = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND="
        guard command.hasPrefix(prefix),
              let parsed = parseShellSingleQuotedValue(
                in: command,
                from: command.index(command.startIndex, offsetBy: prefix.count)
              ) else {
            return nil
        }

        let remainder = command[parsed.endIndex...]
        guard remainder.contains("claude-statusline-bridge.sh") else {
            return nil
        }

        return parsed.value
    }

    private func commandReferencesInstalledBridge(_ command: String) -> Bool {
        command.contains(installedScriptURL.path)
            || command.contains(shellSingleQuoted(installedScriptURL.path))
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func parseShellSingleQuotedValue(
        in command: String,
        from startIndex: String.Index
    ) -> (value: String, endIndex: String.Index)? {
        guard startIndex < command.endIndex,
              command[startIndex] == "'" else {
            return nil
        }

        var value = ""
        var scanIndex = command.index(after: startIndex)
        let escapedQuoteSequence = "\\''"

        while scanIndex <= command.endIndex {
            guard let closingQuote = command[scanIndex...].firstIndex(of: "'") else {
                return nil
            }

            value.append(contentsOf: command[scanIndex..<closingQuote])
            var cursor = command.index(after: closingQuote)

            if command[cursor...].hasPrefix(escapedQuoteSequence) {
                value.append("'")
                cursor = command.index(cursor, offsetBy: escapedQuoteSequence.count)
                scanIndex = cursor
                continue
            }

            return (value, cursor)
        }

        return nil
    }
}
